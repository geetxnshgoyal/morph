import Foundation

public enum ArchiveOps {
    /// Zips files and folders using the system's built-in coordinator (works on iOS too).
    public static func zip(_ urls: [URL], options: Options) throws -> URL {
        guard let first = urls.first else { throw MorphError("Nothing to zip") }
        let fm = FileManager.default
        let isSingleFolder = urls.count == 1 && FileKind(url: first) == .folder
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        // Always zip a staged copy without symbolic links: the system zipper fails on any link, and following one
        // would pull files from outside the folder into the archive. On APFS the copies are clones, so this is cheap.
        let tmp = try Output.temporaryDirectory()
        defer { try? fm.removeItem(at: tmp) }
        let staging = tmp.appendingPathComponent(base)
        if isSingleFolder {
            try copySkippingLinks(first, to: staging)
        } else {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for url in urls where !isLink(url) {
                try copySkippingLinks(url, to: Output.unique(in: staging, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension))
            }
        }

        let out = Output.unique(in: options.outputDirectory ?? first.deletingLastPathComponent(), base: base, ext: "zip")
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinatorError) { zipped in
            do { try fm.copyItem(at: zipped, to: out) } catch { copyError = error }
        }
        if let error = coordinatorError ?? copyError { throw error }
        return out
    }

    static func isLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Copies a file or folder tree, leaving out symbolic links at any depth.
    static func copySkippingLinks(_ source: URL, to dest: URL) throws {
        let fm = FileManager.default
        guard (try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return try fm.copyItem(at: source, to: dest) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) where !isLink(child) {
            try copySkippingLinks(child, to: dest.appendingPathComponent(child.lastPathComponent))
        }
    }

    #if os(macOS)
    public static func tarGz(_ urls: [URL], options: Options) async throws -> URL {
        guard let first = urls.first else { throw MorphError("Nothing to archive") }
        let parent = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let out = Output.unique(in: options.outputDirectory ?? parent, base: base, ext: "tar.gz")
        try await ExternalTool.run(URL(fileURLWithPath: "/usr/bin/tar"),
                                   // "--" so a folder named like an option ("--version") is archived, not obeyed.
                                   ["-czf", out.path, "-C", parent.path, "--"] + urls.map(\.lastPathComponent))
        return out
    }

    /// bsdtar handles zip, tar, gz, bz2, xz, 7z and rar.
    public static func extract(_ url: URL, options: Options) async throws -> URL {
        var base = url.deletingPathExtension()
        if base.pathExtension == "tar" { base = base.deletingPathExtension() }
        let folder = Output.unique(in: options.outputDirectory ?? url.deletingLastPathComponent(), base: base.lastPathComponent, ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try await ExternalTool.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", url.path, "-C", folder.path])
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }
    #endif
}
