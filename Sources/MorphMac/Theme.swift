import AppKit
import SwiftUI
import MorphCore

/// Morph's look: one flat brand colour, Teal Ink, on cool neutrals, with big continuous corners and rounded
/// type. The iOS app, the Android app and the website mirror these values.
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

    static let radius: CGFloat = 22
    static let smallRadius: CGFloat = 14

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    fileprivate static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    fileprivate static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
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
        case .ultramarine: return Color(nsColor: Theme.rgb(0x2F2EFF))
        case .green: return Color(nsColor: Theme.rgb(0x17804A))
        case .magenta: return Color(nsColor: Theme.rgb(0xD6007A))
        case .yellow: return Color(nsColor: Theme.rgb(0xFFD60A))
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
        case .teal: return Color(nsColor: Theme.rgb(0x0B6E69))
        case .ultramarine: return Color(nsColor: Theme.rgb(0x2F2EFF))
        case .green: return Color(nsColor: Theme.rgb(0x136B3E))
        case .magenta: return Color(nsColor: Theme.rgb(0xC2006E))
        case .yellow: return Color(nsColor: Theme.rgb(0x735A00))
        }
    }

    /// Labels on the fill: white, except on yellow.
    private func makeOnFill() -> Color { self == .yellow ? Color(nsColor: Theme.rgb(0x121318)) : .white }
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

/// Rebuilds the view when the accent changes in Settings, so every `Theme` colour inside picks it up at once.
struct FollowsPalette: ViewModifier {
    @AppStorage(Palette.key) private var palette = Palette.teal.rawValue

    func body(content: Content) -> some View { content.id(palette) }
}

extension View {
    func followsPalette() -> some View { modifier(FollowsPalette()) }
}

/// Builds its content again whenever the accent changes, for windows that keep state (a page, a tab) the change
/// shouldn't reset. The content is a closure on purpose: a view built ahead of time keeps the colours it had.
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
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12 * 0.7, weight: .semibold))
            }
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.tint))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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

/// A tinted pill that opens a menu of exact photo sizes, grouped (passport, exams, signature, social), or any size typed in.
struct PhotoSizeMenu: View {
    @Binding var size: PixelSize?
    @State private var typing = false
    @State private var custom = ""

    var body: some View {
        Menu {
            Button { size = nil } label: {
                if size == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(PixelSize.presets, id: \.group) { group in
                Section(group.group) {
                    ForEach(group.items, id: \.name) { item in
                        Button { size = item.size } label: {
                            let title = "\(item.name)  ·  \(item.size.label)"
                            if size == item.size { Label(title, systemImage: "checkmark") } else { Text(title) }
                        }
                    }
                }
            }
            Divider()
            Button("Custom Size…") {
                custom = size.map { "\($0.width) x \($0.height)" } ?? ""
                typing = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(size?.label ?? "Off")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12 * 0.7, weight: .semibold))
            }
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.tint))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .alert("Custom photo size", isPresented: $typing) {
            TextField("600 x 600", text: $custom)
            Button("Set") { if let parsed = PixelSize(custom) { size = parsed } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Width × height in pixels, as the form asks for it, such as 600 x 600.")
        }
    }
}

/// Teal pill for the main action on a screen: tinted Liquid Glass on macOS 26, a solid capsule before that.
struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(Theme.font(14, .semibold))
            .foregroundStyle(Theme.onBrand)
            .padding(.horizontal, 22).padding(.vertical, 10)
        if #available(macOS 26.0, *) {
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

/// Quieter pill for secondary actions: clear Liquid Glass on macOS 26, a tinted capsule before that.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.brandText)
            .padding(.horizontal, 12).padding(.vertical, 6)
        if #available(macOS 26.0, *) {
            label.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            label
                .background(Capsule().fill(Theme.tint))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

extension View {
    /// Floating controls: Liquid Glass on macOS 26, a soft surface before that. Content such as cards stays
    /// solid, as Apple's design guidance asks.
    @ViewBuilder func glassControl(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            modifier(MorphGlass(shape: shape))
        } else {
            background(shape.fill(Theme.surface)).shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
    }

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
            .foregroundStyle(Theme.brandText)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.tint))
    }
}

/// Bubbly replacement for a segmented control on a glass track: the selection is a teal pill that slides
/// between options.
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
                        .foregroundStyle(selected ? Theme.onBrand : .secondary)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background {
                            if selected { Capsule().fill(Theme.brand).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassControl(in: Capsule())
    }
}

// MARK: - Liquid Glass

/// Standard system Liquid Glass, so it follows the Clear or Tinted choice in System Settings automatically;
/// a frosted material before macOS 26.
struct MorphGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var interactive = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial))
        }
    }
}
