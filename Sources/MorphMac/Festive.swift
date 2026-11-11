import SwiftUI

// Shared by the Mac and iPhone apps (ios/project.yml lists this file).

/// Seasonal touches for the menu bar panel. For Diwali a saffron and maroon card with a lit diya
/// wishes a happy Diwali above the drop area, as on Android; the rest of the year the panel is Morph's own.
enum Festive {
    /// Diwali (Lakshmi Puja) for the next few years; add a line when these run out.
    private static let diwaliDays: [DateComponents] = [
        .init(year: 2026, month: 11, day: 8), .init(year: 2027, month: 10, day: 29), .init(year: 2028, month: 10, day: 17),
        .init(year: 2029, month: 11, day: 5), .init(year: 2030, month: 10, day: 26),
    ]

    /// From three days before Diwali to a week after.
    static var isDiwali: Bool {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        return diwaliDays.compactMap(cal.date(from:)).contains { day in
            (-3...7).contains(cal.dateComponents([.day], from: day, to: today).day ?? .max)
        }
    }
}

struct DiwaliCard: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Happy Diwali!").font(Theme.font(16, .bold))
                Text("Wishing you light, joy and a happy new year.").font(Theme.font(11.5, .medium)).opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.88))
            Spacer(minLength: 0)
            Diya().frame(width: 46, height: 50)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color(red: 0.36, green: 0.07, blue: 0.21), Color(red: 0.71, green: 0.22, blue: 0.12),
                                    Color(red: 0.94, green: 0.54, blue: 0.11)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A clay diya whose flame flickers; still with Reduce Motion.
