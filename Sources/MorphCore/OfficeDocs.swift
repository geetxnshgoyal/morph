import Foundation
import Compression
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// DOCX and ODT for iOS, where NSAttributedString can't read or write them: paragraphs, headings (from bold, large
/// text), list items and line breaks, inside a small zip reader and writer. The Mac uses AppKit's own converters.
enum OfficeDocs {
    // MARK: Reading

    static func read(_ url: URL) throws -> NSAttributedString {
        let entries = try Zip.read(url)
        switch url.pathExtension.lowercased() {
        case "docx":
            guard let xml = entries["word/document.xml"] else { throw MorphError("This DOCX has no document body") }
            return try Reader(xml: xml, namespace: "w", paragraph: ["p"], heading: [], text: "t",
                              styles: entries["word/styles.xml"]).attributed()
        case "odt":
            guard let xml = entries["content.xml"] else { throw MorphError("This ODT has no content") }
            return try Reader(xml: xml, namespace: "text", paragraph: ["p"], heading: ["h"], text: nil, styles: nil).attributed()
        default:
            throw MorphError("Can't read .\(url.pathExtension) documents")
        }
    }

    /// Collects paragraphs from WordprocessingML or ODF content: text, tabs, breaks, and which ones are headings.
    private final class Reader: NSObject, XMLParserDelegate {
        let xml: Data, namespace: String, paragraph: Set<String>, heading: Set<String>, textElement: String?
        var styleNames: [String: String] = [:]
        var paragraphs: [(text: String, heading: Int, list: Int)] = []
        var current = "", depth = 0, headingLevel = 0, listDepth = 0, style = "", numbered = false
        var inText = false, inNote = 0

        init(xml: Data, namespace: String, paragraph: Set<String>, heading: Set<String>, text: String?, styles: Data?) {
            self.xml = xml; self.namespace = namespace; self.paragraph = paragraph; self.heading = heading; self.textElement = text
            super.init()
            if let styles { styleNames = StyleNames(styles).names }
        }

        func attributed() throws -> NSAttributedString {
            let parser = XMLParser(data: xml)
            parser.delegate = self
            guard parser.parse() else { throw MorphError("Couldn't read the document: \(parser.parserError?.localizedDescription ?? "bad XML")") }
            let result = NSMutableAttributedString()
            for p in paragraphs where !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let size: CGFloat = p.heading == 0 ? 12 : [1: 20, 2: 16][p.heading] ?? 13
                #if os(macOS)
                let font = p.heading > 0 ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
                #else
                let font = p.heading > 0 ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                #endif
                let prefix = p.list > 0 ? String(repeating: "\t", count: p.list - 1) + "•\t" : ""
                result.append(NSAttributedString(string: prefix + p.text + "\n", attributes: [.font: font]))
            }
            return result
        }

        private func local(_ name: String) -> (prefix: String, name: String) {
            let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : ("", name)
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let (prefix, name) = local(elementName)
            guard prefix == namespace else { return }
            if paragraph.contains(name) || heading.contains(name) {
                if depth == 0 {
                    current = ""; style = ""; numbered = false
                    headingLevel = heading.contains(name) ? Int(attributes["text:outline-level"] ?? "1") ?? 1 : 0
                }
                depth += 1
            }
            switch name {
            case "pStyle": style = attributes["w:val"] ?? ""
            case "numPr": numbered = true
            case "list" where namespace == "text": listDepth += 1
            case "note": inNote += 1
            case "tab" where depth > 0 && inNote == 0: current += "\t"
            case "br", "cr", "line-break": if depth > 0 && inNote == 0 { current += "\n" }
            case "s" where namespace == "text" && inNote == 0: current += String(repeating: " ", count: Int(attributes["text:c"] ?? "1") ?? 1)
            default: break
            }
            if let textElement, name == textElement { inText = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard depth > 0, inNote == 0, textElement == nil || inText else { return }
            current += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let (prefix, name) = local(elementName)
            guard prefix == namespace else { return }
            if let textElement, name == textElement { inText = false }
            switch name {
            case "list" where namespace == "text": listDepth -= 1
            case "note": inNote -= 1
            default: break
            }
            guard paragraph.contains(name) || heading.contains(name) else { return }
            depth -= 1
            guard depth == 0 else { return }
            let styleName = (styleNames[style] ?? style).lowercased().replacingOccurrences(of: " ", with: "")
            var level = headingLevel
            if styleName == "title" { level = 1 }
            if styleName.hasPrefix("heading"), let n = Int(styleName.dropFirst(7)) { level = min(max(n, 1), 6) }
            var list = numbered || styleName == "listparagraph" ? 1 : listDepth
            // Morph's own DOCX writes the bullet into the text; take it back off.
            var text = current
            if text.hasPrefix("•\t") { text.removeFirst(2); list = max(list, 1) }
            paragraphs.append((text, level, level > 0 ? 0 : list))
        }
    }

