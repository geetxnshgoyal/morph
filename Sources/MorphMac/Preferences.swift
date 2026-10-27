import AppKit
import ServiceManagement
import SwiftUI
import MorphCore

// MARK: - Preferences

/// User settings, persisted in UserDefaults and shared by the popover, Settings, Welcome and the wheel.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }
    @Published var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    @Published var revealWhenDone: Bool { didSet { defaults.set(revealWhenDone, forKey: "revealWhenDone") } }
    @Published var compression: CompressionLevel { didSet { defaults.set(compression.rawValue, forKey: "compression") } }
    /// Bytes Compress must fit under, for upload forms; 0 is no limit.
    @Published var sizeLimit: Int { didSet { defaults.set(sizeLimit, forKey: SizeLimit.key) } }
    @Published var convertKeys: DragKeys { didSet { defaults.set(convertKeys.rawValue, forKey: "convertKeys") } }
    @Published var toolsKeys: DragKeys { didSet { defaults.set(toolsKeys.rawValue, forKey: "toolsKeys") } }
    @Published var recipesKeys: DragKeys { didSet { defaults.set(recipesKeys.rawValue, forKey: "recipesKeys") } }
    @Published var actionsKeys: DragKeys { didSet { defaults.set(actionsKeys.rawValue, forKey: "actionsKeys") } }
    /// nil saves results next to the original.
    @Published var outputFolder: URL? {
        didSet {
            defaults.set(outputFolder?.path, forKey: "outputFolder")
            // The sandbox forgets panel choices on quit; a bookmark keeps the folder writable.
            defaults.set(outputFolder.flatMap { try? $0.bookmarkData(options: .withSecurityScope) }, forKey: "outputFolderBookmark")
        }
    }

    private init() {
        defaults.register(defaults: ["playSounds": true])
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
        playSounds = defaults.bool(forKey: "playSounds")
        revealWhenDone = defaults.bool(forKey: "revealWhenDone")
        compression = defaults.string(forKey: "compression").flatMap(CompressionLevel.init) ?? .balanced
        sizeLimit = defaults.integer(forKey: SizeLimit.key)
        outputFolder = defaults.data(forKey: "outputFolderBookmark").flatMap(FolderAccess.resolve)
            ?? defaults.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) }
        let convert = Self.storedKeys(defaults, "convertKeys", legacy: ["convertKey", "dragKey"]) ?? .shift
        let tools = Self.storedKeys(defaults, "toolsKeys", legacy: ["toolsKey"]) ?? .command
        let recipes = Self.storedKeys(defaults, "recipesKeys", legacy: ["recipesKey"]) ?? .control
        convertKeys = convert
        toolsKeys = tools
        recipesKeys = recipes
        // The newest wheel takes ⌥ unless an older one already uses it; then the first single key still free.
        actionsKeys = Self.storedKeys(defaults, "actionsKeys", legacy: [])
            ?? ([.option] + DragKeys.singles).first { ![convert, tools, recipes].contains($0) } ?? .off
    }

    /// A saved combination, or one carried over from when each wheel had a single named key.
    private static func storedKeys(_ defaults: UserDefaults, _ key: String, legacy: [String]) -> DragKeys? {
        if defaults.object(forKey: key) != nil { return DragKeys(rawValue: defaults.integer(forKey: key)) }
        let names: [String: DragKeys] = ["shift": .shift, "command": .command, "option": .option,
                                         "control": .control, "tab": .tab, "off": .off]
        return legacy.lazy.compactMap { defaults.string(forKey: $0).flatMap { names[$0] } }.first
    }

    static let wheels: [Action.Group] = [.convert, .tool, .recipe, .file]

    func dragKeys(for group: Action.Group) -> DragKeys {
        switch group {
        case .convert: convertKeys
        case .tool: toolsKeys
        case .recipe: recipesKeys
        case .file: actionsKeys
        }
    }

    /// The wheel whose keys are exactly `keys`. Holding extra keys matches nothing, so ⌘⇧ never opens ⌘'s wheel.
    func group(for keys: DragKeys) -> Action.Group? {
        guard !keys.isEmpty else { return nil }
        return Self.wheels.first { dragKeys(for: $0) == keys }
    }

    /// Assigns `keys` to `group`; a wheel that already used them takes this one's old keys, so wheels never clash.
    func setDragKeys(_ keys: DragKeys, for group: Action.Group) {
        let old = dragKeys(for: group)
        if !keys.isEmpty, let other = Self.wheels.first(where: { $0 != group && dragKeys(for: $0) == keys }) {
            assign(old, to: other)
        }
        assign(keys, to: group)
    }

    private func assign(_ keys: DragKeys, to group: Action.Group) {
        switch group {
        case .convert: convertKeys = keys
        case .tool: toolsKeys = keys
        case .recipe: recipesKeys = keys
        case .file: actionsKeys = keys
        }
    }

    /// Options for a run from the wheel on `files`, or nil if the user won't let Morph save where they go.
    func options(for files: [URL]) -> Options? {
        var options = Options()
        options.compression = compression
        if sizeLimit > 0 { options.targetBytes = sizeLimit }
        if let outputFolder {
            try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            options.outputDirectory = outputFolder
        } else if Sandbox.isActive {
            // Results go next to each original, so every folder the files come from needs a grant.
            for parent in Set(files.map { $0.deletingLastPathComponent().standardizedFileURL }) {
                guard let folder = FolderAccess.writable(parent) else { return nil }
                // Picked a different folder in the panel: save everything there.
                if folder.path != parent.path { options.outputDirectory = folder; break }
            }
        }
        return options
    }
}