private struct Diya: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let sway = CGFloat(sin(t * 6.2) * 0.6 + sin(t * 9.7) * 0.4)
                // Glow behind the flame.
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.1, y: h * 0.02, width: w * 0.8, height: w * 0.8)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.83, blue: 0.42).opacity(0.55), .clear]),
                                               center: CGPoint(x: w * 0.5, y: h * 0.4), startRadius: 0, endRadius: w * 0.42))
                // Flame: a teardrop whose tip sways.
                let tip = CGPoint(x: w * 0.5 + sway * w * 0.04, y: h * 0.08)
                var flame = Path()
                flame.move(to: tip)
                flame.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.56), control1: CGPoint(x: w * 0.66, y: h * 0.32), control2: CGPoint(x: w * 0.64, y: h * 0.52))
                flame.addCurve(to: tip, control1: CGPoint(x: w * 0.36, y: h * 0.52), control2: CGPoint(x: w * 0.34, y: h * 0.32))
                ctx.fill(flame, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.78), Color(red: 1, green: 0.71, blue: 0.15),
                                                                       Color(red: 0.94, green: 0.38, blue: 0.1)]),
                                                      startPoint: tip, endPoint: CGPoint(x: w * 0.5, y: h * 0.56)))
                // The clay lamp: a shallow bowl with a spout on the right.
                var bowl = Path()
                bowl.move(to: CGPoint(x: w * 0.06, y: h * 0.6))
                bowl.addLine(to: CGPoint(x: w * 0.96, y: h * 0.6))
                bowl.addLine(to: CGPoint(x: w * 0.76, y: h * 0.67))
                bowl.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.67), control1: CGPoint(x: w * 0.72, y: h * 0.94), control2: CGPoint(x: w * 0.24, y: h * 0.94))
                bowl.closeSubpath()
                ctx.fill(bowl, with: .linearGradient(Gradient(colors: [Color(red: 0.88, green: 0.46, blue: 0.23), Color(red: 0.56, green: 0.18, blue: 0.08)]),
                                                     startPoint: CGPoint(x: 0, y: h * 0.6), endPoint: CGPoint(x: 0, y: h * 0.86)))
                ctx.fill(Path(CGRect(x: w * 0.14, y: h * 0.59, width: w * 0.7, height: h * 0.025)), with: .color(Color(red: 1, green: 0.76, blue: 0.35).opacity(0.85)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The Diwali wheel

extension Festive {
    static let marigold = Color(red: 1, green: 0.67, blue: 0.1)
    static let saffron = Color(red: 0.95, green: 0.45, blue: 0.1)
    static let rani = Color(red: 0.86, green: 0.16, blue: 0.47)
}

/// A rangoli for the wheel's hub: two rings of petals around a dotted circle, in marigold, saffron and pink.
struct Rangoli: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            func petals(count: Int, inner: CGFloat, outer: CGFloat, width: CGFloat, turn: Double, color: Color) {
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi + turn
                    var petal = Path()
                    let base = CGPoint(x: c.x + inner * CGFloat(cos(a)), y: c.y + inner * CGFloat(sin(a)))
                    let tip = CGPoint(x: c.x + outer * CGFloat(cos(a)), y: c.y + outer * CGFloat(sin(a)))
                    let side = CGFloat(width)
                    let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
                    let normal = CGPoint(x: -CGFloat(sin(a)) * side, y: CGFloat(cos(a)) * side)
                    petal.move(to: base)
                    petal.addQuadCurve(to: tip, control: CGPoint(x: mid.x + normal.x, y: mid.y + normal.y))
                    petal.addQuadCurve(to: base, control: CGPoint(x: mid.x - normal.x, y: mid.y - normal.y))
                    ctx.fill(petal, with: .color(color.opacity(0.22)))
                    ctx.stroke(petal, with: .color(color.opacity(0.55)), lineWidth: 0.8)
                }
            }
            petals(count: 12, inner: r * 0.62, outer: r * 0.96, width: r * 0.09, turn: 0, color: Festive.saffron)
            petals(count: 12, inner: r * 0.42, outer: r * 0.72, width: r * 0.08, turn: .pi / 12, color: Festive.rani)
            for i in 0..<24 {
                let a = Double(i) / 24 * 2 * .pi
                let p = CGPoint(x: c.x + r * 0.36 * CGFloat(cos(a)), y: c.y + r * 0.36 * CGFloat(sin(a)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)), with: .color(Festive.marigold.opacity(0.7)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Little lamps around the outside of the wheel that twinkle in turn, like a row of diyas on a doorstep.
struct DiyaRing: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let count = 18
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
                    let p = CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a)))
                    let glow = (sin(t * 2.4 + Double(i) * 0.9) + 1) / 2
                    let g = 6 + 5 * glow
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)),
                             with: .radialGradient(Gradient(colors: [Festive.marigold.opacity(0.55 * (0.5 + glow / 2)), .clear]),
                                                   center: p, startRadius: 0, endRadius: g))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)),
                             with: .color(Color(red: 1, green: 0.93, blue: 0.7)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Crackers over the wheel when a job finishes: a few bursts of sparks that rise, open and fall away.
/// With Reduce Motion, a single soft glow instead.
struct Crackers: View {
    @State private var start = Date()
    /// Once the last spark has fallen the animation stops, so a result left open doesn't keep redrawing.
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Burst { let x: CGFloat, y: CGFloat, delay: Double, colors: [Color] }
    private let bursts: [Burst] = [
        Burst(x: 0.5, y: 0.34, delay: 0, colors: [Festive.marigold, .white]),
        Burst(x: 0.24, y: 0.26, delay: 0.25, colors: [Festive.rani, Festive.marigold]),
        Burst(x: 0.78, y: 0.28, delay: 0.45, colors: [Color(red: 0.4, green: 0.85, blue: 1), .white]),
        Burst(x: 0.36, y: 0.56, delay: 0.7, colors: [Festive.saffron, Festive.marigold]),
        Burst(x: 0.66, y: 0.58, delay: 0.9, colors: [Color(red: 0.55, green: 1, blue: 0.5), Festive.rani]),
    ]
    static let duration = 2.2

    var body: some View {
        TimelineView(.animation(paused: finished)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                if reduceMotion {
                    let fade = max(0, 1 - elapsed / 1.2)
                    let c = CGPoint(x: size.width / 2, y: size.height * 0.42)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 120, y: c.y - 120, width: 240, height: 240)),
                             with: .radialGradient(Gradient(colors: [Festive.marigold.opacity(0.35 * fade), .clear]), center: c, startRadius: 0, endRadius: 120))
                    return
                }
                ctx.blendMode = .plusLighter
                for (b, burst) in bursts.enumerated() {
                    let local = elapsed - burst.delay
                    guard local > 0, local < 1.3 else { continue }
                    let origin = CGPoint(x: size.width * burst.x, y: size.height * burst.y)
                    let progress = local / 1.3
                    let fade = 1 - progress
                    // The flash where it opens.
                    if local < 0.18 {
                        let f = 1 - local / 0.18
                        ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 26, y: origin.y - 26, width: 52, height: 52)),
                                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.8 * f), .clear]), center: origin, startRadius: 0, endRadius: 26))
                    }
                    let sparks = 26
                    for i in 0..<sparks {
                        let a = Double(i) / Double(sparks) * 2 * .pi + Double(b)
                        let speed = 92.0 * (0.75 + 0.25 * Double((i * 7 + b) % 5) / 4)
                        // Out fast, slowing, then pulled down a little.
                        let travel = speed * (1 - pow(1 - progress, 2.4))
                        let fall = 38 * progress * progress
                        let p = CGPoint(x: origin.x + CGFloat(cos(a) * travel), y: origin.y + CGFloat(sin(a) * travel + fall))
                        let color = burst.colors[i % burst.colors.count]
                        let s = 2.6 * fade + 0.6
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2)), with: .color(color.opacity(fade)))
                        // A short trail behind each spark.
                        let back = CGPoint(x: origin.x + CGFloat(cos(a) * travel * 0.82), y: origin.y + CGFloat(sin(a) * travel * 0.82 + fall * 0.8))
                        var trail = Path(); trail.move(to: back); trail.addLine(to: p)
                        ctx.stroke(trail, with: .color(color.opacity(0.45 * fade)), lineWidth: s * 0.8)
                    }
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            finished = true
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
