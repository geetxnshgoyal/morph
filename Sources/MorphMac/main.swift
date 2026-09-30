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
        ))

        // Hold the chosen key while dragging files anywhere: the wheel appears under the cursor to drop on.
        dragShortcut.onTrigger = { [weak self] urls in self?.showWheel(for: urls, dropMode: true) }
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
    func showWheel(for urls: [URL], dropMode: Bool = false) {
        let files = urls.map(\.standardizedFileURL)
        guard !files.isEmpty else { return }
        wheel?.close()
        wheel = WheelPanel(files: files, dropMode: dropMode)
        wheel?.present(at: NSEvent.mouseLocation)
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

// MARK: - Wheel window

@MainActor
final class WheelPanel: NSPanel {
    static let size: CGFloat = 420
    private var monitor: Any?
    let model: WheelModel

    init(files: [URL], dropMode: Bool = false) {
        model = WheelModel(files: files, dropMode: dropMode)
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        model.dismiss = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: WheelView(model: model))
        host.frame = contentRect(forFrameRect: frame)
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    func present(at point: NSPoint) {
        // Keep the whole wheel on the screen the cursor is on.
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - Self.size)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - Self.size)
        }
        setFrameOrigin(origin)
        alphaValue = 0
        if model.dropMode {
            // Activating now would cancel the drag in progress.
            orderFrontRegardless()
        } else {
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        super.close()
    }
}

// MARK: - Wheel model

@MainActor
final class WheelModel: ObservableObject {
    enum Phase { case choosing, running(Action, done: Int, total: Int), finished(Action, RunResult) }

    let files: [URL]
    let actions: [Action]
    let dropMode: Bool
    @Published var group: Action.Group
    @Published var phase: Phase = .choosing
    @Published var hovered: String?
    var dismiss: () -> Void = {}

    init(files: [URL], dropMode: Bool = false) {
        self.files = files
        self.dropMode = dropMode
        actions = Library.actions(for: files)
        group = actions.contains { $0.group == .convert } ? .convert : .tool
    }

    var groups: [Action.Group] {
        [.convert, .tool, .recipe].filter { g in actions.contains { $0.group == g } }
    }

    var visible: [Action] { actions.filter { $0.group == group } }

    var summary: String {
        let kinds = Set(files.map { FileKind(url: $0) })
        let noun = kinds.count == 1 ? kinds.first!.rawValue : "file"
        return files.count == 1 ? files[0].lastPathComponent : "\(files.count) \(noun)s"
    }

    func run(_ action: Action) {
        phase = .running(action, done: 0, total: files.count)
        let files = files
        let prefs = Preferences.shared
        Task {
            let result = await Runner.run(action, inputs: files, options: prefs.options) { done, total in
                Task { @MainActor in
                    if case .running = self.phase { self.phase = .running(action, done: done, total: total) }
                }
            }
            phase = .finished(action, result)
            if result.failures.isEmpty {
                if prefs.playSounds { NSSound(named: "Glass")?.play() }
                if prefs.revealWhenDone, !result.outputs.isEmpty { reveal(result); return }
                try? await Task.sleep(for: .seconds(2.5))
                if case .finished = phase { dismiss() }
            } else if prefs.playSounds {
                NSSound.beep()
            }
        }
    }

    func reveal(_ result: RunResult) {
        NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
        dismiss()
    }
}

// MARK: - Wheel view

struct WheelView: View {
    @ObservedObject var model: WheelModel

    private let radius: CGFloat = 150
    private let hub: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Theme.tangerine.opacity(0.25), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                .frame(width: (radius + 48) * 2, height: (radius + 48) * 2)

            switch model.phase {
            case .choosing: ring
            case .running, .finished: EmptyView()
            }

