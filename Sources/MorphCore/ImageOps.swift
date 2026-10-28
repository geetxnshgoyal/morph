import Foundation
import ImageIO
import CoreGraphics
import CoreText
import UniformTypeIdentifiers
import CryptoKit

public enum ImageFormat: String, CaseIterable, Codable, Sendable {
    case jpg, png, heic, webp, avif, tiff, gif, bmp

    public var type: UTType {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        case .heic: .heic
        case .webp: .webP
        case .avif: UTType("public.avif") ?? .image
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        }
    }

    public var isNativelyWritable: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
    }

    public var isAvailable: Bool { isNativelyWritable || (self == .webp && ExternalTool.cwebp != nil) }
    var supportsAlpha: Bool { ![.jpg, .bmp].contains(self) }
    var isLossy: Bool { [.jpg, .heic, .webp, .avif].contains(self) }

    init?(type: String) {
        guard let match = Self.allCases.first(where: { $0.type.identifier == type }) else { return nil }
        self = match
    }
}

public enum ImageOps {
    static func source(_ url: URL) throws -> CGImageSource {
        if VectorOps.isSVG(url) { return try VectorOps.source(url) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else {
            throw MorphError("\(url.lastPathComponent) isn't a readable image")
        }
        return src
    }

    static func properties(_ src: CGImageSource, _ index: Int = 0) -> [CFString: Any] {
        CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] ?? [:]
    }

