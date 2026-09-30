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
    @Published var dragKey: DragKey { didSet { defaults.set(dragKey.rawValue, forKey: "dragKey") } }
    /// nil saves results next to the original.
    @Published var outputFolder: URL? { didSet { defaults.set(outputFolder?.path, forKey: "outputFolder") } }

    private init() {
        defaults.register(defaults: ["playSounds": true])
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
        playSounds = defaults.bool(forKey: "playSounds")
        revealWhenDone = defaults.bool(forKey: "revealWhenDone")
        compression = defaults.string(forKey: "compression").flatMap(CompressionLevel.init) ?? .balanced
        outputFolder = defaults.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) }
        dragKey = defaults.string(forKey: "dragKey").flatMap(DragKey.init) ?? .shift
    }

    /// Options for a run from the wheel.
    var options: Options {
        var options = Options()
        options.compression = compression
        if let outputFolder {
            try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            options.outputDirectory = outputFolder
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
        case .light: "Barely noticeable, modest savings."
        case .balanced: "Good quality, much smaller files."
        case .strong: "Smallest files, visible softening."
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