            hubView
        }
        .frame(width: WheelPanel.size, height: WheelPanel.size)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.group)
    }

    private var ring: some View {
        let items = model.visible
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, action in
                let angle = Angle.degrees(Double(index) / Double(max(items.count, 1)) * 360 - 90)
                WheelButton(action: action, hovered: model.hovered == action.id) { model.run(action) }
                    .onHover { setHovered(action, $0) }
                    // Dropping the dragged files on a bubble runs it.
                    .onDrop(of: [.fileURL], isTargeted: Binding(get: { model.hovered == action.id }, set: { setHovered(action, $0) })) { _ in
                        model.run(action)
                        return true
                    }
                    .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
            }
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .id(model.group)
    }

    @ViewBuilder private var hubView: some View {
        ZStack {
            Circle().fill(Theme.surface.opacity(0.92)).frame(width: hub, height: hub)
                .shadow(color: Theme.coral.opacity(0.15), radius: 12)
            switch model.phase {
            case .choosing:
                VStack(spacing: 6) {
                    Text(hoverTitle ?? (model.dropMode && !model.actions.isEmpty ? "Drop on an action" : model.summary))
                        .font(Theme.font(14, .semibold))
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(width: hub - 28)
                    if model.actions.isEmpty {
                        Text("Nothing fits these files").font(.caption).foregroundStyle(.secondary)
                    } else if model.groups.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(model.groups, id: \.self) { g in
                                Button { model.group = g } label: {
                                    Text(g.label).font(Theme.font(10, .semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Capsule().fill(g == model.group ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.tint)))
                                        .foregroundStyle(g == model.group ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                                // Spring-loaded: hovering a drag over a group switches to it.
                                .onDrop(of: [.fileURL], isTargeted: Binding(get: { false }, set: { if $0 { model.group = g } })) { _ in false }
                            }
                        }
                    }
                }
            case let .running(action, done, total):
                VStack(spacing: 8) {
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0).progressViewStyle(.circular)
                        .tint(Theme.tangerine)
                    Text(action.title).font(Theme.font(14, .semibold))
                    if total > 1 { Text("\(done) of \(total)").font(.caption).foregroundStyle(.secondary) }
                }
            case let .finished(_, result):
                VStack(spacing: 6) {
                    Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(result.failures.isEmpty ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.coral))
                    Text(result.failures.isEmpty ? "Done" : "\(result.failures.count) failed")
                        .font(Theme.font(14, .semibold))
                    if let first = result.failures.first {
                        Text(first).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            .multilineTextAlignment(.center).frame(width: hub - 30)
                    }
                    if !result.outputs.isEmpty {
                        Button("Show in Finder") { model.reveal(result) }.buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
    }

    private func setHovered(_ action: Action, _ on: Bool) {
        model.hovered = on ? action.id : (model.hovered == action.id ? nil : model.hovered)
    }

    private var hoverTitle: String? {
        model.hovered.flatMap { id in model.actions.first { $0.id == id } }.map { action in
            action.group == .convert ? "Convert to \(action.title)" : action.title
        }
    }
}

struct WheelButton: View {
    let action: Action
    let hovered: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                Image(systemName: action.symbol).font(.system(size: 15))
                Text(action.title).font(Theme.font(9, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 58, height: 58)
            .background(Circle().fill(hovered ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface)))
            .shadow(color: hovered ? Theme.coral.opacity(0.4) : .black.opacity(0.08), radius: hovered ? 10 : 4, y: 2)
            .foregroundStyle(hovered ? .white : .primary)
            .scaleEffect(hovered ? 1.14 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hovered)
        }
        .buttonStyle(.plain)
        .help(action.title)
    }
}

extension Action.Group {
    var label: String {
        switch self {
        case .convert: "Convert"
        case .tool: "Tools"
        case .recipe: "Recipes"
        }
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
                .foregroundStyle(targeted ? Theme.tangerine : .secondary.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(targeted ? Theme.tint : Theme.surface))
                .frame(height: 124)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.accent)
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

            if !tools.hasFFmpeg {
                Button(action: onSettings) {
                    Label("Unlock MP3, WebM and more", systemImage: "sparkles")
                        .font(Theme.font(11, .medium)).foregroundStyle(Theme.tangerine)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 310)
        .background(Theme.canvas)
        .tint(Theme.tangerine)
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
