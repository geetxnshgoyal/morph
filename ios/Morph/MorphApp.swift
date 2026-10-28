import SwiftUI
import MorphCore

@main
struct MorphApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var state = AppState.shared
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage(Palette.key) private var palette = Palette.teal.rawValue
    @State private var showSplash = !UIAccessibility.isReduceMotionEnabled

    init() {
        // Lets Siri and Spotlight offer "Run <action> with Morph" for every action and recipe.
        MorphShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                    // The app settles into place as the launch mark dissolves over it.
                    .scaleEffect(showSplash ? 0.94 : 1)
                    .blur(radius: showSplash ? 10 : 0)
                if showSplash {
                    MorphSplash { withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { showSplash = false } }
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 2.4))))
                        .zIndex(1)
                }
            }
            .environmentObject(state)
            .tint((Palette(rawValue: palette) ?? .teal).fill)
            .fullScreenCover(isPresented: Binding(get: { !hasSeenWelcome && !showSplash }, set: { hasSeenWelcome = !$0 })) {
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
    /// One per app, so Shortcuts ("Open in Morph") and home-screen quick actions can reach the UI.
    static let shared = AppState()

    @Published var batch: Batch?
    @Published var recent: [HistoryEntry] = []
    @Published var importError: String?
    /// A home-screen quick action waiting for the home screen to act on it.
    @Published var quickAction: QuickAction?

    /// Results go to Documents, which the Files app shows as "On My iPhone → Morph".
    nonisolated static let results: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        // Copies of files imported in earlier sessions; each job works on its own fresh copies.
        try? FileManager.default.removeItem(at: Self.inboxRoot)
        reload()
    }

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
                // Two files can share a name ("scan.pdf" from two folders); the second becomes "scan 2.pdf".
                let dest = Output.unique(in: inbox, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
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

    nonisolated static var inboxRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Inbox") }

    nonisolated static func newInbox() throws -> URL {
        let dir = inboxRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Home-screen quick actions

/// The menu from pressing and holding Morph's icon (declared as UIApplicationShortcutItems in Info.plist).
enum QuickAction: String {
    case photos = "app.morph.photos"
    case files = "app.morph.files"
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // A quick action that launched the app arrives here; one used while it runs goes to the scene delegate.
        if let item = options.shortcutItem { MainActor.assumeIsolated { SceneDelegate.handle(item) } }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(Self.handle(shortcutItem))
    }

    @MainActor @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(rawValue: item.type) else { return false }
        AppState.shared.quickAction = action
        return true
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
        case .light: "Looks identical, smaller savings."
        case .balanced: "Looks the same side by side, much smaller."
        case .strong: "Smallest files; a close look may show softening."
        }
    }
}

enum Prefs {
    static var compression: CompressionLevel {
        UserDefaults.standard.string(forKey: "compression").flatMap(CompressionLevel.init) ?? .balanced
    }

    static var haptics: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    /// Bytes Compress must fit under, for upload forms; 0 is no limit.
    static var sizeLimit: Int { UserDefaults.standard.integer(forKey: SizeLimit.key) }

    /// Exact size Resize makes for forms ("600x600"); empty keeps the usual fit.
    static var photoSize: PixelSize? { PixelSize(UserDefaults.standard.string(forKey: "photoSize") ?? "") }

    /// Printed with the date under the photo at that size; empty prints nothing.
    static var photoCaption: String { UserDefaults.standard.string(forKey: "photoCaption") ?? "" }

    static var options: Options {
        var options = Options()
        options.compression = compression
        if sizeLimit > 0 { options.targetBytes = sizeLimit }
        options.exactSize = photoSize
        if !photoCaption.isEmpty { options.caption = photoCaption }
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
        case .file: "Actions"
        }
    }
}
