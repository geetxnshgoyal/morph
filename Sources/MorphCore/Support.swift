import Foundation
import UniformTypeIdentifiers

public struct MorphError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Not a failure: the file was left alone on purpose (say, it's already as small as it can get without
/// losing quality). Runner reports it as a note rather than an error.
public struct MorphNote: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum FileKind: String, Codable, Sendable, CaseIterable {
    case image, video, audio, pdf, document, subtitle, data, archive, folder, other

    public init(url: URL) {
        let ext = url.pathExtension.lowercased()
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, ext != "rtfd" {
            self = .folder; return
        }
        switch ext {
        case "srt", "vtt": self = .subtitle; return
        case "csv", "tsv", "json": self = .data; return
        case "md", "markdown", "docx", "doc", "odt", "rtfd", "html", "htm": self = .document; return
        case "zip", "tar", "gz", "tgz", "rar", "7z", "xz", "bz2": self = .archive; return
        default: break
        }
        guard let type = UTType(filenameExtension: ext) else { self = .other; return }
        if type.conforms(to: .pdf) { self = .pdf }
        else if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .text) || type.conforms(to: .rtf) { self = .document }
        else { self = .other }
    }
}

public enum CompressionLevel: String, Codable, Sendable, CaseIterable {
    case light, balanced, strong

    /// How close a compressed image must stay to the original (SSIM on luminance, 1 = identical).
    /// Light is indistinguishable, balanced looks the same side by side, strong may soften on a close look.
    var minimumSimilarity: Double {
        switch self { case .light: 0.995; case .balanced: 0.985; case .strong: 0.97 }
    }
}

public enum RedactStyle: String, Codable, Sendable, CaseIterable { case pixelate, solid }

/// Knobs shared by every action. Unset values fall back to sensible per-action defaults.
public struct Options: Codable, Sendable {
    public var quality: Double?
    public var compression: CompressionLevel = .balanced
    public var maxPixel: Int?
    public var targetBytes: Int?
    public var redactStyle: RedactStyle = .pixelate
    public var outputDirectory: URL?
    /// Palette size when tracing an image into an SVG; unset picks one from `compression`.
    public var colors: Int?
    /// Exact size for Resize, cropped to fill: what passport, visa and exam forms ask for.
    public var exactSize: PixelSize?
    /// Printed with the date the photo was taken in a white strip under it, for exam forms.
    public var caption: String?

    public init() {}

    /// Parses "500KB", "2.5mb", "1g", or plain bytes.
    public static func parseSize(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        let units: [(String, Double)] = [("gb", 1e9), ("g", 1e9), ("mb", 1e6), ("m", 1e6), ("kb", 1e3), ("k", 1e3), ("b", 1)]
        for (suffix, mult) in units where s.hasSuffix(suffix) {
            return Double(s.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)).map { Int($0 * mult) }
        }
        return Int(s)
    }
}

/// Size limits the apps offer for Compress, for upload forms that cap a file's size (often 20 KB to 2 MB).
/// Stored in bytes under `key`; 0 means no limit. Sizes are decimal, so "200 KB" also fits a 200 KiB cap.
public enum SizeLimit {
    public static let key = "sizeLimit"
    public static let presets = [20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000, 2_000_000, 5_000_000]

    public static func label(_ bytes: Int) -> String {
        bytes <= 0 ? "No limit" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// What Compress does with this limit, for the Settings screens.
    public static func detail(_ bytes: Int) -> String {
        bytes <= 0
            ? "Compress makes the smallest file that still looks the same. Set a limit for upload forms that cap file size."
            : "Compress fits photos under \(label(bytes)) as JPG, at the best quality that fits, ready for upload forms."
    }
}

/// An exact width × height in pixels, for forms that ask for one ("600 × 600", "413 × 531").
public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }

    public var label: String { "\(width) × \(height)" }

    /// Parses "600x600", "600 × 600" or "600*600".
    public init?(_ text: String) {
        let parts = text.lowercased().split(whereSeparator: { "x×* ,".contains($0) }).compactMap { Int($0) }
        guard parts.count == 2, (16...8000).contains(parts[0]), (16...8000).contains(parts[1]) else { return nil }
        self.init(width: parts[0], height: parts[1])
    }

    /// Sizes people are asked for most, grouped for a menu. Millimetre sizes are at 300 dpi.
    public static let presets: [(group: String, items: [(name: String, size: PixelSize)])] = [
        ("Passport and visa", [
            ("US or India, 2 × 2 in", PixelSize(width: 600, height: 600)),
            ("Schengen, UK, 35 × 45 mm", PixelSize(width: 413, height: 531)),
            ("China visa, 33 × 48 mm", PixelSize(width: 354, height: 472)),
        ]),
        ("Exams", [
            ("Exam photo, 3.5 × 4.5 cm", PixelSize(width: 413, height: 531)),
            ("Bank exams photo", PixelSize(width: 200, height: 230)),
        ]),
        ("Signature", [
            ("Signature, small", PixelSize(width: 140, height: 60)),
            ("Signature, large", PixelSize(width: 280, height: 120)),
        ]),
        ("Social and web", [
            ("Square post", PixelSize(width: 1080, height: 1080)),
            ("Portrait post", PixelSize(width: 1080, height: 1350)),
            ("Story", PixelSize(width: 1080, height: 1920)),
            ("Full HD", PixelSize(width: 1920, height: 1080)),
            ("HD", PixelSize(width: 1280, height: 720)),
            ("Profile picture", PixelSize(width: 400, height: 400)),
        ]),
    ]
}

