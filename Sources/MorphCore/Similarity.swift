import CoreGraphics
import Foundation

/// How alike two images look: mean SSIM (structural similarity) of their luminance, where 1 means identical.
/// Measured at full resolution on up to 16 tiles spread across the frame, so compression artifacts aren't
/// hidden by downscaling and big photos stay quick to check.
struct Similarity {
    private let tiles: [CGRect]
    private let reference: [[UInt8]]

    init(reference image: CGImage) {
        tiles = Self.tiles(width: image.width, height: image.height)
        reference = tiles.map { Self.luma(image, in: $0) }
    }

    func score(_ candidate: CGImage) -> Double {
        var total = 0.0
        for (rect, ref) in zip(tiles, reference) {
            total += Self.ssim(ref, Self.luma(candidate, in: rect), width: Int(rect.width), height: Int(rect.height))
        }
        return total / Double(max(tiles.count, 1))
    }

    /// A 4×4 grid of 256-pixel tiles, or the whole image if it's small.
    private static func tiles(width: Int, height: Int) -> [CGRect] {
        let side = 256
        guard width > side * 2 || height > side * 2 else {
            return [CGRect(x: 0, y: 0, width: width, height: height)]
        }
        let w = min(side, width), h = min(side, height)
        var rects: [CGRect] = []
        for row in 0..<4 {
            for column in 0..<4 {
                rects.append(CGRect(x: (width - w) * column / 3, y: (height - h) * row / 3, width: w, height: h))
            }
        }
        return rects
    }

    /// Grey levels of `rect` (top-left origin, in pixels).
    private static func luma(_ image: CGImage, in rect: CGRect) -> [UInt8] {
        let w = Int(rect.width), h = Int(rect.height)
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let tile = image.cropping(to: rect) else { return pixels }
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            ctx?.draw(tile, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return pixels
    }

    /// Mean SSIM over 8×8 windows stepping 4 pixels at a time. Window sums come from summed-area tables, built
    /// in one pass over raw buffers so this stays quick even in unoptimized builds.
    private static func ssim(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> Double {
        let window = 8
        guard width >= window, height >= window else { return a == b ? 1 : 0 }
        let stride = width + 1, size = stride * (height + 1)
        // Tables for a, b, a², b² and a·b, interleaved: entry (x, y) holds the sums above and left of it.
        var tables = [Double](repeating: 0, count: size * 5)
        tables.withUnsafeMutableBufferPointer { t in
            a.withUnsafeBufferPointer { pa in
                b.withUnsafeBufferPointer { pb in
                    for y in 0..<height {
                        var row = (0.0, 0.0, 0.0, 0.0, 0.0)
                        for x in 0..<width {
                            let va = Double(pa[y * width + x]), vb = Double(pb[y * width + x])
                            row.0 += va; row.1 += vb; row.2 += va * va; row.3 += vb * vb; row.4 += va * vb
                            let here = ((y + 1) * stride + x + 1) * 5, above = (y * stride + x + 1) * 5
                            t[here] = t[above] + row.0
                            t[here + 1] = t[above + 1] + row.1
                            t[here + 2] = t[above + 2] + row.2
                            t[here + 3] = t[above + 3] + row.3
                            t[here + 4] = t[above + 4] + row.4
                        }
                    }
                }
            }
        }
        let n = Double(window * window), c1 = 6.5025, c2 = 58.5225   // (0.01·255)², (0.03·255)²
        var total = 0.0, count = 0
        tables.withUnsafeBufferPointer { t in
            func box(_ k: Int, _ x: Int, _ y: Int) -> Double {
                t[((y + window) * stride + x + window) * 5 + k] - t[(y * stride + x + window) * 5 + k]
                    - t[((y + window) * stride + x) * 5 + k] + t[(y * stride + x) * 5 + k]
            }
            for y in Swift.stride(from: 0, through: height - window, by: 4) {
                for x in Swift.stride(from: 0, through: width - window, by: 4) {
                    let meanA = box(0, x, y) / n, meanB = box(1, x, y) / n
                    let varA = (box(2, x, y) - n * meanA * meanA) / (n - 1)
                    let varB = (box(3, x, y) - n * meanB * meanB) / (n - 1)
                    let cov = (box(4, x, y) - n * meanA * meanB) / (n - 1)
                    total += ((2 * meanA * meanB + c1) * (2 * cov + c2)) / ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2))
                    count += 1
                }
            }
        }
        return total / Double(count)
    }
}
