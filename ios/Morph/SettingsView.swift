import SwiftUI
import MorphCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("compression") private var compression = CompressionLevel.balanced.rawValue
    @AppStorage("haptics") private var haptics = true
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = true
    @AppStorage(SizeLimit.key) private var sizeLimit = 0
    @AppStorage("photoSize") private var photoSize = ""
    @AppStorage("photoCaption") private var photoCaption = ""

    var body: some View {
        PaletteScope {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Settings").font(Theme.font(28, .bold))
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
                    }
                    .padding(.top, 24).padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Compression").font(Theme.font(17, .semibold))
                        PillPicker(options: CompressionLevel.allCases,
                                   selection: Binding(get: { CompressionLevel(rawValue: compression) ?? .balanced },
                                                      set: { compression = $0.rawValue })) { $0.label }
                        Text((CompressionLevel(rawValue: compression) ?? .balanced).detail)
                            .font(Theme.font(14)).foregroundStyle(.secondary)
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("Size limit").font(Theme.font(17, .semibold))
                            Spacer()
                            SizeLimitMenu(limit: $sizeLimit)
                        }
                        Text(SizeLimit.detail(sizeLimit)).font(Theme.font(14)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("Photo size").font(Theme.font(17, .semibold))
                            Spacer()
                            PhotoSizeMenu(stored: $photoSize)
                        }
                        Text(PixelSize(photoSize).map { "Resize makes photos exactly \($0.label) as a JPG, cropped to fill, and under your size limit if one is set. For passport, visa and exam forms." }
                             ?? "Pick the exact size a form asks for, like 600 × 600, and Resize makes it.")
                            .font(Theme.font(14)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if PixelSize(photoSize) != nil {
                            TextField("Name to print below the photo (optional)", text: $photoCaption)
                                .textFieldStyle(.roundedBorder).font(Theme.font(15))
                            Text("Some exam forms want the name and the date the photo was taken under it.")
                                .font(Theme.font(13)).foregroundStyle(.tertiary)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Color").font(Theme.font(17, .semibold))
                            Spacer()
                            Text(Palette.current.name).font(Theme.font(15, .semibold)).foregroundStyle(Theme.brandText)
                        }
                        PalettePicker(size: 36)
                        Text("For highlights and buttons. The app icon stays Teal Ink.")
                            .font(Theme.font(14)).foregroundStyle(.secondary)
                    }
                    .card()

                    row("hand.tap.fill", "Haptics", "A gentle tap when a job finishes.") {
                        Toggle("", isOn: $haptics).labelsHidden().tint(Theme.brand)
                    }

                    row("folder.fill", "Your results", "Kept in the Files app under On My iPhone → Morph.") {
                        Button("Open") {
                            if let url = URL(string: "shareddocuments://" + AppState.results.path) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(SoftButtonStyle())
                    }

                    row("square.and.arrow.up.fill", "Share to Morph", "In any app, tap Share, then Morph in the app row.") { EmptyView() }

                    row("sparkles", "Welcome guide", "See the introduction again.") {
                        Button("Show") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { hasSeenWelcome = false }
                        }
                        .buttonStyle(SoftButtonStyle())
                    }

                    row("hand.raised.fill", "Privacy", "Morph collects nothing. Your files never leave this device.") {
                        Link("Read", destination: URL(string: "https://morph.geetanshgoyal.in/privacy.html")!)
                            .buttonStyle(SoftButtonStyle())
                    }

                    row("questionmark.bubble.fill", "Help and feedback", "Questions, ideas or a file that didn't convert.") {
                        Link("Open", destination: URL(string: "https://morph.geetanshgoyal.in/support.html")!)
                            .buttonStyle(SoftButtonStyle())
                    }

                    Text("Morph \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Everything stays on your device")
                        .font(Theme.font(12)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.top, 10)
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
            .background(Theme.canvas.ignoresSafeArea())
        }
    }

    private func row<Trailing: View>(_ symbol: String, _ title: String, _ detail: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            SymbolBubble(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(16, .semibold))
                Text(detail).font(Theme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .card(padding: 14)
    }
}
