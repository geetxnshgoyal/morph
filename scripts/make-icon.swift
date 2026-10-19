// Draws Morph's app icon.
//   swift scripts/make-icon.swift <out.iconset>        macOS iconset (bundle.sh turns it into AppIcon.icns)
//   swift scripts/make-icon.swift --square <out.png>   full-bleed, opaque 1024px square (the App Store rejects
//                                                       alpha); iOS masks it itself
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let square = args.first == "--square"
let out = URL(fileURLWithPath: args.last ?? "AppIcon.iconset")

func render(_ px: Int, square: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: square ? 3 : 4, hasAlpha: !square, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: 824/1024 rounded square, centred, with a soft drop shadow.
    let inset = square ? 0 : s * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = square ? 0 : tile.width * 0.225
    let shape = NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Flat Teal Ink, the apps' brand colour.
    NSColor(srgbRed: 0x0B / 255, green: 0x6E / 255, blue: 0x69 / 255, alpha: 1).setFill()
    shape.fill()

    // Morph's seven drops in white, point up, in the same proportions as MorphMark in the apps.
    let mark = tile.width * (square ? 0.58 : 0.62)
    let reach = mark * 0.31, radius = mark * 0.12
    NSColor.white.setFill()
    for i in -1..<6 {
        let angle = Double(i) * .pi / 3 - .pi / 2
        let x = tile.midX + (i < 0 ? 0 : cos(angle) * reach), y = tile.midY + (i < 0 ? 0 : sin(angle) * reach)
        NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if square {
    try render(1024, square: true).write(to: out)
    exit(0)
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
