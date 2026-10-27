import Foundation

public struct Action: Identifiable, Sendable {
    /// `file` holds everyday actions on the files themselves (share, copy, move…), which each app supplies;
    /// the engine's own library has none.
    public enum Group: String, Codable, Sendable { case convert, tool, recipe, file }

    public let id: String
    public let title: String
    public let symbol: String
    public let group: Group
    public let kinds: Set<FileKind>
    /// Called once with every input (merge, zip) rather than once per file.
    public let combinesInputs: Bool
    public let minimumInputs: Int
    /// Hidden when every input already has this extension (no "PNG → PNG").
    public let targetExtension: String?
    public let needsFFmpeg: Bool
    public let run: @Sendable ([URL], Options) async throws -> [URL]

    public init(id: String, title: String, symbol: String, group: Group, kinds: Set<FileKind>, combinesInputs: Bool,
                minimumInputs: Int, targetExtension: String?, needsFFmpeg: Bool,
                run: @escaping @Sendable ([URL], Options) async throws -> [URL]) {
        self.id = id; self.title = title; self.symbol = symbol; self.group = group; self.kinds = kinds
        self.combinesInputs = combinesInputs; self.minimumInputs = minimumInputs
        self.targetExtension = targetExtension; self.needsFFmpeg = needsFFmpeg; self.run = run
    }

    public var isAvailable: Bool { !needsFFmpeg || ExternalTool.ffmpeg != nil }

    /// Edits that keep an image in its own format and work on its pixels, which an SVG doesn't have.
    var editsPixels: Bool { ["tool.compress", "tool.strip-metadata", "tool.redact-faces", "tool.redact-pii"].contains(id) }

    /// Whether "171 KB → 139 KB" is worth showing after this action: true for actions that remake the same
    /// content, false for ones that extract something else (text, codes, snapshots).
    public var reportsSize: Bool {
        group == .recipe || ["tool.compress", "tool.resize", "tool.strip-metadata"].contains(id)
            || (group == .convert && !["convert.pdf-text", "convert.pdf-images"].contains(id))
    }

    public func accepts(_ urls: [URL]) -> Bool {
        guard urls.count >= minimumInputs, isAvailable else { return false }
        guard urls.allSatisfy({ kinds.contains(FileKind(url: $0)) }) else { return false }
        if editsPixels, urls.contains(where: VectorOps.isSVG) { return false }
        if let ext = targetExtension, urls.allSatisfy({ $0.pathExtension.lowercased() == ext }) { return false }
        return true
    }
}

public enum Library {
    private static func one(_ id: String, _ title: String, _ symbol: String, _ group: Action.Group, _ kinds: Set<FileKind>,
                            target: String? = nil, ffmpeg: Bool = false,
                            _ body: @escaping @Sendable (URL, Options) async throws -> URL) -> Action {
        Action(id: id, title: title, symbol: symbol, group: group, kinds: kinds, combinesInputs: false, minimumInputs: 1,
               targetExtension: target, needsFFmpeg: ffmpeg) { urls, options in
            var outputs: [URL] = []
            for url in urls { outputs.append(try await body(url, options)) }
            return outputs
        }
    }

    private static func all(_ id: String, _ title: String, _ symbol: String, _ group: Action.Group, _ kinds: Set<FileKind>,
                            minimum: Int = 1, _ body: @escaping @Sendable ([URL], Options) async throws -> URL) -> Action {
        Action(id: id, title: title, symbol: symbol, group: group, kinds: kinds, combinesInputs: true, minimumInputs: minimum,
               targetExtension: nil, needsFFmpeg: false) { urls, options in [try await body(urls, options)] }
    }

