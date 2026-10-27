import AppKit
import MorphCore

/// The Actions wheel: everyday things to do with the files themselves (send, copy, move, open a Terminal
/// there) rather than new files to make. They run at once on the main thread and stay out of history, since
/// undoing a move would trash the originals.
@MainActor
enum FileActions {
    static func actions(for files: [URL]) -> [Action] {
        guard !files.isEmpty else { return [] }
        var list: [Action] = []
        func add(_ id: String, _ title: String, _ symbol: String, _ body: @escaping @MainActor ([URL]) throws -> Void) {
            list.append(Action(id: "file.\(id)", title: title, symbol: symbol, group: .file, kinds: Set(FileKind.allCases),
                               combinesInputs: true, minimumInputs: 1, targetExtension: nil, needsFFmpeg: false) { urls, _ in
                try await MainActor.run { try body(urls) }
                return []
            })
        }

        let services: [(NSSharingService.Name, String, String, String)] = [
            (.sendViaAirDrop, "airdrop", "AirDrop", "dot.radiowaves.left.and.right"),
            (.composeMessage, "messages", "Messages", "message"),
            (.composeEmail, "mail", "Mail", "envelope"),
        ]
        for (name, id, title, symbol) in services where NSSharingService(named: name)?.canPerform(withItems: files) == true {
            add(id, title, symbol) { urls in
                NSApp.activate(ignoringOtherApps: true)
                NSSharingService(named: name)?.perform(withItems: urls)
            }
        }
        add("copy", "Copy", "doc.on.doc") { urls in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            confirm()
        }
        add("copy-path", files.count == 1 ? "Copy Path" : "Copy Paths", "link") { urls in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            confirm()
        }
        add("move", "Move To…", "folder") { try transfer($0, move: true) }
        add("copy-to", "Copy To…", "plus.rectangle.on.folder") { try transfer($0, move: false) }
        add("terminal", "Terminal", "terminal") { openTerminal(at: $0) }
        return list
    }

    /// Shows a failed file action, since the wheel has already gone by the time it fails.
    static func report(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't finish that"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private static func confirm() {
        if Preferences.shared.playSounds { NSSound(named: "Pop")?.play() }
    }

    /// Moves or copies into a folder the user picks, renaming instead of overwriting, then shows the results.
    private static func transfer(_ urls: [URL], move: Bool) throws {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = move ? "Move Here" : "Copy Here"
        panel.message = "\(move ? "Move" : "Copy") \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items") to:"
        panel.directoryURL = urls.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        // Moving takes the file out of its folder, which the sandbox only allows once that folder is granted.
        if move {
            for parent in Set(urls.map { $0.deletingLastPathComponent() }) where FolderAccess.writable(parent)?.path != parent.path {
                throw MorphError("Morph needs permission for “\(parent.lastPathComponent)” to move files out of it.")
            }
        }
        let fm = FileManager.default
        var results: [URL] = []
        for url in urls {
            let target = Output.unique(in: folder, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
            if move { try fm.moveItem(at: url, to: target) } else { try fm.copyItem(at: url, to: target) }
            results.append(target)
        }
        NSWorkspace.shared.activateFileViewerSelecting(results)
    }

    /// Opens Terminal in the folder itself, or in the folder that holds the file.
    private static func openTerminal(at urls: [URL]) {
        guard let first = urls.first,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? first : first.deletingLastPathComponent()
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
