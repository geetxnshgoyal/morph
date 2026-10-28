import SwiftUI
import MorphCore
import UIKit

/// Morph's look: one flat brand colour, Teal Ink, on cool neutrals; mirrors Sources/MorphMac/Theme.swift and
/// the Android theme.
enum Theme {
    /// The accent chosen in Settings (Teal Ink unless changed), for the one selected or primary thing on screen.
    static var brand: Color { Palette.current.fill }
    /// The accent for text and symbols, readable on the canvas in light and dark mode.
    static var brandText: Color { Palette.current.text }
    /// Labels and symbols drawn on a `brand` fill.
    static var onBrand: Color { Palette.current.onFill }
    static var tint: Color { Palette.current.tint }

    /// Cool paper in light mode, deep teal-black in dark.
    static let canvas = dynamic(light: rgb(0xF1F4F3), dark: rgb(0x0E1414))
    static let surface = dynamic(light: .white, dark: rgb(0x172020))

    static let radius: CGFloat = 26
    static let smallRadius: CGFloat = 18

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    fileprivate static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    fileprivate static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The accent colours people can choose in Settings. Teal Ink is Morph's own and the default; the app icon stays
/// Teal Ink whatever is picked. Every option keeps labels on its fill at WCAG AA or better in light and dark mode.
enum Palette: String, CaseIterable, Identifiable {
    case teal, ultramarine, green, magenta, yellow

    static let key = "palette"
    /// The chosen palette, kept in memory: views read it on every frame.
    static var current: Palette { PaletteStore.shared.current }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .teal: return "Teal Ink"
        case .ultramarine: return "Ultramarine"
        case .green: return "Green"
        case .magenta: return "Magenta"
        case .yellow: return "Yellow"
        }
    }

    var fill: Color { Self.built[self]!.fill }
    var text: Color { Self.built[self]!.text }
    var onFill: Color { Self.built[self]!.onFill }
    var textOnWhite: Color { Self.built[self]!.textOnWhite }
    var tint: Color { Self.built[self]!.tint }

    /// Every colour is built once. Views ask for them on every frame, and handing back the same instance lets
    /// SwiftUI see that nothing changed instead of redrawing.
    private static let built: [Palette: (fill: Color, text: Color, onFill: Color, textOnWhite: Color, tint: Color)] =
        Dictionary(uniqueKeysWithValues: allCases.map { palette in
            let fill = palette.makeFill()
            return (palette, (fill, palette.makeText(), palette.makeOnFill(), palette.makeTextOnWhite(), fill.opacity(0.12)))
        })

    /// Fills; Teal Ink steps lighter in dark mode so filled shapes stand off the dark canvas.
    private func makeFill() -> Color {
        switch self {
        case .teal: return Theme.dynamic(light: Theme.rgb(0x0B6E69), dark: Theme.rgb(0x157F79))
        case .ultramarine: return Color(uiColor: Theme.rgb(0x2F2EFF))
        case .green: return Color(uiColor: Theme.rgb(0x17804A))
        case .magenta: return Color(uiColor: Theme.rgb(0xD6007A))
        case .yellow: return Color(uiColor: Theme.rgb(0xFFD60A))
        }
    }

    /// Text and symbols: deep enough to read on light surfaces, light enough on dark ones.
    private func makeText() -> Color {
        switch self {
        case .teal: return Theme.dynamic(light: Theme.rgb(0x0B6E69), dark: Theme.rgb(0x4FC1B9))
        case .ultramarine: return Theme.dynamic(light: Theme.rgb(0x2F2EFF), dark: Theme.rgb(0xA6A8FF))
        case .green: return Theme.dynamic(light: Theme.rgb(0x136B3E), dark: Theme.rgb(0x62C48E))
        case .magenta: return Theme.dynamic(light: Theme.rgb(0xC2006E), dark: Theme.rgb(0xFF8CC6))
        case .yellow: return Theme.dynamic(light: Theme.rgb(0x735A00), dark: Theme.rgb(0xFFD60A))
        }
    }

    /// This palette's text colour as it reads on white, for controls drawn on white in both modes.
    private func makeTextOnWhite() -> Color {
        switch self {
        case .teal: return Color(uiColor: Theme.rgb(0x0B6E69))
        case .ultramarine: return Color(uiColor: Theme.rgb(0x2F2EFF))
        case .green: return Color(uiColor: Theme.rgb(0x136B3E))
        case .magenta: return Color(uiColor: Theme.rgb(0xC2006E))
        case .yellow: return Color(uiColor: Theme.rgb(0x735A00))
        }
    }

    /// Labels on the fill: white, except on yellow.
    private func makeOnFill() -> Color { self == .yellow ? Color(uiColor: Theme.rgb(0x121318)) : .white }
}

