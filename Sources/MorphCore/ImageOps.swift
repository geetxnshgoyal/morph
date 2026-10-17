import Foundation
import ImageIO
import CoreGraphics
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
        try image(from: source(url), maxPixel: maxPixel)
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
        let src = try source(url)
        let fmt = outputFormat(for: src)
        let img = try image(from: src, maxPixel: options.maxPixel ?? 2048)
        // Name by the size actually written: smaller images are never upscaled.
        let out = Output.url(for: url, ext: fmt.rawValue, suffix: "\(max(img.width, img.height))px", options: options)
        try write(img, as: fmt, quality: options.quality ?? 0.9, metadata: carriedMetadata(src), to: out)
        return out
    }

    /// Makes the file smaller without a visible change: re-encodes at a range of qualities, compares each with
    /// the original and keeps the smallest that still looks the same at the chosen compression level. Throws
    /// `MorphNote` when that saves under 5%, rather than writing a near-identical copy. With `targetBytes`,
    /// binary-searches quality, then downscales until the file fits.
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
        let out = Output.url(for: url, ext: fmt.rawValue, suffix: "compressed", options: options)
        var longest = max(img.width, img.height)
        for _ in 0..<10 {
            var lo = 0.05, hi = 0.95, best: Data?
            for _ in 0..<7 {
                let mid = (lo + hi) / 2
                let data = try encode(img, as: fmt, quality: mid, metadata: meta)
                if data.count <= target { best = data; lo = mid } else { hi = mid }
            }
            if let best { try best.write(to: out); return out }
            longest = Int(Double(longest) * 0.8)
            guard longest > 64 else { break }
            img = try image(from: src, maxPixel: longest)
        }
        throw MorphError("Couldn't get \(url.lastPathComponent) under \(ByteCountFormatter.string(fromByteCount: Int64(target), countStyle: .file))")
    }

    /// The smallest encoding that still scores at least `similarity` against `img`. Qualities are tried from
    /// high to low, stopping once quality clearly falls short: size and similarity aren't perfectly monotonic
    /// (encoders change chroma subsampling at some steps), so every passing step is kept and the smallest wins.
    static func smallestLookalike(_ img: CGImage, as fmt: ImageFormat, metadata: [CFString: Any],
                                  similarity: Double) throws -> Data? {
        let reference = Similarity(reference: fmt.supportsAlpha ? img : flattened(img))
        var best: Data?
        var misses = 0
        for quality in stride(from: 0.95, through: 0.3, by: -0.05) {
            let data = try encode(img, as: fmt, quality: quality, metadata: metadata, progressive: true)
            // Decode fully up front through the thumbnail path: a lazily decoded image would be decoded again for
            // every tile that's checked.
            let decodeNow = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCacheImmediately: true,
                             kCGImageSourceThumbnailMaxPixelSize: max(img.width, img.height)] as CFDictionary
            guard let decoded = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCreateThumbnailAtIndex($0, 0, decodeNow) })
            else { continue }
            if reference.score(decoded) >= similarity {
                misses = 0
                if data.count < best?.count ?? .max { best = data }
            } else {
                // One step can dip and the next recover; two in a row means it only gets worse from here.
                misses += 1
                if misses == 2 { break }
            }
        }
        return best
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
