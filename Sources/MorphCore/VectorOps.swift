import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftDraw

/// SVG in both directions. ImageIO can't read SVG, so SVGs are drawn by SwiftDraw, a pure-Swift renderer: it works
/// the same on the Mac, in the CLI and on iOS, off the main thread, and never touches the network (only images
/// embedded as data: URLs are drawn). Images become SVGs by tracing them into shapes (see `Tracer`).
public enum VectorOps {
    public static func isSVG(_ url: URL) -> Bool { url.pathExtension.lowercased() == "svg" }

    /// Icons are often drawn at 16-24 px, so SVGs render at least this big on the long side unless a size is set.
    static let minimumPixel = 1024
    static let maximumPixel = 8192

    static func document(_ url: URL) throws -> SVG {
        // Not SVG(fileURL:), which caches by path and would miss edits to the file.
        guard let data = try? Data(contentsOf: url), let svg = SVG(data: data),
              svg.size.width > 0, svg.size.height > 0 else {
            throw MorphError("\(url.lastPathComponent) isn't a readable SVG")
        }
        return svg
    }

    /// The SVG's own size (its width and height, or its viewBox), raised to `minimumPixel` on the long side.
    /// `maxPixel` sets the long side exactly: a vector scales up as cleanly as down.
    static func pixelSize(of size: CGSize, maxPixel: Int?) -> (width: Int, height: Int) {
        let longest = max(size.width, size.height)
        let target = maxPixel.map(Double.init) ?? min(max(longest, Double(minimumPixel)), Double(maximumPixel))
        let scale = target / longest
        return (max(1, Int((size.width * scale).rounded())), max(1, Int((size.height * scale).rounded())))
    }

    /// Draws `svg` filling `rect` of a context whose origin is at the bottom left (bitmaps, PDF pages).
    static func draw(_ svg: SVG, in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(svg, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Renders on a transparent background; formats without alpha flatten it onto white when they're written.
    public static func render(_ url: URL, maxPixel: Int? = nil) throws -> CGImage {
        let svg = try document(url)
        let (width, height) = pixelSize(of: svg.size, maxPixel: maxPixel)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw MorphError("\(url.lastPathComponent) is too big to render")
        }
        draw(svg, in: ctx, rect: CGRect(x: 0, y: 0, width: width, height: height))
        guard let img = ctx.makeImage() else { throw MorphError("Couldn't render \(url.lastPathComponent)") }
        return img
    }

    /// The rendered SVG as an image source, so every action that reads images can read SVGs too.
    static func source(_ url: URL) throws -> CGImageSource {
        let png = try ImageOps.encode(render(url), as: .png, quality: 1)
        guard let src = CGImageSourceCreateWithData(png as CFData, nil) else { throw MorphError("Couldn't render \(url.lastPathComponent)") }
        return src
    }

    public static func summary(_ url: URL) throws -> [String: String] {
        let size = try document(url).size
        return ["Type": UTType.svg.identifier, "Size": "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"]
    }

    /// Traces an image into an SVG of filled shapes. The palette size comes from `options.colors`, or else from the
    /// compression level, which also sets how closely outlines follow the pixels: stronger makes simpler, smaller files.
    public static func trace(_ url: URL, options: Options) throws -> URL {
        let img = try ImageOps.load(url)
        var settings = Tracer.Settings(options.compression)
        if let colors = options.colors { settings.colors = min(max(colors, 2), 64) }
        // Big images are traced at about `workPixel` squared pixels (a cap on the long side would cost tall screenshots
        // their detail). Small ones are enlarged to 512 on the long side, so curves come out smooth rather than stepped;
        // enlarging anything bigger only stretches pixel noise into ragged edges.
        let longest = max(img.width, img.height)
        let fit = Double(settings.workPixel) / (Double(img.width) * Double(img.height)).squareRoot()
        let scale = fit < 1 ? fit : max(1, min(fit, 512 / Double(longest)))
        let width = max(1, Int((Double(img.width) * scale).rounded())), height = max(1, Int((Double(img.height) * scale).rounded()))
        let image = Tracer.Bitmap(width: width, height: height, rgba: try pixels(of: img, width: width, height: height))
        let sample = scale <= 1 ? image : Tracer.Bitmap(width: img.width, height: img.height, rgba: try pixels(of: img, width: img.width, height: img.height))
        let tracer = Tracer(image: image, sample: sample, settings: settings)
        // The SVG keeps the image's size (or fits Max size); the shapes are in traced pixels, scaled by the viewBox.
        let size = options.maxPixel.map { min(1, Double($0) / Double(longest)) } ?? 1
        let svg = tracer.svg(width: max(1, Int((Double(img.width) * size).rounded())),
                             height: max(1, Int((Double(img.height) * size).rounded())))
        let out = Output.url(for: url, ext: "svg", options: options)
        try Data(svg.utf8).write(to: out)
        return out
    }

    /// Straight (not premultiplied) RGBA bytes, redrawn at `width` × `height`.
    private static func pixels(of img: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw MorphError("The image is too big to trace") }
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = Int(bytes[i + 3])
            guard a > 0, a < 255 else { continue }
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, Int(bytes[i + c]) * 255 / a)) }
        }
        return bytes
    }
}