/// Holds the chosen palette in memory and re-reads it whenever settings change, so `Palette.current` costs nothing.
private final class PaletteStore {
    static let shared = PaletteStore()
    private(set) var current: Palette

    private init() {
        current = Self.read()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.current = Self.read()
        }
    }

    private static func read() -> Palette {
        Palette(rawValue: UserDefaults.standard.string(forKey: Palette.key) ?? "") ?? .teal
    }
}

/// Builds its content again whenever the accent changes in Settings, so every `Theme` colour inside picks it up at
/// once. The content is a closure on purpose: a view built ahead of time would keep the colours it was built with.
struct PaletteScope<Content: View>: View {
    @AppStorage(Palette.key) private var palette = Palette.teal.rawValue
    @ViewBuilder var content: () -> Content

    var body: some View { content().id(palette) }
}

/// One round swatch per palette; the chosen one wears a ring.
struct PalettePicker: View {
    var size: CGFloat = 26
    @AppStorage(Palette.key) private var palette = Palette.teal.rawValue

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Palette.allCases) { option in
                let selected = option.rawValue == palette
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { palette = option.rawValue } } label: {
                    Circle().fill(option.fill)
                        .frame(width: size, height: size)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(option.onFill)
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? option.text : Color.clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.name)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Picks Compress's size limit: none, a common upload-form size, or any size typed in ("300 KB", "1.5 MB").
struct SizeLimitMenu: View {
    @Binding var limit: Int
    @State private var typing = false
    @State private var custom = ""

    var body: some View {
        Menu {
            Picker("Size limit", selection: $limit) {
                Text("No limit").tag(0)
                ForEach(SizeLimit.presets, id: \.self) { Text(SizeLimit.label($0)).tag($0) }
                if limit > 0, !SizeLimit.presets.contains(limit) { Text(SizeLimit.label(limit)).tag(limit) }
            }
            .pickerStyle(.inline)
            Button("Custom Size…") {
                custom = limit > 0 ? SizeLimit.label(limit) : ""
                typing = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(SizeLimit.label(limit))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 15 * 0.7, weight: .semibold))
            }
            .font(Theme.font(15, .semibold))
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(Theme.tint))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .alert("Custom size limit", isPresented: $typing) {
            TextField("200 KB", text: $custom)
            Button("Set") {
                if let bytes = Options.parseSize(custom), bytes >= 5_000 { limit = bytes }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a size such as 300 KB or 1.5 MB.")
        }
    }
}

/// A tinted pill that opens a menu of exact photo sizes, grouped (passport, exams, signature, social), or any size
/// typed in. Stored as text like "600x600"; empty is off.
struct PhotoSizeMenu: View {
    @Binding var stored: String
    @State private var typing = false
    @State private var custom = ""

    private var size: PixelSize? { PixelSize(stored) }
    private func key(_ size: PixelSize) -> String { "\(size.width)x\(size.height)" }

