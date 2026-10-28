import Foundation
import PDFKit
import CoreGraphics

public enum PDFOps {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw MorphError("\(url.lastPathComponent) isn't a readable PDF") }
        if doc.isLocked { throw MorphError("\(url.lastPathComponent) is password-protected") }
        return doc
    }

    public static func merge(_ urls: [URL], options: Options) throws -> URL {
        guard let first = urls.first else { throw MorphError("Nothing to merge") }
        let merged = PDFDocument()
        for url in urls {
            let doc = try open(url)
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage { merged.insert(page, at: merged.pageCount) }
            }
        }
        let out = Output.unique(in: options.outputDirectory ?? first.deletingLastPathComponent(), base: "Merged", ext: "pdf")
        guard merged.write(to: out) else { throw MorphError("Couldn't write merged PDF") }
        return out
    }

    public static func split(_ url: URL, options: Options) throws -> URL {
        let doc = try open(url)
        let folder = try Output.folder(for: url, suffix: "pages", options: options)
        for i in 0..<doc.pageCount {
            let single = PDFDocument()
            if let page = doc.page(at: i)?.copy() as? PDFPage { single.insert(page, at: 0) }
            single.write(to: folder.appendingPathComponent(String(format: "page %03d.pdf", i + 1)))
        }
        return folder
    }

    /// One A4-width page per image, in drop order. SVGs stay vectors.
    public static func fromImages(_ urls: [URL], options: Options) throws -> URL {
        guard let first = urls.first else { throw MorphError("No images") }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Images"
        let out = Output.unique(in: options.outputDirectory ?? first.deletingLastPathComponent(), base: base, ext: "pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else { throw MorphError("Couldn't create PDF") }
        for url in urls {
            if VectorOps.isSVG(url) {
                let svg = try VectorOps.document(url)
                let svgWidth = max(svg.size.width, 1)
                let svgHeight = max(svg.size.height, 1)
                var page = CGRect(x: 0, y: 0, width: 595, height: 595 * svgHeight / svgWidth)
                ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &page, count: MemoryLayout<CGRect>.size)] as CFDictionary)
                VectorOps.draw(svg, in: ctx, rect: page)
                ctx.endPDFPage()
                continue
            }
            let img = try ImageOps.load(url, maxPixel: options.maxPixel ?? 3000)
            let imgWidth = max(CGFloat(img.width), 1)
            let imgHeight = max(CGFloat(img.height), 1)
            var page = CGRect(x: 0, y: 0, width: 595, height: 595 * imgHeight / imgWidth)
            let pageInfo = [kCGPDFContextMediaBox: Data(bytes: &page, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(pageInfo)
            ctx.draw(img, in: page)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out
    }

    static func render(_ page: CGPDFPage, scale: CGFloat) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let size = CGSize(width: (rotated ? box.height : box.width) * scale, height: (rotated ? box.width : box.height) * scale)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: CGSize(width: size.width / scale, height: size.height / scale)), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    public static func toImages(_ url: URL, format: ImageFormat = .png, options: Options) throws -> URL {
        guard let doc = CGPDFDocument(url as CFURL) else { throw MorphError("\(url.lastPathComponent) isn't a readable PDF") }
        let folder = try Output.folder(for: url, suffix: "images", options: options)
        guard doc.numberOfPages > 0 else { return folder }
        for i in 1...doc.numberOfPages {
            guard let page = doc.page(at: i), let img = render(page, scale: 2) else { continue }
            try ImageOps.encode(img, as: format, quality: options.quality ?? 0.9)
                .write(to: folder.appendingPathComponent(String(format: "page %03d.%@", i, format.rawValue)))
        }
        return folder
    }

    /// Re-saves with JPEG-recompressed, screen-resolution images. Text stays selectable.
    public static func compress(_ url: URL, options: Options) throws -> URL {
        let doc = try open(url)
        let out = Output.url(for: url, ext: "pdf", suffix: "compressed", options: options)
        let opts: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
        guard doc.write(to: out, withOptions: opts) else { throw MorphError("Couldn't write compressed PDF") }
        return out
    }

    /// Embedded text where present, OCR for scanned pages.
    public static func text(of url: URL) throws -> String {
        let doc = try open(url)
        let cg = CGPDFDocument(url as CFURL)
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            let embedded = doc.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !embedded.isEmpty { pages.append(embedded); continue }
            if let page = cg?.page(at: i + 1), let img = render(page, scale: 2) {
                pages.append(try VisionOps.recognizeText(in: img))
            }
        }
        return pages.joined(separator: "\n\n")
    }

    public static func toText(_ url: URL, options: Options) throws -> URL {
        let out = Output.url(for: url, ext: "txt", options: options)
        try text(of: url).write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    public static func attributedText(of url: URL) throws -> NSAttributedString {
        let doc = try open(url)
        let attr = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i)?.attributedString { attr.append(page); attr.append(NSAttributedString(string: "\n")) }
        }
        if !attr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return attr }
        return NSAttributedString(string: try text(of: url))
    }
}
