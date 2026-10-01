import SwiftUI
import MorphCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("compression") private var compression = CompressionLevel.balanced.rawValue
    @AppStorage("haptics") private var haptics = true
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = true

    var body: some View {
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
                }
                .card()

                row("hand.tap.fill", "Haptics", "A gentle tap when a job finishes.") {
                    Toggle("", isOn: $haptics).labelsHidden().tint(Theme.tangerine)
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

                Text("Morph \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Everything stays on your device")
                    .font(Theme.font(12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding(.top, 10)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(Theme.canvas.ignoresSafeArea())
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