extension CompressionLevel {
    var label: String {
        switch self {
        case .light: "Light"
        case .balanced: "Balanced"
        case .strong: "Strong"
        }
    }

    var detail: String {
        switch self {
        case .light: "Looks identical, smaller savings."
        case .balanced: "Looks the same side by side, much smaller."
        case .strong: "Smallest files; a close look may show softening."
        }
    }
}

// MARK: - Login item

/// Wraps SMAppService so every screen shows the same, current login item state.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var problem: String?

    /// Registered, even if macOS is still waiting for the user to approve it.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        problem = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = AppLocation.isInstalled
                ? error.localizedDescription
                : "Move Morph to your Applications folder first."
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

// MARK: - App location

enum AppLocation {
    static var bundle: URL { Bundle.main.bundleURL.resolvingSymlinksInPath() }

    /// Running from /Applications or ~/Applications (login items and Open With are only reliable from there).
    static var isInstalled: Bool {
        let path = bundle.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    /// False under `swift run`, where there is no .app to move.
    static var isBundled: Bool { bundle.pathExtension == "app" }

    /// The CLI shipped inside the app, for linking onto PATH.
    static var cli: URL { bundle.appendingPathComponent("Contents/Resources/morph") }

    /// Copies the app into /Applications (trashing any older copy) and relaunches from there.
    @MainActor static func moveToApplications() throws {
        let fm = FileManager.default
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
        try fm.copyItem(at: bundle, to: dest)
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; open \"$0\"", dest.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Optional tools

/// Live ffmpeg status, so "Extra formats unlocked" shows up everywhere the moment `brew install ffmpeg`
/// finishes, without a relaunch.
@MainActor
final class ToolStatus: ObservableObject {
    static let shared = ToolStatus()

    @Published private(set) var hasFFmpeg = ExternalTool.ffmpeg != nil
    private var timer: Timer?

    private init() { schedule() }

    func refresh() {
        let found = ExternalTool.ffmpeg != nil
        if found != hasFFmpeg {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { hasFFmpeg = found }
        }
        schedule()
    }

    /// Checks every few seconds while ffmpeg is missing (a Homebrew install takes a while); idle once found.
    private func schedule() {
        if hasFFmpeg {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated { ToolStatus.shared.refresh() }
            }
        }
    }
}
