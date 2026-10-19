// Draws the DMG window background: `swift scripts/make-dmg-background.swift <out-folder>`.
// Writes background.png (640×420) and background@2x.png; dmg-settings.py places the icons on the bubbles.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let width: CGFloat = 640, height: CGFloat = 420
/// Icon centres, in Finder's top-left coordinates; keep in sync with dmg-settings.py.
let appCenter = CGPoint(x: 170, y: 220), appsCenter = CGPoint(x: 470, y: 220)

func hex(_ value: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}
let brand = hex(0x0B6E69)   // Teal Ink
let ink = hex(0x121A19)
let muted = hex(0x5C6664)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func text(_ string: String, font: NSFont, color: NSColor, centerX: CGFloat, top: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let size = (string as NSString).size(withAttributes: attrs)
    (string as NSString).draw(at: CGPoint(x: centerX - size.width / 2, y: height - top - size.height), withAttributes: attrs)
}

/// Finder coordinates (origin top-left) → AppKit (origin bottom-left).
func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Flat cool-paper canvas.
    hex(0xF1F4F3).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Playful soft bubbles in the corners.
    for (center, radius, alpha) in [(CGPoint(x: 600, y: 390), 90.0, 0.10), (CGPoint(x: 40, y: 40), 70.0, 0.08), (CGPoint(x: 590, y: 50), 36.0, 0.07)] {
        brand.withAlphaComponent(alpha * 0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    // Header: logo mark + wordmark, then the tagline.
    let word: [NSAttributedString.Key: Any] = [.font: rounded(30, .bold), .foregroundColor: ink]
    let wordWidth = ("Morph" as NSString).size(withAttributes: word).width
    // Centre the mark and wordmark together.
    let mark = NSRect(x: (width - (34 + 12 + wordWidth)) / 2, y: height - 70, width: 34, height: 34)
    brand.setFill()
    NSBezierPath(roundedRect: mark, xRadius: 10, yRadius: 10).fill()
    // The app icon's seven drops.
    NSColor.white.setFill()
    for i in -1..<6 {
        let angle = Double(i) * .pi / 3 - .pi / 2
        let x = mark.midX + (i < 0 ? 0 : cos(angle) * 6.5), y = mark.midY + (i < 0 ? 0 : sin(angle) * 6.5)
        NSBezierPath(ovalIn: NSRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)).fill()
    }
    ("Morph" as NSString).draw(at: CGPoint(x: mark.maxX + 12, y: mark.midY - 19), withAttributes: word)
    text("Convert anything, right where it is.", font: rounded(14, .medium), color: muted, centerX: width / 2, top: 82)

    // A soft white bubble under each icon.
    for center in [appCenter, appsCenter] {
        let c = flip(center)
        let disc = NSBezierPath(ovalIn: NSRect(x: c.x - 82, y: c.y - 82, width: 164, height: 164))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor.white.setFill()
        disc.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Curved arrow from the app to Applications.
    let start = flip(CGPoint(x: appCenter.x + 98, y: appCenter.y - 6))
    let end = flip(CGPoint(x: appsCenter.x - 104, y: appsCenter.y - 6))
    let control2 = CGPoint(x: end.x - 40, y: end.y + 44)
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end, controlPoint1: CGPoint(x: start.x + 40, y: start.y + 44), controlPoint2: control2)
    arc.lineWidth = 7
    arc.lineCapStyle = .round
    // Arrowhead wings follow the curve's direction where it lands.
    let angle = atan2(end.y - control2.y, end.x - control2.x)
    func wing(_ offset: CGFloat) -> CGPoint {
        CGPoint(x: end.x - 20 * cos(angle + offset), y: end.y - 20 * sin(angle + offset))
    }
    let head = NSBezierPath()
    head.move(to: wing(.pi / 5))
    head.line(to: end)
    head.line(to: wing(-.pi / 5))
    head.lineWidth = 7
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    // Stroke into a mask, then fill the mask.
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(arc.cgPath)
    ctx.addPath(head.cgPath)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    brand.setFill()
    NSRect(x: start.x - 10, y: end.y - 40, width: end.x - start.x + 20, height: 130).fill()
    ctx.restoreGState()

    // Footer instructions.
    text("Drag Morph onto Applications to install", font: rounded(15, .semibold), color: ink, centerX: width / 2, top: 330)
    text("FREE  ·  PRIVATE  ·  WORKS OFFLINE", font: rounded(10, .bold), color: brand, centerX: width / 2, top: 354, kern: 1.6)

    // Credit line: Morph is free, so word of mouth is the marketing.
    let credit = NSMutableAttributedString()
    let small: [NSAttributedString.Key: Any] = [.font: rounded(11, .medium), .foregroundColor: muted]
    credit.append(NSAttributedString(string: "Made with ", attributes: small))
    credit.append(NSAttributedString(string: "♥", attributes: [.font: rounded(11, .bold), .foregroundColor: brand]))
    credit.append(NSAttributedString(string: " by ", attributes: small))
    credit.append(NSAttributedString(string: "Geetansh Goyal", attributes: [.font: rounded(11, .bold), .foregroundColor: ink]))
    credit.append(NSAttributedString(string: "  ·  Free forever, share it with a friend", attributes: small))
    let creditSize = credit.size()
    credit.draw(at: CGPoint(x: (width - creditSize.width) / 2, y: height - 386 - creditSize.height))

    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
