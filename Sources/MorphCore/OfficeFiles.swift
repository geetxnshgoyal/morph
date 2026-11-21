import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Slides and spreadsheets: PowerPoint, Excel and OpenDocument read from their XML, plus Keynote, Numbers, Pages
/// and the old binary Office formats through LibreOffice when it's installed (Mac outside the App Store only).
public enum OfficeFiles {
    static let slides: Set<String> = ["pptx", "ppsx", "potx", "odp"]
    static let sheets: Set<String> = ["xlsx", "xlsm", "ods"]
    /// Need LibreOffice to open; each is turned into its modern counterpart first.
    static let legacy: [String: String] = ["ppt": "pptx", "pps": "pptx", "key": "pptx", "xls": "xlsx", "numbers": "xlsx", "pages": "docx"]
    /// Office files are zips; these folders hold the pictures placed in them.
    static let mediaFolders = ["ppt/media/", "word/media/", "xl/media/", "Pictures/"]

    // MARK: LibreOffice

    static var libreOffice: URL? {
        #if os(macOS)
        guard !Sandbox.isActive else { return nil }
        let app = URL(fileURLWithPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice")
        return FileManager.default.isExecutableFile(atPath: app.path) ? app : ExternalTool.find("soffice")
        #else
        return nil
        #endif
    }

    /// Whether a legacy format can be opened here (it has a FileKind only then, so no action is offered that would fail).
    static func canOpen(_ ext: String) -> Bool { legacy[ext] == nil || libreOffice != nil }

    /// LibreOffice's own export, into `out`'s folder under `out`'s name.
    static func export(_ url: URL, as ext: String, to out: URL) async throws {
        #if os(macOS)
        guard let soffice = libreOffice else { throw MorphError("Opening .\(url.pathExtension) needs LibreOffice (libreoffice.org)") }
        let tmp = try Output.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Its own profile, so a LibreOffice window the user has open doesn't swallow the job.
        try await ExternalTool.run(soffice, ["-env:UserInstallation=file://\(tmp.path)/profile", "--headless", "--norestore",
                                             "--convert-to", ext, "--outdir", tmp.path, url.path])
        let made = tmp.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension(ext)
        guard FileManager.default.fileExists(atPath: made.path) else { throw MorphError("LibreOffice couldn't convert \(url.lastPathComponent)") }
        try FileManager.default.moveItem(at: made, to: out)
        #else
        throw MorphError("Opening .\(url.pathExtension) needs LibreOffice, which isn't available on this device")
        #endif
    }

    /// Runs `body` on a legacy file's modern counterpart (made in a temporary folder, results still saved next to
    /// the original), or on the file itself.
    static func withModern(_ url: URL, _ options: Options, _ body: (URL, Options) throws -> URL) async throws -> URL {
        guard let ext = legacy[url.pathExtension.lowercased()] else { return try body(url, options) }
        let tmp = try Output.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension(ext)
        try await export(url, as: ext, to: copy)
        var o = options
        o.outputDirectory = o.outputDirectory ?? url.deletingLastPathComponent()
        return try body(copy, o)
    }

    /// Slides, sheets and old formats get LibreOffice's PDF where it's installed: the real layout, not just the text.
    static func prefersLibreOfficePDF(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return libreOffice != nil && (slides.contains(ext) || sheets.contains(ext) || legacy[ext] != nil)
    }

    // MARK: Reading

    /// Each slide's text under a "Slide n" heading.
    static func readSlides(_ url: URL) throws -> NSAttributedString {
        let entries = try Zip.read(url)
        let result = NSMutableAttributedString()
        func heading(_ text: String) {
            #if os(macOS)
            let font = NSFont.boldSystemFont(ofSize: 20)
            #else
            let font = UIFont.boldSystemFont(ofSize: 20)
            #endif
            result.append(NSAttributedString(string: text + "\n", attributes: [.font: font]))
        }
        if url.pathExtension.lowercased() == "odp" {
            guard let xml = entries["content.xml"] else { throw MorphError("This presentation has no content") }
            // shortcut: an ODP's slides run together without "Slide n" headings; split on draw:page if people ask.
            result.append(try OfficeDocs.Reader(xml: xml, namespace: "text", paragraph: ["p"], heading: ["h"], text: nil, styles: nil).attributed())
            return result
        }
        let numbered = entries.keys.compactMap { key -> (Int, Data)? in
            guard key.hasPrefix("ppt/slides/slide"), key.hasSuffix(".xml"),
                  let n = Int(key.dropFirst(16).dropLast(4)), let xml = entries[key] else { return nil }
            return (n, xml)
        }.sorted { $0.0 < $1.0 }
        guard !numbered.isEmpty else { throw MorphError("This presentation has no slides") }
        for (i, (_, xml)) in numbered.enumerated() {
            heading("Slide \(i + 1)")
            result.append(try OfficeDocs.Reader(xml: xml, namespace: "a", paragraph: ["p"], heading: [], text: "t", styles: nil).attributed())
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    /// Every sheet's cells, in sheet order.
    static func readSheets(_ url: URL) throws -> [(name: String, rows: [[String]])] {
        let entries = try Zip.read(url)
        if url.pathExtension.lowercased() == "ods" {
            guard let xml = entries["content.xml"] else { throw MorphError("This spreadsheet has no content") }
            return odsSheets(xml)
        }
        var shared: [String] = []
        if let xml = entries["xl/sharedStrings.xml"] {
            var current: String?
            var inText = false, inPhonetic = false
            XMLWalk(xml, start: { name, _ in
                switch name {
                case "si": current = ""
                case "rPh": inPhonetic = true
                case "t": inText = !inPhonetic
                default: break
                }
            }, text: { if inText { current? += $0 } }, end: { name in
                switch name {
                case "si": shared.append(current ?? ""); current = nil
                case "rPh": inPhonetic = false
                case "t": inText = false
                default: break
                }
            })
        }
        // Sheet names and order from the workbook, their files from its relationships.
        var targets: [String: String] = [:], order: [(name: String, id: String)] = []
        if let rels = entries["xl/_rels/workbook.xml.rels"] {
            XMLWalk(rels, start: { name, a in if name == "Relationship", let id = a["Id"], let t = a["Target"] { targets[id] = t } })
        }
        if let book = entries["xl/workbook.xml"] {
            XMLWalk(book, start: { name, a in if name == "sheet", let n = a["name"], let id = a["r:id"] { order.append((n, id)) } })
        }
        var files: [(String, String)] = order.compactMap { s in
            targets[s.id].map { t in (s.name, t.hasPrefix("/") ? String(t.dropFirst()) : "xl/" + t) }
        }
        if files.isEmpty {
            files = entries.keys.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted().map { ($0, $0) }
        }
        return files.compactMap { name, path in entries[path].map { (name, xlsxRows($0, shared: shared)) } }
    }

    private static func xlsxRows(_ xml: Data, shared: [String]) -> [[String]] {
        var rows: [Int: [Int: String]] = [:]
        var row = 0, col = 0, type = "", value = "", inValue = false
        func column(_ ref: String) -> Int? {
            let letters = ref.prefix { $0.isLetter }
            guard !letters.isEmpty else { return nil }
            return letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        }
        XMLWalk(xml, start: { name, a in
            switch name {
            case "row": row = Int(a["r"] ?? "") ?? row + 1; col = -1
            case "c": col = a["r"].flatMap(column) ?? col + 1; type = a["t"] ?? ""; value = ""
            case "v", "t": inValue = true
            default: break
            }
        }, text: { if inValue { value += $0 } }, end: { name in
            switch name {
            case "v", "t": inValue = false
            case "c":
                var text = value
                if type == "s" { text = Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "" }
                if type == "b" { text = value == "1" ? "TRUE" : "FALSE" }
                // shortcut: dates come out as Excel's day numbers (45000), not formatted dates.
                if !text.isEmpty { rows[row - 1, default: [:]][col] = text }
            default: break
            }
        })
        return grid(rows)
    }

    private static func odsSheets(_ xml: Data) -> [(name: String, rows: [[String]])] {
        var sheets: [(name: String, rows: [[String]])] = []
        var rows: [Int: [Int: String]] = [:]
        var name = "", row = 0, col = 0, rowRepeat = 1, cellRepeat = 1, cell = "", paragraphs = 0, inCell = false
        XMLWalk(xml, start: { el, a in
            switch el {
            case "table:table": name = a["table:name"] ?? "Sheet \(sheets.count + 1)"; rows = [:]; row = 0
            case "table:table-row": col = 0; rowRepeat = min(Int(a["table:number-rows-repeated"] ?? "") ?? 1, 10_000)
            case "table:table-cell", "table:covered-table-cell":
                inCell = true; cell = ""; paragraphs = 0; cellRepeat = min(Int(a["table:number-columns-repeated"] ?? "") ?? 1, 1_000)
            case "text:p": if inCell { if paragraphs > 0 { cell += "\n" }; paragraphs += 1 }
            case "text:s": if inCell { cell += String(repeating: " ", count: Int(a["text:c"] ?? "") ?? 1) }
            case "text:tab": if inCell { cell += "\t" }
            default: break
            }
        }, text: { if inCell { cell += $0 } }, end: { el in
            switch el {
            case "table:table-cell", "table:covered-table-cell":
                // Repeats are how ODS fills the empty rest of a sheet (a million cells); only filled ones are kept.
                if !cell.isEmpty { for i in 0..<cellRepeat { rows[row, default: [:]][col + i] = cell } }
                col += cellRepeat; inCell = false
            case "table:table-row":
                if let filled = rows[row], rowRepeat > 1 { for i in 1..<rowRepeat { rows[row + i] = filled } }
                row += rowRepeat
            case "table:table": sheets.append((name, grid(rows)))
            default: break
            }
        })
        return sheets
    }

    /// Sparse cells to rows, padded to the widest row; empty rows inside the table are kept.
    private static func grid(_ cells: [Int: [Int: String]]) -> [[String]] {
        guard let last = cells.keys.max() else { return [] }
        let width = (cells.values.compactMap { $0.keys.max() }.max() ?? -1) + 1
        return (0...last).map { r in (0..<width).map { cells[r]?[$0] ?? "" } }
    }

    static func sheetsAsText(_ sheets: [(name: String, rows: [[String]])]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        #if os(macOS)
        let bold = NSFont.boldSystemFont(ofSize: 16), body = NSFont.systemFont(ofSize: 11)
        #else
        let bold = UIFont.boldSystemFont(ofSize: 16), body = UIFont.systemFont(ofSize: 11)
        #endif
        for sheet in sheets {
            if sheets.count > 1 { result.append(NSAttributedString(string: sheet.name + "\n", attributes: [.font: bold])) }
            let text = sheet.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            result.append(NSAttributedString(string: text + "\n\n", attributes: [.font: body]))
        }
        return result
    }

    // MARK: Pictures

    static func hasPictures(_ url: URL) -> Bool {
        ["pptx", "ppsx", "potx", "odp", "xlsx", "xlsm", "ods", "docx", "odt"].contains(url.pathExtension.lowercased())
    }

    /// Saves the pictures placed in an Office or OpenDocument file into a folder next to it.
    static func pictures(_ url: URL, options: Options) throws -> URL {
        let entries = try Zip.read(url)
        let images = entries.filter { key, _ in
            mediaFolders.contains { key.hasPrefix($0) } && FileKind(url: URL(fileURLWithPath: key)) == .image
        }.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        guard !images.isEmpty else { throw MorphNote("\(url.lastPathComponent) has no pictures in it") }
        let folder = try Output.folder(for: url, suffix: "pictures", options: options)
        for (key, data) in images {
            let file = URL(fileURLWithPath: key)
            try data.write(to: Output.unique(in: folder, base: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension))
        }
        return folder
    }
}

/// A few lines of XMLParser for reading parts of Office files: element names as written (with their prefix).
final class XMLWalk: NSObject, XMLParserDelegate {
    private let start: (String, [String: String]) -> Void, text: (String) -> Void, end: (String) -> Void

    @discardableResult
    init(_ data: Data, start: @escaping (String, [String: String]) -> Void, text: @escaping (String) -> Void = { _ in },
         end: @escaping (String) -> Void = { _ in }) {
        self.start = start; self.text = text; self.end = end
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        start(Self.local(elementName, keepPrefix: elementName.hasPrefix("table:") || elementName.hasPrefix("text:")), attributes)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text(string) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        end(Self.local(elementName, keepPrefix: elementName.hasPrefix("table:") || elementName.hasPrefix("text:")))
    }

    /// SpreadsheetML is written with and without a prefix ("x:c" or "c"), so it's dropped there; ODF's is kept.
    private static func local(_ name: String, keepPrefix: Bool) -> String {
        keepPrefix ? name : String(name.split(separator: ":").last ?? Substring(name))
    }
}
