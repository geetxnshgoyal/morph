import AppIntents
import UniformTypeIdentifiers
import MorphCore

// Morph in the Shortcuts app, Siri, Spotlight and the Action button. Every action runs in the background on
// the device; results are saved to Morph's folder in Files (like jobs started in the app) and handed back to
// the shortcut, so they can be chained into "Save to Photos", "Share", "Quick Look" and so on.

// MARK: - Run any action

/// Any Morph action or recipe, chosen from a searchable list in Shortcuts.
struct MorphActionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Morph Action"
    static let defaultQuery = MorphActionQuery()

    let id: String
    let title: String
    let subtitle: String
    let symbol: String

    init(_ action: Action) {
        id = action.id
        title = action.group == .convert ? "Convert to \(action.title)" : action.title
        let kinds = action.kinds.count > 4 ? "Any file" : action.kinds.map(\.rawValue).sorted().joined(separator: ", ")
        subtitle = "\(action.group.label) · \(kinds)"
        symbol = action.symbol
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: .init(systemName: symbol))
    }
}

struct MorphActionQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MorphActionEntity] {
        identifiers.compactMap { Library.action($0).map(MorphActionEntity.init) }
    }

    func entities(matching string: String) async throws -> [MorphActionEntity] {
        all().filter { $0.title.localizedCaseInsensitiveContains(string) || $0.subtitle.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [MorphActionEntity] { all() }

    private func all() -> [MorphActionEntity] {
        (Library.actions + RecipeStore.shared.recipes.map(\.action)).filter(\.isAvailable).map(MorphActionEntity.init)
    }
}

struct RunActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Morph Action"
    static let description = IntentDescription(
        "Converts, compresses or cleans up files with any Morph action or recipe, and returns the results.",
        categoryName: "Files")

    @Parameter(title: "Action") var action: MorphActionEntity
    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.item"]) var files: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$action) on \(\.$files)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard let chosen = Library.action(action.id) else { throw MorphIntentError.unknownAction }
        return .result(value: try await IntentJob.files(chosen, files))
    }
}

// MARK: - Everyday jobs

enum ImageFormatOption: String, AppEnum {
    case jpg, png, heic, webp, avif, tiff, gif, bmp, svg, pdf

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Image Format"
    static let caseDisplayRepresentations: [ImageFormatOption: DisplayRepresentation] = [
        .jpg: "JPG", .png: "PNG", .heic: "HEIC", .webp: "WEBP", .avif: "AVIF",
        .tiff: "TIFF", .gif: "GIF", .bmp: "BMP", .svg: "SVG", .pdf: "PDF",
    ]

    var actionID: String { self == .pdf ? "convert.images-pdf" : "convert.\(rawValue)" }
}

struct ConvertImagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Images"
    static let description = IntentDescription(
        "Converts photos and images to JPG, PNG, HEIC, WEBP, SVG and more, or combines them into one PDF.",
        categoryName: "Images")

    @Parameter(title: "Images", supportedTypeIdentifiers: ["public.image"]) var images: [IntentFile]
    @Parameter(title: "Format", default: .jpg) var format: ImageFormatOption

    static var parameterSummary: some ParameterSummary { Summary("Convert \(\.$images) to \(\.$format)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard let action = Library.action(format.actionID) else { throw MorphIntentError.unavailable(format.rawValue.uppercased()) }
        return .result(value: try await IntentJob.files(action, images))
    }
}

enum CompressionOption: String, AppEnum {
    case light, balanced, strong

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Compression"
    static let caseDisplayRepresentations: [CompressionOption: DisplayRepresentation] = [
        .light: DisplayRepresentation(title: "Light", subtitle: "Looks identical, smaller savings"),
        .balanced: DisplayRepresentation(title: "Balanced", subtitle: "Looks the same side by side, much smaller"),
        .strong: DisplayRepresentation(title: "Strong", subtitle: "Smallest files; a close look may show softening"),
    ]

    var level: CompressionLevel { CompressionLevel(rawValue: rawValue) ?? .balanced }
}

struct CompressFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress Files"
    static let description = IntentDescription("Shrinks images, videos and PDFs.", categoryName: "Files")

    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.image", "public.movie", "com.adobe.pdf"]) var files: [IntentFile]
    @Parameter(title: "Strength", default: .balanced) var strength: CompressionOption
    @Parameter(title: "Size Limit (KB)", description: "Fit photos under this many kilobytes, as JPG. Leave empty for no limit.")
    var limitKB: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$files) (\(\.$strength))") { \.$limitKB }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        var options = Prefs.options
        options.compression = strength.level
        options.targetBytes = limitKB.map { $0 * 1000 } ?? options.targetBytes
        return .result(value: try await IntentJob.files(try IntentJob.action("tool.compress"), files, options: options))
    }
}

struct RemoveMetadataIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Metadata"
    static let description = IntentDescription(
        "Strips location, camera details and other private metadata from photos, videos and audio.",
        categoryName: "Privacy")

    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.image", "public.movie", "public.audio"]) var files: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Remove metadata from \(\.$files)") }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        .result(value: try await IntentJob.files(try IntentJob.action("tool.strip-metadata"), files))
    }
}

struct ExtractTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Extract Text"
    static let description = IntentDescription("Reads the text in images and PDFs, on device.", categoryName: "Text")

    @Parameter(title: "Images or PDFs", supportedTypeIdentifiers: ["public.image", "com.adobe.pdf"]) var files: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Extract text from \(\.$files)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = try await IntentJob.text(try IntentJob.action("tool.ocr"), files)
        return .result(value: text, dialog: "\(text.prefix(140))")
    }
}

struct ReadCodesIntent: AppIntent {
    static let title: LocalizedStringResource = "Read QR Codes and Barcodes"
    static let description = IntentDescription("Finds QR codes and barcodes in images and PDFs and returns what they say.", categoryName: "Text")