    var body: some View {
        Menu {
            Button { stored = "" } label: {
                if size == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(PixelSize.presets, id: \.group) { group in
                Section(group.group) {
                    ForEach(group.items, id: \.name) { item in
                        Button { stored = key(item.size) } label: {
                            if size == item.size { Label("\(item.name) · \(item.size.label)", systemImage: "checkmark") }
                            else { Text("\(item.name) · \(item.size.label)") }
                        }
                    }
                }
            }
            Button("Custom Size…") {
                custom = size.map { "\($0.width) x \($0.height)" } ?? ""
                typing = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(size?.label ?? "Off")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 15 * 0.7, weight: .semibold))
            }
            .font(Theme.font(15, .semibold))
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(Theme.tint))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .alert("Custom photo size", isPresented: $typing) {
            TextField("600 x 600", text: $custom)
            Button("Set") { if let parsed = PixelSize(custom) { stored = key(parsed) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Width × height in pixels, as the form asks for it, such as 600 x 600.")
        }
    }
}

/// Teal pill for the main action on a screen: tinted Liquid Glass on iOS 26, a solid capsule before that.
struct BubbleButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(Theme.font(17, .semibold))
            .foregroundStyle(Theme.onBrand)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 26).padding(.vertical, 15)
        if #available(iOS 26.0, *) {
            // Interactive glass does its own press response.
            label.glassEffect(.regular.tint(Theme.brand).interactive(), in: Capsule())
        } else {
            label
                .background(Capsule().fill(Theme.brand))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Quieter pill for secondary actions: clear Liquid Glass on iOS 26, a tinted capsule before that.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(Theme.font(15, .semibold))
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 16).padding(.vertical, 10)
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            label
                .background(Capsule().fill(Theme.tint))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
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
    /// Floating controls (toolbar buttons and the like): Liquid Glass on iOS 26, a soft surface before that.
    /// Content such as cards stays solid, as Apple's design guidance asks.
    @ViewBuilder func glassControl(in shape: some Shape, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            modifier(MorphGlass(shape: shape, tint: tint, interactive: true))
        } else {
            background(shape.fill(tint ?? Theme.surface)).shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
    }

    /// Lets sheets use the system's Liquid Glass background on iOS 26; the plain canvas before that.
    @ViewBuilder func sheetBackground() -> some View {
        if #available(iOS 26.0, *) { self } else { presentationBackground(Theme.canvas) }
    }

    /// The canvas behind a sheet's content, left out on iOS 26 so the glass sheet shows through.
    @ViewBuilder func sheetCanvas() -> some View {
        if #available(iOS 26.0, *) { self } else { background(Theme.canvas.ignoresSafeArea()) }
    }

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
            .foregroundStyle(Theme.brandText)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.tint))
    }
}

/// The app icon drawn in SwiftUI (asset-catalog app icons can't be loaded as images): Morph's seven drops in
/// white on Teal Ink, whichever accent is chosen, like the icon itself.
struct LogoMark: View {
    var size: CGFloat = 112

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Palette.teal.fill)
            .frame(width: size, height: size)
            .overlay {
                Canvas { context, canvas in
                    for drop in MorphMark.drops(split: 1, size: canvas.width * 0.62) {
                        let inset = canvas.width * 0.19
                        context.fill(Circle().path(in: CGRect(x: inset + drop.center.x - drop.radius, y: inset + drop.center.y - drop.radius,
                                                              width: drop.radius * 2, height: drop.radius * 2)), with: .color(.white))
                    }
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

/// Bubbly segmented control on a glass track: the selection is a teal pill that slides between options.
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
                        .foregroundStyle(selected ? Theme.onBrand : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selected { Capsule().fill(Theme.brand).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassControl(in: Capsule())
    }
}

// MARK: - Liquid Glass

/// Standard system Liquid Glass, so it follows the Clear or Tinted choice in System Settings automatically;
/// a frosted material before iOS 26.
struct MorphGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var interactive = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial))
        }
    }
}
