import Photos
import QuickLook
import SwiftUI
import MorphCore

@MainActor
final class JobModel: ObservableObject {
    enum Phase { case choosing, running(Action, done: Int, total: Int), finished(Action, RunResult) }

    let files: [URL]
    let actions: [Action]
    @Published var group: Action.Group
    @Published var phase: Phase = .choosing

    init(files: [URL]) {
        self.files = files
        actions = Library.actions(for: files)
        group = actions.contains { $0.group == .convert } ? .convert : .tool
    }

    var groups: [Action.Group] { [.convert, .tool, .recipe].filter { g in actions.contains { $0.group == g } } }
    var visible: [Action] { actions.filter { $0.group == group } }

    var kind: FileKind {
        let kinds = Set(files.map { FileKind(url: $0) })
        return kinds.count == 1 ? kinds.first! : .other
    }

    var summary: String {
        files.count == 1 ? files[0].lastPathComponent : "\(files.count) \(kind == .other ? "file" : kind.rawValue)s"
    }

    func run(_ action: Action) {
        if Prefs.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .running(action, done: 0, total: files.count) }
        let files = files
        Task {
            let result = await Runner.run(action, inputs: files, options: Prefs.options) { done, total in
                Task { @MainActor in
                    if case .running = self.phase { self.phase = .running(action, done: done, total: total) }
                }
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { phase = .finished(action, result) }
            if Prefs.haptics {
                UINotificationFeedbackGenerator().notificationOccurred(result.failures.isEmpty ? .success : .error)
            }
        }
    }
}

struct ActionsView: View {
    @StateObject private var model: JobModel
    @Environment(\.dismiss) private var dismiss

    init(files: [URL]) { _model = StateObject(wrappedValue: JobModel(files: files)) }

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .choosing: choosing
            case let .running(action, done, total): RunningView(action: action, done: done, total: total)
            case let .finished(action, result): ResultView(action: action, result: result) { dismiss() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetCanvas()
        .presentationDragIndicator(.visible)
        #if DEBUG
        // `simctl launch … -open <file> -run <action id>` runs an action straight away.
        .task {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-run"), i + 1 < args.count,
               let action = model.actions.first(where: { $0.id == args[i + 1] }) { model.run(action) }
        }
        #endif
    }

    private var choosing: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    SymbolBubble(symbol: symbol(for: model.kind), size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.summary).font(Theme.font(18, .semibold)).lineLimit(1).truncationMode(.middle)
                        Text("Pick what to make").font(Theme.font(14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 26)

                if model.actions.isEmpty {
                    VStack(spacing: 8) {
                        SymbolBubble(symbol: "questionmark", size: 56)
                        Text("Nothing fits this file yet").font(Theme.font(17, .semibold))
                        Text("Morph handles images, video, audio, PDFs, documents and data files.")
                            .font(Theme.font(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).card()
                } else {
                    if model.groups.count > 1 {
                        PillPicker(options: model.groups, selection: $model.group) { $0.label }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 14)], spacing: 18) {
                        ForEach(model.visible, id: \.id) { action in
                            ActionBubble(action: action) { model.run(action) }
                        }
                    }
                    .id(model.group)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.group)
        }
    }

    private func symbol(for kind: FileKind) -> String {
        switch kind {
        case .image: "photo.fill"
        case .video: "film.fill"
        case .audio: "waveform"
        case .pdf: "doc.richtext.fill"
        case .document: "doc.text.fill"
        case .data: "tablecells.fill"
        case .subtitle: "captions.bubble.fill"
        case .archive: "doc.zipper"
        case .folder: "folder.fill"
        case .other: "doc.on.doc.fill"
        }
    }
}

struct ActionBubble: View {
    let action: Action
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 8) {
                Image(systemName: action.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(Theme.surface))
                    .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
                Text(action.title)
                    .font(Theme.font(13, .semibold))
                    .lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SquishyButtonStyle())
        .foregroundStyle(.primary)
    }
}