    public static let actions: [Action] = {
        var list: [Action] = []

        // Images: the common formats, SVG and PDF come first so they share the wheel's first page; rarer formats follow.
        let common: [ImageFormat] = [.jpg, .png, .heic, .webp]
        func image(_ fmt: ImageFormat) -> Action {
            one("convert.\(fmt.rawValue)", fmt.rawValue.uppercased(), "photo", .convert, [.image], target: fmt.rawValue) {
                try ImageOps.convert($0, to: fmt, options: $1)
            }
        }
        for fmt in common where fmt.isAvailable { list.append(image(fmt)) }
        list.append(one("convert.svg", "SVG", "scribble.variable", .convert, [.image], target: "svg") { try VectorOps.trace($0, options: $1) })
        list.append(all("convert.images-pdf", "PDF", "doc.richtext", .convert, [.image]) { try PDFOps.fromImages($0, options: $1) })
        for fmt in ImageFormat.allCases where !common.contains(fmt) && fmt.isAvailable { list.append(image(fmt)) }

        // Video
        for ext in ["mp4", "mov"] {
            list.append(one("convert.video-\(ext)", ext.uppercased(), "film", .convert, [.video], target: ext) {
                try await MediaOps.convertVideo($0, to: ext, options: $1)
            })
        }
        for ext in ["webm", "mkv"] {
            list.append(one("convert.video-\(ext)", ext.uppercased(), "film", .convert, [.video], target: ext, ffmpeg: true) {
                try await MediaOps.convertVideo($0, to: ext, options: $1)
            })
        }
        list.append(one("convert.video-gif", "GIF", "sparkles.rectangle.stack", .convert, [.video]) { try await MediaOps.toGIF($0, options: $1) })

        // Audio (video inputs extract their soundtrack)
        for ext in ["m4a", "wav", "aiff"] {
            list.append(one("convert.audio-\(ext)", ext.uppercased(), "waveform", .convert, [.audio, .video], target: ext) {
                try await MediaOps.convertAudio($0, to: ext, options: $1)
            })
        }
        for ext in ["mp3", "flac", "ogg", "opus"] {
            list.append(one("convert.audio-\(ext)", ext.uppercased(), "waveform", .convert, [.audio, .video], target: ext, ffmpeg: true) {
                try await MediaOps.convertAudio($0, to: ext, options: $1)
            })
        }

        // PDF & documents
        list.append(one("convert.pdf-images", "Images", "photo.on.rectangle", .convert, [.pdf]) { try PDFOps.toImages($0, options: $1) })
        list.append(one("convert.pdf-text", "Text", "text.alignleft", .convert, [.pdf]) { try PDFOps.toText($0, options: $1) })
        for ext in DocOps.outputFormats {
            let kinds: Set<FileKind> = ext == "pdf" ? [.document, .data, .subtitle] : (ext == "docx" ? [.document, .pdf] : [.document])
            list.append(one("convert.doc-\(ext)", ext.uppercased(), "doc.text", .convert, kinds, target: ext) {
                try DocOps.convert($0, to: ext, options: $1)
            })
        }
        for ext in ["srt", "vtt"] {
            list.append(one("convert.sub-\(ext)", ext.uppercased(), "captions.bubble", .convert, [.subtitle], target: ext) {
                try DocOps.convertSubtitle($0, to: ext, options: $1)
            })
        }
        for ext in ["csv", "tsv", "json"] {
            list.append(one("convert.data-\(ext)", ext.uppercased(), "tablecells", .convert, [.data], target: ext) {
                try DocOps.convertData($0, to: ext, options: $1)
            })
        }

        // Tools
        list.append(one("tool.compress", "Compress", "arrow.down.right.and.arrow.up.left", .tool, [.image, .video, .pdf]) { url, o in
            let out: URL = switch FileKind(url: url) {
            case .video: try await MediaOps.compressVideo(url, options: o)
            case .pdf: try PDFOps.compress(url, options: o)
            default: try ImageOps.compress(url, options: o)
            }
            // A "compressed" copy that isn't meaningfully smaller is only a worse duplicate.
            if o.targetBytes == nil, Double(Runner.size(of: out)) >= Double(Runner.size(of: url)) * 0.95 {
                try? FileManager.default.removeItem(at: out)
                throw MorphNote("\(url.lastPathComponent) is already as small as it can get without losing quality")
            }
            return out
        })
        list.append(one("tool.resize", "Resize", "arrow.up.left.and.down.right.magnifyingglass", .tool, [.image]) { try ImageOps.resize($0, options: $1) })
        list.append(one("tool.strip-metadata", "Remove Metadata", "eye.slash", .tool, [.image, .video, .audio]) { url, o in
            FileKind(url: url) == .image ? try ImageOps.stripMetadata(url, options: o).output : try await MediaOps.stripMetadata(url, options: o)
        })
        list.append(one("tool.redact-faces", "Blur Faces", "person.crop.circle.badge.xmark", .tool, [.image]) { try VisionOps.redactFaces($0, options: $1) })
        list.append(one("tool.redact-pii", "Hide Personal Info", "eye.trianglebadge.exclamationmark", .tool, [.image]) { try VisionOps.redactPersonalInfo($0, options: $1) })
        list.append(one("tool.ocr", "Extract Text", "text.viewfinder", .tool, [.image, .pdf]) { try VisionOps.ocr($0, options: $1) })
        list.append(one("tool.qr", "Read QR", "qrcode.viewfinder", .tool, [.image, .pdf]) { try VisionOps.readCodes($0, options: $1) })
        list.append(all("tool.merge-pdf", "Merge PDFs", "doc.on.doc", .tool, [.pdf], minimum: 2) { try PDFOps.merge($0, options: $1) })
        list.append(one("tool.split-pdf", "Split PDF", "scissors", .tool, [.pdf]) { try PDFOps.split($0, options: $1) })
        list.append(one("tool.mute", "Mute", "speaker.slash", .tool, [.video]) { try await MediaOps.mute($0, options: $1) })
        list.append(Action(id: "tool.snapshots", title: "Snapshots", symbol: "camera.viewfinder", group: .tool, kinds: [.video],
                           combinesInputs: false, minimumInputs: 1, targetExtension: nil, needsFFmpeg: false) { urls, o in
            var outputs: [URL] = []
            for url in urls { outputs += try await MediaOps.snapshots(url, options: o) }
            return outputs
        })
        list.append(one("tool.normalize", "Normalize Loudness", "speaker.wave.3", .tool, [.audio, .video], ffmpeg: true) { try await MediaOps.normalize($0, options: $1) })
        list.append(one("tool.trim-silence", "Trim Silence", "waveform.badge.minus", .tool, [.audio], ffmpeg: true) { try await MediaOps.trimSilence($0, options: $1) })
        list.append(one("tool.waveform-video", "Waveform Video", "waveform.and.magnifyingglass", .tool, [.audio], ffmpeg: true) { try await MediaOps.waveformVideo($0, options: $1) })
        list.append(all("tool.zip", "Zip", "doc.zipper", .tool, Set(FileKind.allCases)) { try ArchiveOps.zip($0, options: $1) })
        #if os(macOS)
        list.append(all("tool.tar-gz", "tar.gz", "archivebox", .tool, [.folder]) { try await ArchiveOps.tarGz($0, options: $1) })
        list.append(one("tool.extract", "Extract", "shippingbox.and.arrow.backward", .tool, [.archive]) { try await ArchiveOps.extract($0, options: $1) })
        #endif
        return list
    }()

    public static func action(_ id: String) -> Action? {
        if let a = actions.first(where: { $0.id == id }) { return a }
        if id.hasPrefix("recipe."), let r = RecipeStore.shared.recipe(named: String(id.dropFirst(7))) { return r.action }
        return nil
    }

    /// Actions offered for a drop, in display order, recipes included.
    public static func actions(for urls: [URL], group: Action.Group? = nil) -> [Action] {
        let recipes = RecipeStore.shared.recipes.map(\.action)
        return (actions + recipes).filter { (group == nil || $0.group == group || (group == .tool && $0.group == .recipe)) && $0.accepts(urls) }
    }
}
