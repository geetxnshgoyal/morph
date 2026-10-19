import SwiftUI

/// Launch: one drop of Teal Ink pulls apart into Morph's seven-dot mark, then the mark swells and dissolves into
/// the app behind it. About a second, skipped entirely with Reduce Motion.
struct MorphSplash: View {
    let onFinish: () -> Void
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            // 0.1 s as a drop, 0.65 s splitting (with a little overshoot), then a beat as the mark.
            let split = Self.springOut(min(1, max(0, (elapsed - 0.1) / 0.65)))
            ZStack {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 18) {
                    MorphMark(split: split, size: 132)
                    Text("Morph")
                        .font(Theme.font(30, .bold))
                        .opacity(min(1, max(0, (elapsed - 0.45) / 0.3)))
                        .offset(y: 8 * (1 - min(1, max(0, (elapsed - 0.45) / 0.3))))
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1050))
            onFinish()
        }
        .accessibilityHidden(true)
    }

    /// Ease-out with a slight overshoot past 1, like a drop snapping apart.
    static func springOut(_ x: Double) -> Double {
        let c = 1.6
        return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
    }
}
