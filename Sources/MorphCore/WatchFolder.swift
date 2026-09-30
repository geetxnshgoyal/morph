import Foundation

/// Runs an action or recipe on every new file that lands in a folder. Outputs go to a
/// "Morphed" subfolder so they never re-trigger the watcher.
public final class WatchFolder: @unchecked Sendable {
    public struct Rule: Codable, Hashable, Sendable, Identifiable {
        public var folder: URL
        public var actionID: String
        public var id: String { folder.path + "→" + actionID }
        public init(folder: URL, actionID: String) { self.folder = folder; self.actionID = actionID }
    }

    public let rule: Rule
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private let queue = DispatchQueue(label: "morph.watch")
    private var pending: DispatchWorkItem?
    public var onResult: (@Sendable (URL, RunResult) -> Void)?

    public init(_ rule: Rule) { self.rule = rule }

    var outputFolder: URL { rule.folder.appendingPathComponent("Morphed") }

    public func start() throws {
        let fd = open(rule.folder.path, O_EVTONLY)
        guard fd >= 0 else { throw MorphError("Can't watch \(rule.folder.path)") }
        known = Set(listing().map(\.path))
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    public func stop() { source?.cancel(); source = nil }

    private func listing() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: rule.folder, includingPropertiesForKeys: [.fileSizeKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.lastPathComponent != "Morphed" }
    }

    private func scheduleScan() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pending = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func scan() {
        let fresh = listing().filter { !known.contains($0.path) }
        guard !fresh.isEmpty, let action = Library.action(rule.actionID) else { return }
        // Wait until writers (screenshots, downloads) finish: size must be stable across two reads.
        let sizes = fresh.map { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        Thread.sleep(forTimeInterval: 1)
        let stable = zip(fresh, sizes).filter { url, size in
            ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2) == size && !url.lastPathComponent.hasSuffix(".download")
        }.map(\.0).filter { action.accepts([$0]) }
        if stable.count < fresh.count { scheduleScan() }
        for url in stable { known.insert(url.path) }
        guard !stable.isEmpty else { return }
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        var options = Options()
        options.outputDirectory = outputFolder
        let callback = onResult
        for url in stable {
            Task {
                let result = await Runner.run(action, inputs: [url], options: options)
                callback?(url, result)
            }
        }
    }
}
