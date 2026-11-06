// Draws Morph's app icon.
//   swift scripts/make-icon.swift <out.iconset>        macOS iconset (bundle.sh turns it into AppIcon.icns)
//   swift scripts/make-icon.swift --square <out.png> [size]   full-bleed, opaque square, 1024px by default (the App Store rejects
//                                                       alpha); iOS masks it itself
//   add --diwali before the path for the Diwali icon: the drops lit like diyas on maroon, a clay lamp below
import AppKit

let diwali = CommandLine.arguments.contains("--diwali")
let args = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--diwali" }
let square = args.first == "--square"
let out = URL(fileURLWithPath: args.last ?? "AppIcon.iconset")

func render(_ px: Int, square: Bool = false) -> Data {
    // Always draw into RGBA: AppKit can't draw into a 3-sample RGB rep, which left the square icon blank.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
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
    if diwali {
        drawDiwali(in: tile, shape: shape, scale: s, square: square)
        NSGraphicsContext.restoreGraphicsState()
        return square ? opaque(rep) : rep.representation(using: .png, properties: [:])!
    }
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
    return square ? opaque(rep) : rep.representation(using: .png, properties: [:])!
}

/// Deep maroon into saffron at the bottom; Morph's seven drops become flames, each lit with a warm glow, and a
/// clay diya sits under them.
func drawDiwali(in tile: NSRect, shape: NSBezierPath, scale s: CGFloat, square: Bool) {
    func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }
    NSGradient(colors: [rgb(0xF08A1C), rgb(0xB4371F), rgb(0x5B1236)], atLocations: [0, 0.38, 1], colorSpace: .sRGB)!
        .draw(in: shape, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let w = tile.width
    let mark = w * (square ? 0.5 : 0.54)
    let reach = mark * 0.31, radius = mark * 0.115
    let center = NSPoint(x: tile.midX, y: tile.midY + w * 0.07)
    // Each drop is a flame: a soft glow, then a teardrop from white-gold to orange.
    for i in -1..<6 {
        let angle = Double(i) * .pi / 3 - .pi / 2
        let c = NSPoint(x: center.x + (i < 0 ? 0 : cos(angle) * reach), y: center.y + (i < 0 ? 0 : sin(angle) * reach))
        NSGradient(colors: [rgb(0xFFD36B, 0.32), rgb(0xFFD36B, 0.08), rgb(0xFFD36B, 0)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
            .draw(in: NSBezierPath(ovalIn: NSRect(x: c.x - radius * 1.7, y: c.y - radius * 1.7, width: radius * 3.4, height: radius * 3.4)),
                  relativeCenterPosition: .zero)
        let flame = NSBezierPath()
        let tip = NSPoint(x: c.x, y: c.y + radius * 1.55)
        flame.move(to: tip)
        flame.curve(to: NSPoint(x: c.x, y: c.y - radius), controlPoint1: NSPoint(x: c.x + radius * 1.25, y: c.y + radius * 0.2),
                    controlPoint2: NSPoint(x: c.x + radius * 1.0, y: c.y - radius))
        flame.curve(to: tip, controlPoint1: NSPoint(x: c.x - radius * 1.0, y: c.y - radius),
                    controlPoint2: NSPoint(x: c.x - radius * 1.25, y: c.y + radius * 0.2))
        NSGradient(colors: [rgb(0xF0601A), rgb(0xFFB627), rgb(0xFFF6C8)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
            .draw(in: flame, angle: 90)
    }
    // The clay diya: a shallow bowl with a spout, under the flames.
    let bowlTop = tile.minY + w * 0.29
    let bowl = NSBezierPath()
    bowl.move(to: NSPoint(x: tile.midX - w * 0.27, y: bowlTop))
    bowl.line(to: NSPoint(x: tile.midX + w * 0.3, y: bowlTop + w * 0.015))
    bowl.line(to: NSPoint(x: tile.midX + w * 0.2, y: bowlTop - w * 0.03))
    bowl.curve(to: NSPoint(x: tile.midX - w * 0.22, y: bowlTop - w * 0.03),
               controlPoint1: NSPoint(x: tile.midX + w * 0.16, y: bowlTop - w * 0.13),
               controlPoint2: NSPoint(x: tile.midX - w * 0.18, y: bowlTop - w * 0.13))
    bowl.close()
    NSGradient(colors: [rgb(0xE0753A), rgb(0x8E2F14)])!.draw(in: bowl, angle: -90)
    rgb(0xFFC35A, 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: tile.midX - w * 0.24, y: bowlTop - w * 0.006, width: w * 0.5, height: w * 0.012),
                 xRadius: w * 0.006, yRadius: w * 0.006).fill()
    NSGraphicsContext.restoreGraphicsState()
}

/// The same pixels as a PNG with no alpha channel, as the App Store requires.
func opaque(_ rep: NSBitmapImageRep) -> Data {
    let ctx = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

if square {
    // An optional size after the path, e.g. 512 for the Play Store icon.
    let size = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
    try render(size, square: true).write(to: URL(fileURLWithPath: args[1]))
    exit(0)
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