    @Parameter(title: "Images or PDFs", supportedTypeIdentifiers: ["public.image", "com.adobe.pdf"]) var files: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Read codes in \(\.$files)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = try await IntentJob.text(try IntentJob.action("tool.qr"), files)
        return .result(value: text, dialog: "\(text.prefix(140))")
    }
}

struct MergePDFsIntent: AppIntent {
    static let title: LocalizedStringResource = "Merge PDFs"
    static let description = IntentDescription("Combines PDFs into one, in the order given.", categoryName: "PDF")

    @Parameter(title: "PDFs", supportedTypeIdentifiers: ["com.adobe.pdf"]) var pdfs: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Merge \(\.$pdfs)") }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let merged = try await IntentJob.files(try IntentJob.action("tool.merge-pdf"), pdfs).first else {
            throw MorphIntentError.failed("Nothing was made")
        }
        return .result(value: merged)
    }
}

// MARK: - Open the app

struct OpenInMorphIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Morph"
    static let description = IntentDescription("Opens files in Morph to pick an action yourself.", categoryName: "Files")
    static let openAppWhenRun = true

    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.item"]) var files: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$files) in Morph") }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.openCopies(try IntentJob.stage(files))
        return .result()
    }
}

// MARK: - Siri, Spotlight and the Action button

struct MorphShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConvertImagesIntent(), phrases: [
            "Convert images with \(.applicationName)",
            "Convert photos to \(\.$format) with \(.applicationName)",
        ], shortTitle: "Convert Images", systemImageName: "photo.on.rectangle.angled")
        AppShortcut(intent: CompressFilesIntent(), phrases: [
            "Compress files with \(.applicationName)",
            "Shrink files with \(.applicationName)",
        ], shortTitle: "Compress", systemImageName: "arrow.down.right.and.arrow.up.left")
        AppShortcut(intent: RemoveMetadataIntent(), phrases: [
            "Remove metadata with \(.applicationName)",
            "Remove location from photos with \(.applicationName)",
        ], shortTitle: "Remove Metadata", systemImageName: "eye.slash")
        AppShortcut(intent: ExtractTextIntent(), phrases: [
            "Extract text with \(.applicationName)",
            "Copy text from an image with \(.applicationName)",
        ], shortTitle: "Extract Text", systemImageName: "text.viewfinder")
        AppShortcut(intent: ReadCodesIntent(), phrases: [
            "Read a QR code with \(.applicationName)",
            "Scan a barcode with \(.applicationName)",
        ], shortTitle: "Read Codes", systemImageName: "qrcode.viewfinder")
        AppShortcut(intent: MergePDFsIntent(), phrases: [
            "Merge PDFs with \(.applicationName)",
        ], shortTitle: "Merge PDFs", systemImageName: "doc.on.doc")
        AppShortcut(intent: RunActionIntent(), phrases: [
            "Run \(\.$action) with \(.applicationName)",
            "Use \(.applicationName) on files",
        ], shortTitle: "Run Action", systemImageName: "wand.and.stars")
        AppShortcut(intent: OpenInMorphIntent(), phrases: [
            "Open files in \(.applicationName)",
        ], shortTitle: "Open in Morph", systemImageName: "circle.hexagongrid.fill")
    }
}

// MARK: - Running

enum MorphIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unknownAction, noFiles, unavailable(String), wrongFiles(String), failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unknownAction: "That action isn't available any more."
        case .noFiles: "No files were given."
        case let .unavailable(format): "\(format) isn't available on this device."
        case let .wrongFiles(action): "\(action) doesn't work on these files."
        case let .failed(reason): "\(reason)"
        }
    }
}

/// Shared plumbing: copy the shortcut's files somewhere Morph can read, run, and hand back the results.
enum IntentJob {
    static func action(_ id: String) throws -> Action {
        guard let action = Library.action(id), action.isAvailable else { throw MorphIntentError.unknownAction }
        return action
    }

    static func files(_ action: Action, _ input: [IntentFile], options: Options = Prefs.options) async throws -> [IntentFile] {
        try await run(action, input, options: options).map { IntentFile(fileURL: $0, filename: $0.lastPathComponent) }
    }

    /// For actions that write a text file (text recognition, codes): the text itself.
    static func text(_ action: Action, _ input: [IntentFile]) async throws -> String {
        try await run(action, input, options: Prefs.options)
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n")
    }

    private static func run(_ action: Action, _ input: [IntentFile], options: Options) async throws -> [URL] {
        let inputs = try stage(input)
        guard action.accepts(inputs) else { throw MorphIntentError.wrongFiles(action.title) }
        let result = await Runner.run(action, inputs: inputs, options: options)
        if result.outputs.isEmpty {
            throw MorphIntentError.failed(result.failures.first ?? result.notes.first ?? "Nothing was made")
        }
        return result.outputs
    }

    /// Copies each file into a private inbox, keeping its name (and giving it an extension if it had none,
    /// since Morph decides what a file is from its extension).
    static func stage(_ files: [IntentFile]) throws -> [URL] {
        guard !files.isEmpty else { throw MorphIntentError.noFiles }
        let inbox = try AppState.newInbox()
        return try files.enumerated().map { index, file in
            var name = file.filename.isEmpty ? "File \(index + 1)" : file.filename
            if (name as NSString).pathExtension.isEmpty, let ext = file.type?.preferredFilenameExtension {
                name += ".\(ext)"
            }
            let destination = Output.unique(in: inbox, base: (name as NSString).deletingPathExtension,
                                            ext: (name as NSString).pathExtension)
            if let source = file.fileURL {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: destination)
            } else {
                try file.data.write(to: destination)
            }
            return destination
        }
    }
}