struct RunningView: View {
    let action: Action
    let done: Int
    let total: Int

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                // Several files: a thin ring fills as each one finishes, around the liquid loader.
                if total > 1 {
                    Circle().stroke(Theme.tint, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.04, Double(done) / Double(total)))
                        .stroke(Theme.brand,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring, value: done)
                }
                MorphLoader(size: 112)
            }
            .frame(width: 140, height: 140)
            VStack(spacing: 4) {
                Text(action.group == .convert ? "Making \(action.title)…" : "\(action.title)…").font(Theme.font(20, .bold))
                if total > 1 { Text("\(done) of \(total)").font(Theme.font(15)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
}

struct ResultView: View {
    let action: Action
    let result: RunResult
    let onDone: () -> Void

    @State private var preview: URL?
    @State private var savedToPhotos = false
    @State private var saveError: String?
    @State private var pop = false

    private var ok: Bool { result.failures.isEmpty }
    /// Nothing made and nothing failed: every file was already as small as it can usefully get.
    private var unchanged: Bool { ok && result.outputs.isEmpty && !result.notes.isEmpty }
    private var media: [URL] { result.outputs.filter { [.image, .video].contains(FileKind(url: $0)) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    // A ring ripples out once as the result lands.
                    Circle().stroke(ok ? Theme.brand : Color.red, lineWidth: 3)
                        .scaleEffect(pop ? 1.9 : 1)
                        .opacity(pop ? 0 : 0.9)
                        .animation(.easeOut(duration: 0.9), value: pop)
                    Circle().fill(ok ? Theme.brand : Color.red)
                    Image(systemName: unchanged ? "equal" : ok ? "checkmark" : "exclamationmark").font(.system(size: 40, weight: .bold)).foregroundStyle(ok ? Theme.onBrand : .white)
                        .symbolEffect(.bounce, value: pop)
                }
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                .scaleEffect(pop ? 1 : 0.4)
                .padding(.top, 30)

                VStack(spacing: 4) {
                    Text(unchanged ? "Already small" : ok ? "All done!" : result.outputs.isEmpty ? "That didn't work" : "Partly done")
                        .font(Theme.font(24, .bold))
                    Text(unchanged ? "Any smaller would look worse, so nothing was changed."
                         : ok ? "Saved to Morph in the Files app." : result.failures.first ?? "")
                        .font(Theme.font(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                if action.reportsSize, let sizes = result.sizeSummary, let change = result.sizeChange {
                    HStack(spacing: 10) {
                        Text(sizes).monospacedDigit()
                        Text(change).foregroundStyle(Theme.brandText)
                    }
                    .font(Theme.font(16, .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.tint))
                }

                ForEach(result.outputs, id: \.self) { url in
                    Button { preview = url } label: {
                        HStack(spacing: 12) {
                            SymbolBubble(symbol: "doc.fill", size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).font(Theme.font(15, .semibold)).lineLimit(1).truncationMode(.middle)
                                Text(size(of: url)).font(Theme.font(13)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "eye").foregroundStyle(.secondary)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(SquishyButtonStyle())
                    .foregroundStyle(.primary)
                }

                VStack(spacing: 10) {
                    if !result.outputs.isEmpty {
                        ShareLink(items: result.outputs) {
                            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BubbleButtonStyle(fullWidth: true))
                    }
                    HStack(spacing: 10) {
                        if !media.isEmpty {
                            Button(savedToPhotos ? "Saved!" : "Save to Photos", action: saveToPhotos)
                                .buttonStyle(SoftButtonStyle()).disabled(savedToPhotos)
                        }
                        if !result.outputs.isEmpty {
                            Button("Show in Files", action: showInFiles).buttonStyle(SoftButtonStyle())
                        }
                        Button("Done", action: onDone).buttonStyle(SoftButtonStyle())
                    }
                    if let saveError { Text(saveError).font(Theme.font(13)).foregroundStyle(.red) }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .quickLookPreview($preview, in: result.outputs)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = true } }
    }

    private func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func saveToPhotos() {
        Task {
            guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
                saveError = "Allow Morph to add photos in Settings → Privacy → Photos."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in media {
                        if FileKind(url: url) == .video {
                            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        } else {
                            PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
                        }
                    }
                }
                savedToPhotos = true
            } catch {
                saveError = "Photos couldn't take this format. Try sharing it instead."
            }
        }
    }

    private func showInFiles() {
        let folder = result.outputs.first?.deletingLastPathComponent() ?? AppState.results
        if let url = URL(string: "shareddocuments://" + folder.path) { UIApplication.shared.open(url) }
    }
}