/// Picks non-colliding output paths next to the source (originals are never overwritten).
public enum Output {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reserved = Set<String>()

    public static func url(for source: URL, ext: String, suffix: String? = nil, options: Options) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + (suffix.map { " \($0)" } ?? "")
        return unique(in: options.outputDirectory ?? source.deletingLastPathComponent(), base: base, ext: ext)
    }

    public static func unique(in folder: URL, base: String, ext: String) -> URL {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        func make(_ name: String) -> URL {
            let u = folder.appendingPathComponent(name)
            return ext.isEmpty ? u : u.appendingPathExtension(ext)
        }
        var candidate = make(base)
        var i = 2
        while fm.fileExists(atPath: candidate.path) || reserved.contains(candidate.path) {
            candidate = make("\(base) \(i)"); i += 1
        }
        reserved.insert(candidate.path)
        return candidate
    }

    public static func folder(for source: URL, suffix: String, options: Options) throws -> URL {
        let dir = url(for: source, ext: "", suffix: suffix, options: options)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("morph-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// The App Sandbox (the Mac App Store build). Inside it Morph can only touch files and folders the user hands
/// it, and can't run tools from Homebrew.
public enum Sandbox {
    public static let isActive = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}

public enum ExternalTool {
    public static func find(_ name: String) -> URL? {
        #if os(macOS)
        guard !Sandbox.isActive else { return nil }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        #endif
        return nil
    }

    public static var ffmpeg: URL? { find("ffmpeg") }
    public static var cwebp: URL? { find("cwebp") }

    #if os(macOS)
    /// Runs a tool to completion, draining stderr so chatty tools can't deadlock on a full pipe.
    @discardableResult
    public static func run(_ tool: URL, _ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = tool
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let buffer = LockedData()
        out.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData, stderr: false) }
        err.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData, stderr: true) }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in c.resume() }
            do { try process.run() } catch { process.terminationHandler = nil; c.resume(throwing: error) }
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        buffer.append(out.fileHandleForReading.readDataToEndOfFile(), stderr: false)
        buffer.append(err.fileHandleForReading.readDataToEndOfFile(), stderr: true)
        guard process.terminationStatus == 0 else {
            let tail = buffer.stderrText.split(separator: "\n").suffix(3).joined(separator: " ")
            throw MorphError("\(tool.lastPathComponent) failed: \(tail.isEmpty ? "exit \(process.terminationStatus)" : tail)")
        }
        return buffer.stdoutText
    }
    #endif

    public static func requireFFmpeg() throws -> URL {
        guard let url = ffmpeg else { throw MorphError("This needs ffmpeg. Install it with: brew install ffmpeg") }
        return url
    }

    public static func ffmpeg(_ args: [String]) async throws {
        #if os(macOS)
        try await run(try requireFFmpeg(), ["-hide_banner", "-loglevel", "error", "-y"] + args)
        #else
        throw MorphError("This format isn't supported on this device yet")
        #endif
    }
}

final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    func append(_ d: Data, stderr: Bool) {
        lock.lock(); defer { lock.unlock() }
        if stderr { err.append(d) } else { out.append(d) }
    }
    var stdoutText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: out, as: UTF8.self) }
    var stderrText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: err, as: UTF8.self) }
}

public enum Paths {
    public static var support: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Morph")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
