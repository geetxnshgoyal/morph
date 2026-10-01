import SwiftUI
import UIKit

/// Morph's soft, bubbly look; mirrors Sources/MorphMac/Theme.swift and the Android theme.
enum Theme {
    static let tangerine = Color(red: 1.00, green: 0.56, blue: 0.22)   // #FF8F38
    static let coral = Color(red: 1.00, green: 0.40, blue: 0.38)       // #FF6661
    static let accent = LinearGradient(colors: [tangerine, coral], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Cream in light mode, warm charcoal in dark.
    static let canvas = dynamic(light: UIColor(red: 1.00, green: 0.97, blue: 0.94, alpha: 1),
                                dark: UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1))
    static let surface = dynamic(light: .white,
                                 dark: UIColor(red: 0.18, green: 0.16, blue: 0.15, alpha: 1))
    static let tint = tangerine.opacity(0.14)

    static let radius: CGFloat = 26
    static let smallRadius: CGFloat = 18

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Filled tangerine pill for the main action on a screen.
struct BubbleButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(17, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 26).padding(.vertical, 15)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: Theme.coral.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tinted pill for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, .semibold))
            .foregroundStyle(Theme.tangerine)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(Theme.tint))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Shrinks a little under the finger; for tappable cards.
struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension View {
    /// A soft rounded card on the canvas.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

/// Round tinted badge holding an SF Symbol.
struct SymbolBubble: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.tangerine)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.tint))
    }
}

/// The app icon drawn in SwiftUI (asset-catalog app icons can't be loaded as images).
struct LogoMark: View {
    var size: CGFloat = 112

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.coral.opacity(0.35), radius: 20, y: 10)
    }
}

/// Bubbly segmented control: the selection is a gradient pill that slides between options.
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
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(selected ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selected { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.surface))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}
