import Foundation
import Vision
import CoreGraphics

public enum VisionOps {
    static func perform(_ requests: [VNRequest], on img: CGImage) throws {
        try VNImageRequestHandler(cgImage: img, options: [:]).perform(requests)
    }

    static func firstImage(of url: URL) throws -> CGImage {
        if FileKind(url: url) == .pdf {
            guard let page = CGPDFDocument(url as CFURL)?.page(at: 1), let img = PDFOps.render(page, scale: 2) else {
                throw MorphError("Couldn't render \(url.lastPathComponent)")
            }
            return img
        }
        return try ImageOps.load(url)
    }

    public static func readCodes(_ url: URL) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        try perform([request], on: firstImage(of: url))
        var seen = Set<String>()
        return (request.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
    }

    public static func readCodes(_ url: URL, options: Options) throws -> URL {
        let codes = try readCodes(url)
        guard !codes.isEmpty else { throw MorphError("No QR codes or barcodes found in \(url.lastPathComponent)") }
        let out = Output.url(for: url, ext: "txt", suffix: "codes", options: options)
        try codes.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func textObservations(in img: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try perform([request], on: img)
        return request.results ?? []
    }

    public static func recognizeText(in img: CGImage) throws -> String {
        try textObservations(in: img).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    public static func ocr(_ url: URL, options: Options) throws -> URL {
        if FileKind(url: url) == .pdf { return try PDFOps.toText(url, options: options) }
        let text = try recognizeText(in: ImageOps.load(url))
        guard !text.isEmpty else { throw MorphError("No text found in \(url.lastPathComponent)") }
        let out = Output.url(for: url, ext: "txt", options: options)
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    // MARK: Redaction

    /// Patterns treated as personal info when redacting text in screenshots.
    static let sensitivePatterns: [NSRegularExpression] = [
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,                 // email
        #"\+?\d[\d\s().-]{7,}\d"#,                                   // phone
        #"\b(?:\d[ -]?){13,19}\b"#,                                  // card number
        #"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#,                        // IBAN
        #"\b\d{3}-\d{2}-\d{4}\b"#,                                   // SSN
        #"\b\d{4}\s?\d{4}\s?\d{4}\b"#,                               // Aadhaar
        #"\b[A-Z]{5}\d{4}[A-Z]\b"#,                                  // PAN
        #"(?:\d{1,3}\.){3}\d{1,3}"#,                                 // IPv4
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Normalized (bottom-left origin) rects of faces.
    static func faceRects(in img: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        try perform([request], on: img)
        return (request.results ?? []).map(\.boundingBox)
    }

    /// Normalized rects of recognized text that matches a personal-info pattern.
    static func sensitiveTextRects(in img: CGImage) throws -> [CGRect] {
        var rects: [CGRect] = []
        for obs in try textObservations(in: img) {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            for regex in sensitivePatterns {
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range, in: text),
                          let box = try? candidate.boundingBox(for: range) else { continue }
                    rects.append(box.boundingBox)
                }
            }
        }
        return rects
    }

    static func redact(_ img: CGImage, normalizedRects: [CGRect], style: RedactStyle, padding: CGFloat) -> CGImage? {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(img, in: full)
        for n in normalizedRects {
            let r = CGRect(x: n.minX * w, y: n.minY * h, width: n.width * w, height: n.height * h)
                .insetBy(dx: -n.width * w * padding, dy: -n.height * h * padding)
                .intersection(full).integral
            guard !r.isEmpty else { continue }
            switch style {
            case .solid:
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(r)
            case .pixelate:
                // Average down to a coarse grid (irreversible), then scale back up with hard edges.
                let crop = CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
                let blocks = 8
                guard r.width > 0, r.height > 0,
                      let piece = img.cropping(to: crop),
                      let tiny = CGContext(data: nil, width: blocks, height: max(Int(CGFloat(blocks) * r.height / r.width), 1),
                                           bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                tiny.interpolationQuality = .high
                tiny.draw(piece, in: CGRect(x: 0, y: 0, width: tiny.width, height: tiny.height))
                guard let small = tiny.makeImage() else { continue }
                ctx.interpolationQuality = .none
                ctx.draw(small, in: r)
            }
        }
        return ctx.makeImage()
    }

    private static func redactFile(_ url: URL, suffix: String, options: Options, padding: CGFloat,
                                   style: RedactStyle, detect: (CGImage) throws -> [CGRect], none: String) throws -> URL {
        let src = try ImageOps.source(url)
        let img = try ImageOps.image(from: src)
        let rects = try detect(img)
        guard !rects.isEmpty else { throw MorphError(none) }
        guard let result = redact(img, normalizedRects: rects, style: style, padding: padding) else {
            throw MorphError("Couldn't redact \(url.lastPathComponent)")
        }
        let fmt = ImageOps.outputFormat(for: src)
        let out = Output.url(for: url, ext: fmt.rawValue, suffix: "redacted", options: options)
        // Metadata is deliberately dropped: a redacted photo shouldn't leak where it was taken.
        try ImageOps.encode(result, as: fmt, quality: 0.92).write(to: out)
        return out
    }

    public static func redactFaces(_ url: URL, options: Options) throws -> URL {
        try redactFile(url, suffix: "redacted", options: options, padding: 0.2, style: options.redactStyle,
                       detect: faceRects, none: "No faces found in \(url.lastPathComponent)")
    }

    public static func redactPersonalInfo(_ url: URL, options: Options) throws -> URL {
        try redactFile(url, suffix: "redacted", options: options, padding: 0.08, style: .solid,
                       detect: sensitiveTextRects, none: "No emails, phone or card numbers found in \(url.lastPathComponent)")
    }
}
