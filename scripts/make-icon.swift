// Draws Morph's app icon.
//   swift scripts/make-icon.swift <out.iconset>        macOS iconset (bundle.sh turns it into AppIcon.icns)
//   swift scripts/make-icon.swift --square <out.png>   full-bleed 1024px square; iOS and Android mask it themselves
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let square = args.first == "--square"
let out = URL(fileURLWithPath: args.last ?? "AppIcon.iconset")

func render(_ px: Int, square: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
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
    // Tangerine → coral, the same accent as the apps' Theme.
    NSGradient(colors: [NSColor(srgbRed: 1.00, green: 0.56, blue: 0.22, alpha: 1),
                        NSColor(srgbRed: 1.00, green: 0.40, blue: 0.38, alpha: 1)])!
        .draw(in: shape, angle: -60)

    // The menu bar glyph, white, filling the middle of the tile.
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * (square ? 0.42 : 0.52), weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: (s - g.width) / 2, y: (s - g.height) / 2, width: g.width, height: g.height))
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
