import AppKit
import SwiftUI
import MorphCore

// MARK: - Setup rows (shared by Welcome and Settings)

/// Icon, title, explanation and a trailing control, on a soft card.
struct SetupRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            SymbolBubble(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(14, .semibold))
                Text(detail).font(Theme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .card(padding: 14)
    }
}

struct LoginItemRow: View {
    @ObservedObject private var login = LoginItem.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SetupRow(symbol: "power", title: "Open at login",
                     detail: "Keep Morph in the menu bar, ready whenever you need it.") {
                Toggle("", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Theme.tangerine)
            }
            if login.needsApproval {
                notice("macOS is waiting for your OK in Login Items.", button: "Open Login Items") { login.openSystemSettings() }
            }
            if let problem = login.problem {
                notice(problem, button: nil) {}
            }
        }
        .onAppear { login.refresh() }
    }

    private func notice(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.coral)
            Text(text).font(Theme.font(12))
            Spacer()
            if let button { Button(button, action: action).buttonStyle(SoftButtonStyle()) }
        }
        .padding(.horizontal, 14)
    }
}

struct DragShortcutRow: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SymbolBubble(symbol: "hand.draw.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag shortcut").font(Theme.font(14, .semibold))
                    Text(prefs.dragKey == .off
                         ? "Off. Turn it on to summon the wheel mid-drag."
                         : "While dragging files anywhere, hold \(prefs.dragKey.label) and drop them on the wheel.")
                        .font(Theme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            PillPicker(options: DragKey.allCases, selection: $prefs.dragKey) { $0.label }
        }
        .card(padding: 14)
    }
}

struct FinderServiceRow: View {
    var body: some View {
        SetupRow(symbol: "cursorarrow.click.2", title: "Right-click in Finder",
                 detail: "Select files, then Services → Open in Morph. Missing? Turn it on under Keyboard Shortcuts → Services.") {
            Button("Shortcuts") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            .buttonStyle(SoftButtonStyle())
        }
    }
}

struct FFmpegRow: View {
    @ObservedObject private var tools = ToolStatus.shared
    @State private var copied = false

    private var installed: Bool { tools.hasFFmpeg }

    var body: some View {
        SetupRow(symbol: installed ? "checkmark.seal.fill" : "film.stack",
                 title: installed ? "Extra formats unlocked" : "Extra formats (optional)",
                 detail: installed ? "ffmpeg found: MP3, WebM, FLAC, OGG and more are on."
                                   : "Install ffmpeg with Homebrew for MP3, WebM, FLAC and more.") {
            if !installed {
                VStack(spacing: 6) {
                    Button(copied ? "Copied!" : "Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                        copied = true
                    }
                    .buttonStyle(SoftButtonStyle())
                    if copied {
                        Text("Paste it in Terminal").font(Theme.font(11)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear { tools.refresh() }
    }
}

struct MoveToApplicationsRow: View {
    @State private var failure: String?

    var body: some View {
        SetupRow(symbol: "folder.badge.plus", title: "Move to Applications",
                 detail: failure ?? "Morph is running from \(AppLocation.bundle.deletingLastPathComponent().lastPathComponent). Login and Open With work best from Applications.") {
            Button("Move") {
                do { try AppLocation.moveToApplications() } catch { failure = error.localizedDescription }
            }
            .buttonStyle(SoftButtonStyle())
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    let onWelcome: () -> Void

    @ObservedObject private var prefs = Preferences.shared
    @State var tab = Tab.general

    enum Tab: String, CaseIterable { case general = "General", output = "Output", tools = "Tools" }

    var body: some View {
        VStack(spacing: 18) {
            PillPicker(options: Tab.allCases, selection: $tab) { $0.rawValue }

            ScrollView {
                VStack(spacing: 10) {
                    switch tab {
                    case .general: general
                    case .output: output
                    case .tools: tools
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .padding(.top, 40)
        .frame(width: 520, height: 440)
        .background(Theme.canvas)
        .tint(Theme.tangerine)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
    }

    @ViewBuilder private var general: some View {
        LoginItemRow()
        DragShortcutRow()
        if AppLocation.isBundled, !AppLocation.isInstalled { MoveToApplicationsRow() }
        SetupRow(symbol: "speaker.wave.2.fill", title: "Sounds", detail: "A soft chime when a job finishes.") {
            Toggle("", isOn: $prefs.playSounds).toggleStyle(.switch).labelsHidden()
        }
        SetupRow(symbol: "magnifyingglass", title: "Show results in Finder",
                 detail: "Open a Finder window on the new files when a job finishes.") {
            Toggle("", isOn: $prefs.revealWhenDone).toggleStyle(.switch).labelsHidden()
        }
        HStack {
            Button("Show Welcome Guide", action: onWelcome).buttonStyle(SoftButtonStyle())
            Spacer()
            Text("Morph \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · Everything stays on your Mac")
                .font(Theme.font(11)).foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var output: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save results").font(Theme.font(14, .semibold))
            choice("Next to the original", selected: prefs.outputFolder == nil) { prefs.outputFolder = nil }
            choice(prefs.outputFolder.map { "In \($0.lastPathComponent)" } ?? "In a folder I choose…",
                   selected: prefs.outputFolder != nil, action: chooseFolder)
            if let folder = prefs.outputFolder {
                Text(folder.path).font(Theme.font(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .padding(.leading, 30)
            }
            Text("Originals are never overwritten.").font(Theme.font(11)).foregroundStyle(.tertiary)
        }
        .card()

        VStack(alignment: .leading, spacing: 10) {
            Text("Compression").font(Theme.font(14, .semibold))
            PillPicker(options: CompressionLevel.allCases, selection: $prefs.compression) { $0.label }
            Text(prefs.compression.detail).font(Theme.font(12)).foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder private var tools: some View {
        FFmpegRow()
        FinderServiceRow()
        SetupRow(symbol: "terminal", title: "Command line",
                 detail: "Use every action from Terminal with the morph command.") {
            Button("Copy Setup") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sudo ln -sf '\(AppLocation.cli.path)' /usr/local/bin/morph", forType: .string)
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.tangerine : .secondary)
                Text(title).font(Theme.font(13))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { prefs.outputFolder = url }
    }
}
