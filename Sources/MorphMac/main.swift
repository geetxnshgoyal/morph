import AppKit
import SwiftUI
import MorphCore

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var wheel: WheelPanel?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let dragShortcut = DragShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        // Reopens folders granted before a relaunch, so Undo can still trash results saved there.
        FolderAccess.restore()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Morph")
        button.target = self
        button.action = #selector(togglePopover)

        // Files dropped straight onto the menu bar icon open the wheel.
        let drop = DropView(frame: button.bounds) { [weak self] urls in self?.showWheel(for: urls) }
        drop.autoresizingMask = [.width, .height]
        button.addSubview(drop)

        // Finder → right-click → Services → "Open in Morph" (declared as NSServices in Info.plist).
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ShelfView(
            onFiles: { [weak self] urls in
                self?.popover.performClose(nil)
                self?.showWheel(for: urls)
            },
            onSettings: { [weak self] in self?.popover.performClose(nil); self?.showSettings() },
            onWelcome: { [weak self] in self?.popover.performClose(nil); self?.showWelcome() }
        ).followsPalette())

        // Tap a wheel's keys while dragging files anywhere: that wheel appears under the cursor to drop on.
        dragShortcut.onTrigger = { [weak self] urls, group in self?.showWheel(for: urls, dropMode: true, group: group) }
        dragShortcut.onSwitch = { [weak self] group in
            if let wheel = self?.wheel, wheel.model.dropMode { wheel.model.select(group) }
        }
        // Esc mid-drag: the wheel isn't key in drop mode, so it can't hear the key itself.
        dragShortcut.onCancel = { [weak self] in
            if let wheel = self?.wheel, wheel.model.dropMode, case .choosing = wheel.model.phase { wheel.close() }
        }
        dragShortcut.onDragEnded = { [weak self] in
            if let wheel = self?.wheel, wheel.model.dropMode, case .choosing = wheel.model.phase { wheel.close() }
        }
        dragShortcut.start()

        // Login item approval can change in System Settings while we run.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                LoginItem.shared.refresh()
                ToolStatus.shared.refresh()
            }
        }

        if !Preferences.shared.hasSeenWelcome { showWelcome() }
        #if DEBUG
        // `open -a Morph --args -settings output`, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-settings") {
            let tab = args.dropFirst(i + 1).first.flatMap { SettingsView.Tab(rawValue: $0.capitalized) } ?? .general
            settingsWindow = makeWindow(title: "Morph Settings", content: SettingsView(onWelcome: { [weak self] in self?.showWelcome() }, tab: tab))
            showSettings()
        }
        #endif
    }

    /// "Open With → Morph", dragging onto the Dock/app icon, and `open -a Morph file`.
    func application(_ application: NSApplication, open urls: [URL]) {
        showWheel(for: urls)
    }

    /// Opening Morph again (Finder, Spotlight, Launchpad) while it runs: point at the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Preferences.shared.hasSeenWelcome { showWelcome() }
        else if !flag { showPopover() }
        return false
    }

    // MARK: Windows

    @objc func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(onTry: { [weak self] urls in self?.showWheel(for: urls) },
                                   onFinish: { [weak self] in self?.finishWelcome() })
            welcomeWindow = makeWindow(title: "Welcome to Morph", content: view)
        }
        present(welcomeWindow!)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Morph Settings", content: SettingsView { [weak self] in self?.showWelcome() })
        }
        present(settingsWindow!)
    }

    private func finishWelcome() {
        Preferences.shared.hasSeenWelcome = true
        welcomeWindow?.close()
        // Show where Morph lives from now on.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.showPopover() }
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Windows get a Dock icon and menu bar while open; the app goes back to menu-bar-only after.
    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === welcomeWindow {
            Preferences.shared.hasSeenWelcome = true
            welcomeWindow = nil
        }
        if window === settingsWindow { settingsWindow = nil }
        DispatchQueue.main.async {
            if self.welcomeWindow == nil, self.settingsWindow == nil { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func installMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Morph", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(withTitle: "Welcome Guide", action: #selector(showWelcome), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Morph", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Morph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for menu in [app, edit, window] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    @objc func openFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        showWheel(for: urls)
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `dropMode`: summoned mid-drag, so the wheel waits for a drop instead of a click and leaves focus alone.
    func showWheel(for urls: [URL], dropMode: Bool = false, group: Action.Group? = nil) {
        let files = urls.map(\.standardizedFileURL)
        guard !files.isEmpty else { return }
        wheel?.close()
        var group = group
        #if DEBUG
        // `open -a Morph file --args -group tool -hover tool.compress -run tool.compress`, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        if let name = arg("-group") { group = Action.Group(rawValue: name) }
        #endif
        wheel = WheelPanel(files: files, dropMode: dropMode, group: group)
        wheel?.present(at: NSEvent.mouseLocation)
        #if DEBUG
        if let model = wheel?.model {
            if let id = arg("-hover") { model.hovered = id }
            if let id = arg("-run"), let action = model.actions.first(where: { $0.id == id }) { model.run(action) }
        }
        #endif
    }
}

// MARK: - Drop target for the status item

final class DropView: NSView {
    private let onDrop: ([URL]) -> Void

    init(frame: NSRect, onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Let clicks fall through to the status button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        DispatchQueue.main.async { self.onDrop(urls) }
        return true
    }
}

// MARK: - Menu bar popover

struct ShelfView: View {
    let onFiles: ([URL]) -> Void
    let onSettings: () -> Void
    let onWelcome: () -> Void

    @ObservedObject private var tools = ToolStatus.shared
    @State private var targeted = false
    @State private var recent: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Morph").font(Theme.font(17, .bold))
                Spacer()
                Menu {
                    Button("Settings…", action: onSettings)
                    Button("Welcome Guide", action: onWelcome)
                    Divider()
                    Button("Quit Morph") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }

            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundStyle(targeted ? Theme.brandText : .secondary.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(targeted ? Theme.tint : Theme.surface))
                .frame(height: 124)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.brandText)
                        Text("Drop files here").font(Theme.font(15, .semibold))
                        Button("Choose Files…", action: choose).buttonStyle(SoftButtonStyle())
                    }
                }
                .scaleEffect(targeted ? 1.02 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
                .dropDestination(for: URL.self) { urls, _ in
                    onFiles(urls); return true
                } isTargeted: { targeted = $0 }

            if recent.isEmpty {
                Label("Tip: right-click files in Finder → Services → Open in Morph", systemImage: "lightbulb.fill")
                    .font(Theme.font(11)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent").font(Theme.font(11, .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                    ForEach(recent) { entry in row(entry) }
                }
            }

            if !tools.hasFFmpeg, !Sandbox.isActive {
                Button(action: onSettings) {
                    Label("Unlock MP3, WebM and more", systemImage: "sparkles")
                        .font(Theme.font(11, .medium)).foregroundStyle(Theme.brandText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 310)
        .background(Theme.canvas)
        .tint(Theme.brand)
        .onAppear {
            recent = Array(History.shared.entries.suffix(5).reversed())
            tools.refresh()
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            SymbolBubble(symbol: entry.undone ? "arrow.uturn.backward" : entry.outputs.isEmpty ? "xmark" : "checkmark", size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title).font(Theme.font(13, .medium)).strikethrough(entry.undone)
                Text("\(entry.inputs.count) in → \(entry.outputs.count) out").font(Theme.font(10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !entry.outputs.isEmpty, !entry.undone {
                Button { NSWorkspace.shared.activateFileViewerSelecting(entry.outputs) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless).help("Show in Finder")
                Button {
                    _ = try? History.shared.undo(entry.id)
                    recent = Array(History.shared.entries.suffix(5).reversed())
                } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless).help("Move outputs to Trash")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Theme.surface))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { onFiles(panel.urls) }
    }
}

// MARK: - Entry point

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Files passed on the command line (`MorphMac a.png b.png`) open the wheel straight away.
    let launchFiles = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
    if !launchFiles.isEmpty {
        DispatchQueue.main.async { delegate.showWheel(for: launchFiles) }
    }
    app.run()
}
