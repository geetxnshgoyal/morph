import SwiftUI
import MorphCore

/// "How it works" demo: a small wheel that plays through each wheel in turn, with that wheel's keys lit up
/// beside it, so the drag shortcuts are learned by watching rather than reading.
struct WheelTour: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var tick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Highlight steps spent on each wheel before moving to the next.
    private let stepsPerWheel = 4

    private var wheels: [Action.Group] {
        let set = Preferences.wheels.filter { !prefs.dragKeys(for: $0).isEmpty }
        return set.isEmpty ? Preferences.wheels : set
    }

    private var current: Action.Group { wheels[(tick / stepsPerWheel) % wheels.count] }

    var body: some View {
        HStack(spacing: 24) {
            MiniWheel(group: current, highlight: tick % stepsPerWheel)
                .frame(width: 184, height: 184)
                .id(current)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            VStack(alignment: .leading, spacing: 9) {
                ForEach(wheels, id: \.self) { group in
                    KeyRow(group: group, keys: prefs.dragKeys(for: group), active: group == current)
                        .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { show(group) } }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 1800 : 750))
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78)) { tick += 1 }
            }
        }
    }

    private func show(_ group: Action.Group) {
        guard let i = wheels.firstIndex(of: group) else { return }
        tick = i * stepsPerWheel
    }
}

/// One wheel and the keys that summon it, lit while the demo shows it.
private struct KeyRow: View {
    let group: Action.Group
    let keys: DragKeys
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            Keycap(text: keys.isEmpty ? "–" : keys.symbols, pressed: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.label).font(Theme.font(13, .semibold))
                Text(detail).font(Theme.font(11)).foregroundStyle(.secondary)
            }
        }
        .opacity(active ? 1 : 0.6)
        .contentShape(Rectangle())
    }

    private var detail: String {
        switch group {
        case .convert: "Images, video, audio and docs to any format"
        case .tool: "Compress, clean up, read text and codes"
        case .recipe: "Several steps in one drop"
        case .file: "AirDrop, copy, move, open Terminal"
        }
    }
}

/// A keyboard key: raised normally, pressed and filled when its wheel is showing.
struct Keycap: View {
    let text: String
    var pressed = false

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(pressed ? Theme.onBrand : Color.primary)
            .padding(.horizontal, 10)
            .frame(minWidth: 38, minHeight: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(pressed ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.surface))
                    .shadow(color: .black.opacity(pressed ? 0.05 : 0.18), radius: 0, y: pressed ? 1 : 3)
            }
            .offset(y: pressed ? 2 : 0)
    }
}

/// A small, non-interactive copy of the wheel with sample actions and a highlight that walks around it.
private struct MiniWheel: View {
    let group: Action.Group
    let highlight: Int

    private let inner: CGFloat = 40
    private let outer: CGFloat = 88

    private var symbols: [String] {
        switch group {
        case .convert: ["photo", "doc.richtext", "film", "waveform", "doc.text", "tablecells"]
        case .tool: ["arrow.down.right.and.arrow.up.left", "eye.slash", "text.viewfinder", "person.crop.circle.badge.xmark", "qrcode.viewfinder", "doc.zipper"]
        case .recipe: ["globe", "envelope", "lock.shield"]
        case .file: ["dot.radiowaves.left.and.right", "message", "doc.on.doc", "link", "folder", "terminal"]
        }
    }

    var body: some View {
        let count = symbols.count
        let lit = (highlight * 2 + 1) % count
        ZStack {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                let on = index == lit
                let angle = WheelModel.angle(of: index, count: count)
                let shape = PetalShape(centerAngle: angle, sectorAngle: 360 / Double(count), gapWidth: 4,
                                       innerRadius: inner, outerRadius: on ? outer + 6 : outer, cornerRadius: 6)
                ZStack {
                    shape.fill(on ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.surface))
                    shape.stroke(.white.opacity(0.35), lineWidth: 1)
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(on ? Theme.onBrand : Color.primary.opacity(0.75))
                        .offset(x: cos(angle * .pi / 180) * (inner + outer) / 2, y: sin(angle * .pi / 180) * (inner + outer) / 2)
                }
            }
            Circle().fill(Theme.surface).frame(width: inner * 2 - 10, height: inner * 2 - 10)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            Text(group.label).font(Theme.font(12, .bold))
        }
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The \(group.label) wheel")
    }
}
