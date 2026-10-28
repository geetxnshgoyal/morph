import Foundation

public enum ArchiveOps {
    /// Zips files and folders using the system's built-in coordinator (works on iOS too).
    public static func zip(_ urls: [URL], options: Options) throws -> URL {
        guard let first = urls.first else { throw MorphError("Nothing to zip") }
        let fm = FileManager.default
        let isSingleFolder = urls.count == 1 && FileKind(url: first) == .folder
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        var staging = first
        var cleanup: URL?
        if !isSingleFolder {
            let tmp = try Output.temporaryDirectory()
            staging = tmp.appendingPathComponent(base)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for url in urls {
                let dest = Output.unique(in: staging, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
                try fm.copyItem(at: url, to: dest)
            }
            cleanup = tmp
        }
        defer { if let cleanup { try? fm.removeItem(at: cleanup) } }

        let out = Output.unique(in: options.outputDirectory ?? first.deletingLastPathComponent(), base: base, ext: "zip")
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinatorError) { zipped in
            do { try fm.copyItem(at: zipped, to: out) } catch { copyError = error }
        }
        if let error = coordinatorError ?? copyError { throw error }
        return out
    }

    #if os(macOS)
    public static func tarGz(_ urls: [URL], options: Options) async throws -> URL {
        guard let first = urls.first else { throw MorphError("Nothing to archive") }
        let parent = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let out = Output.unique(in: options.outputDirectory ?? parent, base: base, ext: "tar.gz")
        try await ExternalTool.run(URL(fileURLWithPath: "/usr/bin/tar"),
                                   ["-czf", out.path, "-C", parent.path] + urls.map(\.lastPathComponent))
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