    /// Style ids to names in a DOCX, so "Heading1" and a translated name both read as headings.
    private final class StyleNames: NSObject, XMLParserDelegate {
        var names: [String: String] = [:]
        private var id: String?
        init(_ data: Data) {
            super.init()
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if elementName == "w:style" { id = attributes["w:styleId"] }
            if elementName == "w:name", let id { names[id] = attributes["w:val"] ?? id }
        }
    }

    // MARK: Writing

    private struct Paragraph { var text: String; var heading: Int; var bullet: Bool }

    /// Headings are lines set in bold at 14 pt or more; list items start with a bullet and a tab.
    private static func paragraphs(of attr: NSAttributedString) -> [Paragraph] {
        var result: [Paragraph] = []
        let string = attr.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { text, range, _, _ in
            guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var heading = 0
            #if os(macOS)
            let font = attr.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let bold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            #else
            let font = attr.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            let bold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            #endif
            if bold, let size = font?.pointSize, size >= 14 { heading = size >= 19 ? 1 : size >= 15.5 ? 2 : 3 }
            let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\t"))
            let bullet = ["•", "◦", "▪", "-"].contains { trimmed.hasPrefix($0 + "\t") || trimmed.hasPrefix($0 + " ") }
            result.append(Paragraph(text: bullet ? String(trimmed.dropFirst(2)) : text, heading: heading, bullet: bullet))
        }
        return result
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: if scalar.value >= 0x20 || scalar == "\t" || scalar == "\n" { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }

    static func write(_ attr: NSAttributedString, to url: URL, ext: String) throws {
        let ps = paragraphs(of: attr)
        switch ext {
        case "docx": try Zip.write(docx(ps), to: url)
        case "odt": try Zip.write(odt(ps), to: url)
        default: throw MorphError("Can't write .\(ext) documents")
        }
    }

    private static func docx(_ ps: [Paragraph]) -> [(String, Data)] {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        var body = ""
        for p in ps {
            let style = p.heading > 0 ? "Heading\(p.heading)" : p.bullet ? "ListParagraph" : "Normal"
            body += "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>" + (p.bullet ? "<w:ind w:left=\"720\" w:hanging=\"360\"/>" : "") + "</w:pPr><w:r>"
            let text = (p.bullet ? "•\t" : "") + p.text
            for (i, line) in text.components(separatedBy: "\u{2028}").enumerated() {
                if i > 0 { body += "<w:br/>" }
                for (j, part) in line.components(separatedBy: "\t").enumerated() {
                    if j > 0 { body += "<w:tab/>" }
                    body += "<w:t xml:space=\"preserve\">\(escape(part))</w:t>"
                }
            }
            body += "</w:r></w:p>"
        }
        func style(_ id: String, _ name: String, _ run: String, _ paragraph: String) -> String {
            "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"\(id == "Normal" ? " w:default=\"1\"" : "")><w:name w:val=\"\(name)\"/>"
                + (id == "Normal" ? "" : "<w:basedOn w:val=\"Normal\"/>") + "<w:pPr>\(paragraph)</w:pPr><w:rPr>\(run)</w:rPr></w:style>"
        }
        let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:styles xmlns:w=\"\(w)\">"
            + style("Normal", "Normal", "<w:sz w:val=\"22\"/>", "<w:spacing w:after=\"120\"/>")
            + style("Heading1", "heading 1", "<w:b/><w:sz w:val=\"36\"/>", "<w:keepNext/><w:spacing w:before=\"360\" w:after=\"120\"/><w:outlineLvl w:val=\"0\"/>")
            + style("Heading2", "heading 2", "<w:b/><w:sz w:val=\"30\"/>", "<w:keepNext/><w:spacing w:before=\"240\" w:after=\"120\"/><w:outlineLvl w:val=\"1\"/>")
            + style("Heading3", "heading 3", "<w:b/><w:sz w:val=\"26\"/>", "<w:keepNext/><w:spacing w:before=\"240\" w:after=\"80\"/><w:outlineLvl w:val=\"2\"/>")
            + style("ListParagraph", "List Paragraph", "", "<w:spacing w:after=\"60\"/>") + "</w:styles>"
        let rels = "http://schemas.openxmlformats.org/package/2006/relationships"
        let doc = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        return [
            ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"),
            ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"\(rels)\"><Relationship Id=\"rId1\" Type=\"\(doc)/officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
            ("word/_rels/document.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"\(rels)\"><Relationship Id=\"rId1\" Type=\"\(doc)/styles\" Target=\"styles.xml\"/></Relationships>"),
            ("word/styles.xml", styles),
            ("word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"\(w)\"><w:body>\(body)<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"),
        ].map { ($0.0, Data($0.1.utf8)) }
    }

    private static func odt(_ ps: [Paragraph]) -> [(String, Data)] {
        var body = "", inList = false
        for p in ps {
            if p.bullet != inList { body += p.bullet ? "<text:list>" : "</text:list>"; inList = p.bullet }
            let text = escape(p.text).replacingOccurrences(of: "\t", with: "<text:tab/>").replacingOccurrences(of: "\u{2028}", with: "<text:line-break/>")
            if p.heading > 0 { body += "<text:h text:style-name=\"H\(p.heading)\" text:outline-level=\"\(p.heading)\">\(text)</text:h>" }
            else if p.bullet { body += "<text:list-item><text:p text:style-name=\"Standard\">\(text)</text:p></text:list-item>" }
            else { body += "<text:p text:style-name=\"Standard\">\(text)</text:p>" }
        }
        if inList { body += "</text:list>" }
        func heading(_ n: Int, _ size: String) -> String {
            "<style:style style:name=\"H\(n)\" style:family=\"paragraph\"><style:text-properties fo:font-size=\"\(size)\" fo:font-weight=\"bold\"/></style:style>"
        }
        let content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" office:version=\"1.2\"><office:automatic-styles>"
            + heading(1, "20pt") + heading(2, "16pt") + heading(3, "13pt")
            + "</office:automatic-styles><office:body><office:text>\(body)</office:text></office:body></office:document-content>"
        return [
            ("mimetype", "application/vnd.oasis.opendocument.text"),
            ("META-INF/manifest.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\"><manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.2\" manifest:media-type=\"application/vnd.oasis.opendocument.text\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>"),
            ("content.xml", content),
        ].map { ($0.0, Data($0.1.utf8)) }
    }
}

/// Just enough zip for office documents: reading stored and deflated entries, writing stored ones.
enum Zip {
    static func read(_ url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        func u16(_ o: Int) -> Int { Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        // The end-of-central-directory record is within the last 64 KB (its comment is at most that long).
        guard data.count >= 22,
              let end = stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1).first(where: { u32($0) == 0x0605_4b50 })
        else { throw MorphError("Not a valid zip file") }
        var entries: [String: Data] = [:]
        var p = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard p + 46 <= data.count, u32(p) == 0x0201_4b50 else { break }
            let method = u16(p + 10), compressed = u32(p + 20), size = u32(p + 24)
            let nameLength = u16(p + 28), extra = u16(p + 30), comment = u16(p + 32), local = u32(p + 42)
            let name = String(decoding: data[(data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLength)], as: UTF8.self)
            p += 46 + nameLength + extra + comment
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= data.count else { continue }
            let raw = data[(data.startIndex + start)..<(data.startIndex + start + compressed)]
            switch method {
            case 0: entries[name] = Data(raw)
            case 8: entries[name] = inflate(Data(raw), size: size)
            default: continue
            }
        }
        return entries
    }

    /// Zip's deflate is raw DEFLATE, which is what the Compression framework's "zlib" algorithm reads.
    private static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
    }

    static func write(_ entries: [(String, Data)], to url: URL) throws {
        var out = Data(), central = Data()
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8(v >> ($0 * 8) & 0xFF) }) }
        for (name, data) in entries {
            let nameData = Data(name.utf8), crc = crc32(data), offset = UInt32(out.count)
            // Stored (no compression), so the ODF mimetype comes first and readable, as it must.
            let header = le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21) + le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(nameData.count) + le16(0)
            out += le32(0x0403_4b50) + header + nameData + data
            central += le32(0x0201_4b50) + le16(20) + header + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameData
        }
        let centralOffset = UInt32(out.count)
        out += central + le32(0x0605_4b50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
            + le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        try out.write(to: url)
    }

    private static let table: [UInt32] = (0..<256).map { i in
        (0..<8).reduce(UInt32(i)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}