    /// Decodes a frame with its EXIF orientation applied; downscales (never upscales) to `maxPixel`.
    static func image(from src: CGImageSource, index: Int = 0, maxPixel: Int? = nil) throws -> CGImage {
        let props = properties(src, index)
        let longest = max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let target = longest > 0 ? min(maxPixel ?? longest, longest) : (maxPixel ?? 8192)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, index, opts as CFDictionary) else {
            throw MorphError("Couldn't decode the image")
        }
        return img
    }

    public static func load(_ url: URL, maxPixel: Int? = nil) throws -> CGImage {
        if VectorOps.isSVG(url) { return try VectorOps.render(url, maxPixel: maxPixel) }
        return try image(from: source(url), maxPixel: maxPixel)
    }

    static func hasAlpha(_ img: CGImage) -> Bool {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    static func flattened(_ img: CGImage) -> CGImage {
        guard hasAlpha(img),
              let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(img, in: rect)
        return ctx.makeImage() ?? img
    }

    /// Descriptive metadata to carry across a re-encode. Orientation is reset since pixels are already upright.
    static func carriedMetadata(_ src: CGImageSource?) -> [CFString: Any] {
        guard let src else { return [:] }
        let p = properties(src)
        var out: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let v = p[key] { out[key] = v }
        }
        if var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        return out
    }

    /// `progressive` writes a progressive JPEG, usually a few percent smaller at the same quality.
    static func encode(_ img: CGImage, as fmt: ImageFormat, quality: Double, metadata: [CFString: Any] = [:],
                       progressive: Bool = false) throws -> Data {
        let img = fmt.supportsAlpha ? img : flattened(img)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, fmt.type.identifier as CFString, 1, nil) else {
            throw MorphError("\(fmt.rawValue.uppercased()) output isn't supported here")
        }
        var props = metadata
        props[kCGImageDestinationLossyCompressionQuality] = quality
        if progressive, fmt == .jpg { props[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true] }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw MorphError("Couldn't encode \(fmt.rawValue.uppercased())") }
        return data as Data
    }

    static func write(_ img: CGImage, as fmt: ImageFormat, quality: Double, metadata: [CFString: Any], to out: URL) throws {
        if fmt == .webp && !fmt.isNativelyWritable {
            try writeWebPWithCwebp(img, quality: quality, to: out)
            return
        }
        try encode(img, as: fmt, quality: quality, metadata: metadata).write(to: out)
    }

    private static func writeWebPWithCwebp(_ img: CGImage, quality: Double, to out: URL) throws {
        #if os(macOS)
        guard let cwebp = ExternalTool.cwebp else { throw MorphError("WebP needs cwebp: brew install webp") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try encode(img, as: .png, quality: 1).write(to: tmp)
        let process = Process()
        process.executableURL = cwebp
        process.arguments = ["-quiet", "-q", String(Int(quality * 100)), tmp.path, "-o", out.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MorphError("cwebp failed") }
        #else
        throw MorphError("WebP output isn't supported on this device")
        #endif
    }

    // MARK: Actions

    public static func convert(_ url: URL, to fmt: ImageFormat, options: Options) throws -> URL {
        if VectorOps.isSVG(url) {
            let img = try VectorOps.render(url, maxPixel: options.maxPixel)
            let out = Output.url(for: url, ext: fmt.rawValue, options: options)
            try write(img, as: fmt, quality: options.quality ?? 0.9, metadata: [:], to: out)
            return out
        }
        let src = try source(url)
        let out = Output.url(for: url, ext: fmt.rawValue, options: options)
        if fmt == .gif, CGImageSourceGetCount(src) > 1, options.maxPixel == nil {
            try copyFrames(src, type: fmt.type, to: out)
            return out
        }
        let img = try image(from: src, maxPixel: options.maxPixel)
        try write(img, as: fmt, quality: options.quality ?? 0.9, metadata: carriedMetadata(src), to: out)
        return out
    }

    private static func copyFrames(_ src: CGImageSource, type: UTType, to out: URL) throws {
        let count = CGImageSourceGetCount(src)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, count, nil) else {
            throw MorphError("Couldn't create output")
        }
        if let props = CGImageSourceCopyProperties(src, nil) { CGImageDestinationSetProperties(dest, props) }
        for i in 0..<count { CGImageDestinationAddImageFromSource(dest, src, i, nil) }
        guard CGImageDestinationFinalize(dest) else { throw MorphError("Couldn't write output") }
    }

    static func outputFormat(for src: CGImageSource) -> ImageFormat {
        let fmt = CGImageSourceGetType(src).flatMap { ImageFormat(type: $0 as String) }
        return fmt.flatMap { $0.isNativelyWritable ? $0 : nil } ?? .png
    }

    public static func resize(_ url: URL, options: Options) throws -> URL {
        if let size = options.exactSize { return try resize(url, exactly: size, options: options) }
        // An SVG is drawn at the size asked for, larger or smaller, into a PNG: SVG has no pixel size to change.
        let src = VectorOps.isSVG(url) ? nil : try source(url)
        let fmt = src.map(outputFormat) ?? .png
        let img = try src.map { try image(from: $0, maxPixel: options.maxPixel ?? 2048) }
            ?? VectorOps.render(url, maxPixel: options.maxPixel ?? 2048)
        // Name by the size actually written: smaller images are never upscaled.
        let out = Output.url(for: url, ext: fmt.rawValue, suffix: "\(max(img.width, img.height))px", options: options)
        try write(img, as: fmt, quality: options.quality ?? 0.9, metadata: carriedMetadata(src), to: out)
        return out
    }

    // MARK: Exact size, for forms

    /// Exactly `size`, cropped to fill, as a JPG with no metadata: what passport, visa and exam forms ask for.
    /// With a caption, the name and the date the photo was taken go in a white strip at the bottom, inside the size.
    /// With a size limit, the JPG is fitted under it at that size (a form checks both).
    static func resize(_ url: URL, exactly size: PixelSize, options: Options) throws -> URL {
        let src = VectorOps.isSVG(url) ? nil : try source(url)
        // Decode big enough that cropping never has to stretch the photo.
        let decode = max(size.width, size.height) * 3
        let photo = try src.map { try image(from: $0, maxPixel: decode) } ?? VectorOps.render(url, maxPixel: decode)
        let caption = options.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = src.flatMap(captureDate) ?? Date()
        guard let img = fitted(photo, to: size, caption: caption?.isEmpty == false ? caption : nil, date: taken) else {
            throw MorphError("Couldn't make \(url.lastPathComponent) \(size.label)")
        }
        let out = Output.url(for: url, ext: ImageFormat.jpg.rawValue, suffix: "\(size.width)x\(size.height)", options: options)
        guard let target = options.targetBytes else {
            try encode(img, as: .jpg, quality: options.quality ?? 0.92).write(to: out)
            return out
        }
        // The size is fixed, so only quality can give: binary-search the best JPG that fits.
        var lo = 0.05, hi = 0.95, best: Data?
        for _ in 0..<8 {
            let mid = (lo + hi) / 2
            let data = try encode(img, as: .jpg, quality: mid)
            if data.count <= target { best = data; lo = mid } else { hi = mid }
        }
        guard let best else {
            throw MorphError("\(size.label) can't get under \(SizeLimit.label(target)); pick a larger size limit")
        }
        try best.write(to: out)
        return out
    }

    /// `img` scaled to cover `size` and cropped, keeping more of the top (where faces are) than the bottom.
    static func fitted(_ img: CGImage, to size: PixelSize, caption: String?, date: Date) -> CGImage? {
        let w = CGFloat(size.width), h = CGFloat(size.height)
        let strip: CGFloat = caption == nil ? 0 : max((h * 0.16).rounded(), 18)
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Photo area above the strip (Core Graphics counts y from the bottom).
        let area = CGRect(x: 0, y: strip, width: w, height: h - strip)
        let scale = max(area.width / CGFloat(img.width), area.height / CGFloat(img.height))
        let dw = CGFloat(img.width) * scale, dh = CGFloat(img.height) * scale
        let spareY = dh - area.height
        let drawn = CGRect(x: (area.width - dw) / 2, y: area.maxY + spareY * 0.3 - dh, width: dw, height: dh)
        ctx.saveGState()
        ctx.clip(to: area)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: drawn)
        ctx.restoreGState()
        if let caption {
            let style = DateFormatter()
            style.dateFormat = "dd/MM/yyyy"
            drawLines([caption, style.string(from: date)], in: CGRect(x: 0, y: 0, width: w, height: strip), ctx: ctx)
        }
        return ctx.makeImage()
    }

    /// Two centred lines (name in bold, date below), shrunk to fit the strip's width.
    private static func drawLines(_ lines: [String], in rect: CGRect, ctx: CGContext) {
        let ink = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        var size = rect.height * 0.36
        func make(_ text: String, bold: Bool, _ size: CGFloat) -> CTLine {
            let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink] as [CFString: Any]
            return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
        }
        var made = lines.enumerated().map { make($1, bold: $0 == 0, size) }
        let widest = made.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        if widest > rect.width * 0.92 {
            size *= rect.width * 0.92 / widest
            made = lines.enumerated().map { make($1, bold: $0 == 0, size) }
        }
        let lineHeight = size * 1.15
        var y = rect.midY + lineHeight * CGFloat(made.count - 1) / 2 - size * 0.35
        for line in made {
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            ctx.textPosition = CGPoint(x: rect.midX - width / 2, y: y)
            CTLineDraw(line, ctx)
            y -= lineHeight
        }
    }

    /// When the photo was taken, from its EXIF data.
    static func captureDate(_ src: CGImageSource) -> Date? {
        guard let exif = properties(src)[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let style = DateFormatter()
        style.locale = Locale(identifier: "en_US_POSIX")
        style.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return style.date(from: text)
    }

    /// Makes the file smaller without a visible change: re-encodes at a range of qualities, compares each with
    /// the original and keeps the smallest that still looks the same at the chosen compression level. Throws
    /// `MorphNote` when that saves under 5%, rather than writing a near-identical copy. With `targetBytes`, makes
    /// a JPEG (what upload forms accept), binary-searching quality and then downscaling until the file fits.
    public static func compress(_ url: URL, options: Options) throws -> URL {
        let src = try source(url)
        var img = try image(from: src, maxPixel: options.maxPixel)
        let srcFmt = outputFormat(for: src)
        let fmt: ImageFormat = srcFmt.isLossy ? srcFmt : (hasAlpha(img) ? .heic : .jpg)
        let meta = carriedMetadata(src)

        guard let target = options.targetBytes else {
            let data: Data
            if let quality = options.quality {
                data = try encode(img, as: fmt, quality: quality, metadata: meta, progressive: true)
            } else {
                let originalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
                guard let best = try smallestLookalike(img, as: fmt, metadata: meta,
                                                       similarity: options.compression.minimumSimilarity),
                      Double(best.count) < Double(originalBytes) * 0.95 else {
                    throw MorphNote("\(url.lastPathComponent) is already as small as it can get without losing quality")
                }
                data = best
            }
            let out = Output.url(for: url, ext: fmt.rawValue, suffix: "compressed", options: options)
            try data.write(to: out)
            return out
        }
        let originalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        if srcFmt == .jpg, originalBytes <= target {
            throw MorphNote("\(url.lastPathComponent) is already under \(SizeLimit.label(target))")
        }
        let out = Output.url(for: url, ext: ImageFormat.jpg.rawValue, suffix: "compressed", options: options)
        var longest = max(img.width, img.height)
        while true {
            var lo = 0.05, hi = 0.95, best: Data?
            for _ in 0..<7 {
                let mid = (lo + hi) / 2
                let data = try encode(img, as: .jpg, quality: mid, metadata: meta)
                if data.count <= target { best = data; lo = mid } else { hi = mid }
            }
            if let best { try best.write(to: out); return out }
            longest = Int(Double(longest) * 0.8)
            guard longest > 64 else { break }
            img = try image(from: src, maxPixel: longest)
        }
        throw MorphError("Couldn't get \(url.lastPathComponent) under \(SizeLimit.label(target))")
    }

    /// The smallest encoding that still scores at least `similarity` against `img`. Qualities are tried from
    /// high to low, stopping once quality clearly falls short: size and similarity aren't perfectly monotonic
    /// (encoders change chroma subsampling at some steps), so every passing step is kept and the smallest wins.
    static func smallestLookalike(_ img: CGImage, as fmt: ImageFormat, metadata: [CFString: Any],
                                  similarity: Double) throws -> Data? {
        let sample = sample(of: fmt.supportsAlpha ? img : flattened(img))
        let reference = Similarity(reference: sample)
        let qualities = Array(stride(from: 0.95, through: 0.3, by: -0.05))
        // The sample is small, so every quality is tried at once, one per core.
        let results = UnsafeMutableBufferPointer<(size: Int, passes: Bool)?>.allocate(capacity: qualities.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: qualities.count) { i in
            guard let data = try? encode(sample, as: fmt, quality: qualities[i]),
                  let decoded = decodeFully(data, maxPixel: max(sample.width, sample.height)) else { return }
            results[i] = (data.count, reference.score(decoded) >= similarity)
        }
        // Read back from high quality to low, exactly as if they had been tried one by one.
        var chosen: (quality: Double, size: Int)?
        var misses = 0
        for (quality, result) in zip(qualities, results) {
            guard let result else { continue }
            if result.passes {
                misses = 0
                if result.size < chosen?.size ?? .max { chosen = (quality, result.size) }
            } else {
                // One step can dip and the next recover; two in a row means it only gets worse from here.
                misses += 1
                if misses == 2 { break }
            }
        }
        guard let chosen else { return nil }
        return try encode(img, as: fmt, quality: chosen.quality, metadata: metadata, progressive: true)
    }

    /// Full-resolution patches from across the image, the 4×4 grid of 256-pixel squares that `Similarity` checks,
    /// packed into one 1024-pixel image. Patches sit on the 16-pixel grid JPEG and HEIC blocks use, so each one
    /// compresses just as it does inside the whole image, and trying a quality on this costs a fraction of trying
    /// it on a big photo. Small images are used whole.
    static func sample(of img: CGImage) -> CGImage {
        let side = 256
        guard img.width > side * 2 || img.height > side * 2 else { return img }
        let w = min(side, img.width), h = min(side, img.height)
        let alpha = hasAlpha(img)
        let space = img.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w * 4, height: h * 4, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else { return img }
        for row in 0..<4 {
            for column in 0..<4 {
                let x = (img.width - w) * column / 3 / 16 * 16, y = (img.height - h) * row / 3 / 16 * 16
                guard let patch = img.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { continue }
                // Core Graphics counts rows from the bottom; keep the patches in reading order.
                ctx.draw(patch, in: CGRect(x: column * w, y: (3 - row) * h, width: w, height: h))
            }
        }
        return ctx.makeImage() ?? img
    }

    /// Decodes every pixel up front through the thumbnail path: a lazily decoded image would be decoded again for
    /// every tile that's checked.
    private static func decodeFully(_ data: Data, maxPixel: Int) -> CGImage? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        return CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options) }
    }

    // MARK: Privacy

    public struct StripReport: Sendable {
        public let output: URL
        public let removed: [String]
        public let lossless: Bool
    }

    /// Human-readable list of identifying metadata in the first frame.
    public static func privateFields(of src: CGImageSource) -> [String] {
        let p = properties(src)
        var found: [String] = []
        if p[kCGImagePropertyGPSDictionary] != nil { found.append("GPS location") }
        if let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if exif[kCGImagePropertyExifDateTimeOriginal] != nil || exif[kCGImagePropertyExifDateTimeDigitized] != nil { found.append("Capture date") }
            if exif[kCGImagePropertyExifLensModel] != nil || exif[kCGImagePropertyExifLensMake] != nil { found.append("Lens") }
            if exif[kCGImagePropertyExifBodySerialNumber] != nil || exif[kCGImagePropertyExifLensSerialNumber] != nil { found.append("Serial numbers") }
            if exif[kCGImagePropertyExifCameraOwnerName] != nil { found.append("Owner name") }
            if exif[kCGImagePropertyExifUserComment] != nil { found.append("Comment") }
            if exif[kCGImagePropertyExifExposureTime] != nil || exif[kCGImagePropertyExifISOSpeedRatings] != nil { found.append("Camera settings") }
        }
        if let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil { found.append("Camera make/model") }
            if tiff[kCGImagePropertyTIFFSoftware] != nil || tiff[kCGImagePropertyTIFFHostComputer] != nil { found.append("Software/device") }
            if tiff[kCGImagePropertyTIFFArtist] != nil || tiff[kCGImagePropertyTIFFCopyright] != nil { found.append("Author/copyright") }
            if tiff[kCGImagePropertyTIFFDateTime] != nil, !found.contains("Capture date") { found.append("Capture date") }
        }
        if p[kCGImagePropertyIPTCDictionary] != nil { found.append("IPTC captions/credits") }
        if p.keys.contains(where: { ($0 as String).hasPrefix("{Maker") }) { found.append("Maker notes") }
        if let png = p[kCGImagePropertyPNGDictionary] as? [CFString: Any],
           [kCGImagePropertyPNGAuthor, kCGImagePropertyPNGComment, kCGImagePropertyPNGDescription,
            kCGImagePropertyPNGSoftware, kCGImagePropertyPNGCreationTime, kCGImagePropertyPNGTitle].contains(where: { png[$0] != nil }) {
            found.append("PNG text")
        }
        if hasForeignXMP(src) { found.append("XMP") }
        return found
    }

    private static func hasForeignXMP(_ src: CGImageSource) -> Bool {
        guard let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
              let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] else { return false }
        return tags.contains { tag in
            let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
            return !["exif", "tiff"].contains(prefix)
        }
    }

    /// SHA-256 of the decoded (un-oriented) pixels of frame 0 — proves a clean copy is visually identical.
    static func pixelHash(_ src: CGImageSource) -> String? {
        guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let data = img.dataProvider?.data as Data? else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Removes identifying metadata, keeping orientation. Tries a lossless rewrite first and verifies
    /// the pixels are byte-identical; falls back to a max-quality re-encode only if that's impossible.
    public static func stripMetadata(_ url: URL, options: Options) throws -> StripReport {
        let src = try source(url)
        guard let type = CGImageSourceGetType(src) else { throw MorphError("Unknown image type") }
        let removed = privateFields(of: src)
        let orientation = properties(src)[kCGImagePropertyOrientation] as? Int ?? 1
        let before = pixelHash(src)
        let out = Output.url(for: url, ext: url.pathExtension, suffix: "clean", options: options)
        let fm = FileManager.default

        func verify() -> (clean: Bool, identical: Bool) {
            guard let s = CGImageSourceCreateWithURL(out as CFURL, nil) else { return (false, false) }
            return (privateFields(of: s).isEmpty, before != nil && pixelHash(s) == before)
        }

        let meta = CGImageMetadataCreateMutable()
        if orientation != 1 {
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, orientation as CFNumber)
        }
        let copyOptions: [CFString: Any] = [
            kCGImageDestinationMetadata: meta,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        if let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil),
           CGImageDestinationCopyImageSource(dest, src, copyOptions as CFDictionary, nil) {
            let result = verify()
            if result.clean && result.identical { return StripReport(output: out, removed: removed, lossless: true) }
        }

        // Fallback: re-encode the raw pixels with nothing but orientation attached.
        try? fm.removeItem(at: out)
        guard let raw = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else {
            throw MorphError("Couldn't rewrite \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, raw, [kCGImagePropertyOrientation: orientation,
                                               kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw MorphError("Couldn't rewrite \(url.lastPathComponent)") }
        let result = verify()
        guard result.clean else {
            try? fm.removeItem(at: out)
            throw MorphError("Private metadata survived; no output was saved")
        }
        return StripReport(output: out, removed: removed, lossless: result.identical)
    }

    public static func summary(_ url: URL) throws -> [String: String] {
        if VectorOps.isSVG(url) { return try VectorOps.summary(url) }
        let src = try source(url)
        let p = properties(src)
        var info: [String: String] = [
            "Type": (CGImageSourceGetType(src) as String?) ?? "?",
            "Size": "\(p[kCGImagePropertyPixelWidth] ?? "?") × \(p[kCGImagePropertyPixelHeight] ?? "?")",
            "Frames": "\(CGImageSourceGetCount(src))",
        ]
        let priv = privateFields(of: src)
        info["Private metadata"] = priv.isEmpty ? "none" : priv.joined(separator: ", ")
        if let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude], let lon = gps[kCGImagePropertyGPSLongitude] {
            info["GPS"] = "\(lat) \(gps[kCGImagePropertyGPSLatitudeRef] ?? ""), \(lon) \(gps[kCGImagePropertyGPSLongitudeRef] ?? "")"
        }
        return info
    }
}
