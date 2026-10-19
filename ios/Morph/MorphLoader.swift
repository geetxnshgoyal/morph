import SwiftUI

// Morph's liquid motion: drops that orbit, stretch and merge like mercury, in Teal Ink.
// This file is shared word for word with Sources/MorphMac/MorphLoader.swift.

/// One circle of liquid.
struct Drop {
    var center: CGPoint
    var radius: CGFloat
}

/// Circles drawn blurred and then cut at half opacity: where two come close their blurs add up, so the
/// outlines flow together like liquid instead of overlapping like coins.
struct Metaballs: View {
    let drops: [Drop]
    let blur: CGFloat

    var body: some View {
        Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: blur))
            context.drawLayer { layer in
                for drop in drops {
                    layer.fill(Path(ellipseIn: CGRect(x: drop.center.x - drop.radius, y: drop.center.y - drop.radius,
                                                      width: drop.radius * 2, height: drop.radius * 2)),
                               with: .color(.black))
                }
            }
        }
    }
}

/// The "working on it" loader: four drops circle a pulsing core, reaching out and melting back in.
struct MorphLoader: View {
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Theme.brand
                .mask(Metaballs(drops: Self.drops(at: t, size: size), blur: size * 0.085))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Working")
    }

    static func drops(at t: Double, size: CGFloat) -> [Drop] {
        let center = CGPoint(x: size / 2, y: size / 2)
        var drops = [Drop(center: center, radius: size * (0.17 + 0.025 * sin(t * 3)))]
        for i in 0..<4 {
            let phase = Double(i) * .pi / 2
            let angle = t * 2.1 + phase
            let reach = size * (0.2 + 0.08 * sin(t * 1.6 + phase))
            drops.append(Drop(center: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach),
                              radius: size * (0.095 + 0.02 * cos(t * 2.3 + phase))))
        }
        return drops
    }
}

/// Morph's mark as liquid: at `split` 0 it is a single drop, at 1 the seven dots of the app icon, and anything
/// between is the drop pulling apart (the dots overshoot a little, like surface tension letting go).
struct MorphMark: View {
    var split: Double
    var size: CGFloat = 120

    var body: some View {
        Theme.brand
            .mask(Metaballs(drops: Self.drops(split: split, size: size), blur: size * 0.04))
            .frame(width: size, height: size)
    }

    static func drops(split: Double, size: CGFloat) -> [Drop] {
        let center = CGPoint(x: size / 2, y: size / 2)
        let s = CGFloat(split)
        let reach = size * 0.31 * s
        let radius = size * (0.24 - 0.12 * min(1, s))
        var drops = [Drop(center: center, radius: radius)]
        for i in 0..<6 {
            let angle = Double(i) * .pi / 3 - .pi / 2
            drops.append(Drop(center: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach), radius: radius))
        }
        return drops
    }
}
