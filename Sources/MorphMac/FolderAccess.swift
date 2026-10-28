import AppKit
import MorphCore

/// Folders the user has let Morph write into. Outside the sandbox every folder is open, so this only matters in
/// the Mac App Store build: there a dropped file can be read, but its folder can't be written to until the user
/// picks that folder (or one it's in, like their home folder) once in an open panel. The grant is kept as a
/// security-scoped bookmark. Until then results go to Downloads, which the sandbox allows, so the wheel never
/// stops to ask.
@MainActor
enum FolderAccess {
    private static let key = "folderBookmarks"
    /// Granted folders, with access started, loaded once.
    private static var granted: [URL] = []
    private static var loaded = false

    /// True while the permission panel is up, so the wheel doesn't take a click in it as a click elsewhere.
    private(set) static var isAsking = false

    /// Starts access to every granted folder, so results saved there before a relaunch can still be undone.
    static func restore() {
        guard Sandbox.isActive, !loaded else { return }
        loaded = true
        var fresh: [Data] = []
        for data in UserDefaults.standard.array(forKey: key) as? [Data] ?? [] {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            else { continue }
            _ = url.startAccessingSecurityScopedResource()
            granted.append(url.standardizedFileURL)
            // A moved or renamed folder gets a new bookmark; ones that no longer resolve are dropped.
            fresh.append(stale ? (try? url.bookmarkData(options: .withSecurityScope)) ?? data : data)
        }
        UserDefaults.standard.set(fresh, forKey: key)
    }

    /// Whether Morph can save into `folder` right now, without asking.
    static func canSave(in folder: URL) -> Bool {
        guard Sandbox.isActive else { return true }
        restore()
        let folder = folder.standardizedFileURL
        return granted.contains(where: { contains($0, folder) }) || canWrite(folder)
    }

    /// Whether the user has allowed saving next to originals anywhere yet.
    static var hasGrants: Bool { restore(); return !granted.isEmpty }

    /// The real Downloads folder, writable in the sandbox through its Downloads entitlement.
    static var downloads: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Downloads")
    }

    /// Asks once, from Settings, to save next to originals: picking the home folder covers every folder in it.
    @discardableResult
    static func allowNextToOriginals() -> Bool {
        let home = downloads.deletingLastPathComponent()
        guard let chosen = ask(for: home, message: "Choose your home folder (or any folder) so Morph can save results next to the files in it. You only do this once.") else { return false }
        remember(chosen)
        return true
    }

    /// A folder Morph may write to for files in `folder`: the folder itself or one it lives in, asking once if
    /// needed. nil if the user says no. Only for moments the user started in a window, like Move To.
    static func writable(_ folder: URL) -> URL? {
        guard Sandbox.isActive else { return folder }
        let folder = folder.standardizedFileURL
        if canSave(in: folder) { return folder }
        guard let chosen = ask(for: folder) else { return nil }
        remember(chosen)
        // Picking a different folder in the panel means "save there instead".
        return contains(chosen, folder) ? folder : chosen
    }

    /// Keeps a folder the user picked in a panel usable after relaunch.
    static func remember(_ folder: URL) {
        guard Sandbox.isActive else { return }
        restore()
        let folder = folder.standardizedFileURL
        guard !granted.contains(where: { contains($0, folder) }),
              let data = try? folder.bookmarkData(options: .withSecurityScope) else { return }
        _ = folder.startAccessingSecurityScopedResource()
        granted.append(folder)
        UserDefaults.standard.set((UserDefaults.standard.array(forKey: key) as? [Data] ?? []) + [data], forKey: key)
    }

    /// Starts access to a bookmarked folder, for a folder setting saved before relaunch.
    static func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Already writable without asking: Morph's own container, or a folder opened earlier this session.
    private static func canWrite(_ folder: URL) -> Bool {
        let probe = folder.appendingPathComponent(".morph-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: probe.path, contents: nil) else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        let p = parent.pathComponents, c = child.pathComponents
        return c.count >= p.count && Array(c.prefix(p.count)) == p
    }

    private static func ask(for folder: URL, message: String? = nil) -> URL? {
        isAsking = true
        defer { isAsking = false }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = message ?? "Allow Morph to save in “\(folder.lastPathComponent)” and the folders inside it? You'll only be asked once."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
