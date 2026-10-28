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
                    .toggleStyle(.switch).labelsHidden().tint(Theme.brand)
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
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                SymbolBubble(symbol: "hand.draw.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag shortcuts").font(Theme.font(14, .semibold))
                    Text("While dragging files anywhere, tap a wheel's keys to open it. Tap another wheel's keys to switch, or Esc to close.")
                        .font(Theme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Preferences.wheels, id: \.self) { group in
                HStack {
                    Text(group.label).font(Theme.font(13, .medium))
                    Spacer()
                    KeyPicker(keys: Binding(get: { prefs.dragKeys(for: group) }, set: { prefs.setDragKeys($0, for: group) }))
                }
                .padding(.leading, 50)
            }
        }
        .card(padding: 14)
    }
}

/// A tinted pill that opens a menu of keys: single keys, modifier combinations, or off.
struct KeyPicker: View {
    @Binding var keys: DragKeys

    var body: some View {
        Menu {
            ForEach(DragKeys.singles, id: \.self, content: option)
            Menu("Combinations") {
                ForEach(DragKeys.combinations, id: \.self, content: option)
            }
            Divider()
            option(.off)
        } label: {
            Text(keys.label).font(Theme.font(12, .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(Theme.tint))
    }

    private func option(_ choice: DragKeys) -> some View {
        Button { keys = choice } label: {
            if choice == keys { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) }
        }
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
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.brandText)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear { tools.refresh() }
    }
}

/// App Store version only: one permission so results can go next to originals instead of Downloads.
struct SaveNextToOriginalsRow: View {
    @State private var allowed = FolderAccess.hasGrants

    var body: some View {
        SetupRow(symbol: allowed ? "checkmark.seal.fill" : "folder.badge.gearshape",
                 title: allowed ? "Saving next to your files" : "Save next to your files",
                 detail: allowed ? "Results land beside the originals."
                                 : "Allow Morph once and results land beside the originals. Until then they go to Downloads.") {
            if !allowed {
                Button("Allow…") { allowed = FolderAccess.allowNextToOriginals() }.buttonStyle(SoftButtonStyle())
            }
        }
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
    @State private var allowedNextToOriginals = FolderAccess.hasGrants

    enum Tab: String, CaseIterable { case general = "General", output = "Output", tools = "Tools" }

    var body: some View {
        PaletteScope {
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
            .tint(Theme.brand)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tab)
        }
    }

    @ViewBuilder private var general: some View {
        LoginItemRow()
        DragShortcutRow()
        if AppLocation.isBundled, !AppLocation.isInstalled, !Sandbox.isActive { MoveToApplicationsRow() }
        SetupRow(symbol: "paintpalette.fill", title: "Color",
                 detail: "\(Palette.current.name) for highlights and buttons. The app icon stays Teal Ink.") {
            PalettePicker(size: 20)
        }
        SetupRow(symbol: "speaker.wave.2.fill", title: "Sounds & haptics",
                 detail: "A soft tick as you move around the wheel, and a chime when a job finishes.") {
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
            if Sandbox.isActive, prefs.outputFolder == nil, !allowedNextToOriginals {
                // The App Store version can't write next to a file until it's allowed to, once.
                HStack(spacing: 10) {
                    Text("Until you allow it, results go to Downloads.").font(Theme.font(12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow…") { allowedNextToOriginals = FolderAccess.allowNextToOriginals() }
                        .buttonStyle(SoftButtonStyle())
                }
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

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Size limit").font(Theme.font(14, .semibold))
                Spacer()
                SizeLimitMenu(limit: $prefs.sizeLimit)
            }
            Text(SizeLimit.detail(prefs.sizeLimit)).font(Theme.font(12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photo size").font(Theme.font(14, .semibold))
                Spacer()
                PhotoSizeMenu(size: $prefs.photoSize)
            }
            Text(prefs.photoSize.map { "Resize makes photos exactly \($0.label) as a JPG, cropped to fill, and under your size limit if one is set. For passport, visa and exam forms." }
                 ?? "Pick the exact size a form asks for, like 600 × 600, and Resize makes it.")
                .font(Theme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if prefs.photoSize != nil {
                TextField("Name to print below the photo (optional)", text: $prefs.photoCaption)
                    .textFieldStyle(.roundedBorder).font(Theme.font(12))
                Text("Some exam forms want the name and the date the photo was taken under it. Leave empty for none.")
                    .font(Theme.font(11)).foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    @ViewBuilder private var tools: some View {
        // The App Store build can't run Homebrew's ffmpeg and ships without the command-line tool.
        if !Sandbox.isActive { FFmpegRow() }
        FinderServiceRow()
        if !Sandbox.isActive {
            SetupRow(symbol: "terminal", title: "Command line",
                     detail: "Use every action from Terminal with the morph command.") {
                Button("Copy Setup") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("sudo ln -sf '\(AppLocation.cli.path)' /usr/local/bin/morph", forType: .string)
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.brandText : .secondary)
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
