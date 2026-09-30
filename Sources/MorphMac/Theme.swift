import AppKit
import SwiftUI

/// Morph's soft, bubbly look: warm tangerine accent, big continuous corners, rounded type.
/// The iOS app and the Android app mirror these values.
enum Theme {
    static let tangerine = Color(red: 1.00, green: 0.56, blue: 0.22)   // #FF8F38
    static let coral = Color(red: 1.00, green: 0.40, blue: 0.38)       // #FF6661
    static let accent = LinearGradient(colors: [tangerine, coral], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Cream in light mode, warm charcoal in dark.
    static let canvas = dynamic(light: NSColor(srgbRed: 1.00, green: 0.97, blue: 0.94, alpha: 1),
                                dark: NSColor(srgbRed: 0.12, green: 0.11, blue: 0.10, alpha: 1))
    static let surface = dynamic(light: .white,
                                 dark: NSColor(srgbRed: 0.18, green: 0.16, blue: 0.15, alpha: 1))
    static let tint = tangerine.opacity(0.14)

    static let radius: CGFloat = 22
    static let smallRadius: CGFloat = 14

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

/// Filled tangerine pill for the main action on a screen.
struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: Theme.coral.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tinted pill for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.tangerine)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.tint))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// A soft rounded card on the canvas.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

/// Round tinted badge holding an SF Symbol.
struct SymbolBubble: View {
    let symbol: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Theme.tangerine)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.tint))
    }
}

/// Bubbly replacement for a segmented control: the selection is a gradient pill that slides between options.
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option } } label: {
                    Text(label(option))
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(selected ? .white : .secondary)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background {
                            if selected { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}
