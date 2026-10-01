import SwiftUI
import MorphCore

@main
struct MorphApp: App {
    @StateObject private var state = AppState()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(state)
                .tint(Theme.tangerine)
                .fullScreenCover(isPresented: Binding(get: { !hasSeenWelcome }, set: { hasSeenWelcome = !$0 })) {
                    OnboardingView { hasSeenWelcome = true }
                }
                // "Open in Morph" from another app's share sheet.
                .onOpenURL { state.open([$0]) }
                #if DEBUG
                // `simctl launch … -open /path/to/file` jumps straight to the actions sheet.
                .task {
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-open"), i + 1 < args.count { state.open([URL(fileURLWithPath: args[i + 1])]) }
                }
                #endif
        }
    }
}

/// Files picked for the actions sheet.
struct Batch: Identifiable {
    let id = UUID()
    let files: [URL]
}

@MainActor
final class AppState: ObservableObject {
    @Published var batch: Batch?
    @Published var recent: [HistoryEntry] = []
    @Published var importError: String?

    /// Results go to Documents, which the Files app shows as "On My iPhone → Morph".
    nonisolated static let results: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() { reload() }

    func reload() {
        recent = Array(History.shared.entries.reversed().prefix(30))
    }

    /// Copies incoming files somewhere private and stable, then shows the actions sheet.
    func open(_ urls: [URL]) {
        do {
            let inbox = try Self.newInbox()
            let fm = FileManager.default
            let copies = try urls.map { url -> URL in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let dest = inbox.appendingPathComponent(url.lastPathComponent)
                try fm.copyItem(at: url, to: dest)
                // Files iOS dropped into Documents/Inbox for us shouldn't linger next to the results.
                if url.path.hasPrefix(Self.results.appendingPathComponent("Inbox").path) { try? fm.removeItem(at: url) }
                return dest
            }
            guard !copies.isEmpty else { return }
            batch = Batch(files: copies)
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Already-copied files (from the photo picker).
    func openCopies(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        batch = Batch(files: urls)
    }

    nonisolated static func newInbox() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Inbox/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Preferences

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

enum Prefs {
    static var compression: CompressionLevel {
        UserDefaults.standard.string(forKey: "compression").flatMap(CompressionLevel.init) ?? .balanced
    }

    static var haptics: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    static var options: Options {
        var options = Options()
        options.compression = compression
        options.outputDirectory = AppState.results
        return options
    }
}

extension Action.Group {
    var label: String {
        switch self {
        case .convert: "Convert"
        case .tool: "Tools"
        case .recipe: "Recipes"
        }
    }
}
