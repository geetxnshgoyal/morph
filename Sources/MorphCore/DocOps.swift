import Foundation
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum DocOps {
    public static let outputFormats: [String] = {
        #if os(macOS)
        ["pdf", "docx", "odt", "rtf", "html", "md", "txt"]
        #else
        ["pdf", "rtf", "html", "md", "txt"]
        #endif
    }()

    public static func readString(from url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .windowsCP1252) { return text }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
        if let text = try? String(contentsOf: url, encoding: .utf16) { return text }
        return try String(contentsOf: url)
    }

    public static func read(_ url: URL) throws -> NSAttributedString {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try PDFOps.attributedText(of: url)
        case "md", "markdown":
            let text = try readString(from: url)
            let attr = try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return NSAttributedString(attr)
        case "txt", "text", "csv", "tsv", "json", "srt", "vtt":
            return NSAttributedString(string: try readString(from: url))
        default:
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
    }

    public static func convert(_ url: URL, to ext: String, options: Options) throws -> URL {
        let attr = try read(url)
        let out = Output.url(for: url, ext: ext, options: options)
        let range = NSRange(location: 0, length: attr.length)
        switch ext {
        case "txt", "md":
            try attr.string.write(to: out, atomically: true, encoding: .utf8)
        case "pdf":
            try renderPDF(attr, to: out)
        case "rtf":
            try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: out)
        case "html":
            try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]).write(to: out)
        #if os(macOS)
        case "docx":
            try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: out)
        case "odt":
            try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.openDocument]).write(to: out)
        #endif
        default:
            throw MorphError("Can't write .\(ext) documents")
        }
        return out
    }

    /// Paginates with CoreText onto US Letter pages with 0.75in margins.
    static func renderPDF(_ attr: NSAttributedString, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw MorphError("Couldn't create PDF") }
        let source = attr.length > 0 ? attr : NSAttributedString(string: " ")
        let framesetter = CTFramesetterCreateWithAttributedString(source)
        let path = CGPath(rect: box.insetBy(dx: 54, dy: 54), transform: nil)
        var start = 0
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame).length
            if visible == 0 { break }
            start += visible
        } while start < source.length
        ctx.closePDF()
    }

    // MARK: Subtitles

    public static func convertSubtitle(_ url: URL, to ext: String, options: Options) throws -> URL {
        let text = try readString(from: url).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let out = Output.url(for: url, ext: ext, options: options)
        let timing = try NSRegularExpression(pattern: #"(\d{2}:\d{2}:\d{2})[.,](\d{3})"#)
        func retime(_ line: String, sep: String) -> String {
            timing.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "$1\(sep)$2")
        }
        let cues = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .newlines) }.filter { $0.contains("-->") }
        var result: String
        if ext == "vtt" {
            result = "WEBVTT\n\n" + cues.map { cue in
                cue.split(separator: "\n", omittingEmptySubsequences: false)
                    .drop(while: { !$0.contains("-->") })
                    .map { $0.contains("-->") ? retime(String($0), sep: ".") : String($0) }
                    .joined(separator: "\n")
            }.joined(separator: "\n\n")
        } else {
            result = cues.enumerated().map { i, cue in
                let lines = cue.split(separator: "\n", omittingEmptySubsequences: false).drop(while: { !$0.contains("-->") })
                    .map { $0.contains("-->") ? retime(String($0), sep: ",").components(separatedBy: " ").prefix(3).joined(separator: " ") : String($0) }
                return "\(i + 1)\n" + lines.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }
        try (result + "\n").write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    // MARK: Data tables

    static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var chars = normalized.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == separator {
                row.append(field); field = ""
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func formatDelimited(_ rows: [[String]], separator: String) -> String {
        rows.map { row in
            row.map { f in
                f.contains(separator) || f.contains("\"") || f.contains("\n")
                    ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: separator)
        }.joined(separator: "\n") + "\n"
    }

    public static func convertData(_ url: URL, to ext: String, options: Options) throws -> URL {
        let input = url.pathExtension.lowercased()
        let text = try readString(from: url)
        var rows: [[String]]
        if input == "json" {
            guard let objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else {
                throw MorphError("JSON must be an array of objects")
            }
            var headers: [String] = []
            for o in objects { for k in o.keys.sorted() where !headers.contains(k) { headers.append(k) } }
            rows = [headers] + objects.map { o in headers.map { o[$0].map { "\($0)" } ?? "" } }
        } else {
            rows = parseDelimited(text, separator: input == "tsv" ? "\t" : ",")
        }
        let out = Output.url(for: url, ext: ext, options: options)
        switch ext {
        case "json":
            guard let headers = rows.first else { throw MorphError("Empty table") }
            let objects = rows.dropFirst().map { r in
                Dictionary(headers.enumerated().map { ($1, $0 < r.count ? r[$0] : "") }, uniquingKeysWith: { first, _ in first })
            }
            try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]).write(to: out)
        case "tsv":
            try formatDelimited(rows, separator: "\t").write(to: out, atomically: true, encoding: .utf8)
        default:
            try formatDelimited(rows, separator: ",").write(to: out, atomically: true, encoding: .utf8)
        }
        return out
    }
}
