import PhotosUI
import QuickLook
import SwiftUI
import MorphCore

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showSettings = false
    @State private var loadingPhotos = false
    @State private var preview: URL?

    var body: some View {
        PaletteScope {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    hero
                    recent
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .background(Theme.canvas.ignoresSafeArea())
        }
        .sheet(item: $state.batch, onDismiss: state.reload) { batch in
            ActionsView(files: batch.files)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(34)
                .sheetBackground()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationCornerRadius(34)
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { state.open(urls) }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        // Home-screen quick actions, including one that launched the app before this view existed.
        .onReceive(state.$quickAction.compactMap { $0 }) { action in
            state.quickAction = nil
            state.batch = nil
            switch action {
            case .photos: showPhotos = true
            case .files: showFiles = true
            }
        }
        .quickLookPreview($preview)
        .alert("Couldn't open that file", isPresented: Binding(get: { state.importError != nil }, set: { _ in state.importError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.importError ?? "")
        }
        .onAppear(perform: state.reload)
        #if DEBUG
        // `simctl launch … -settings` opens Settings, for screenshots.
        .task { if ProcessInfo.processInfo.arguments.contains("-settings") { showSettings = true } }
        #endif
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("Morph").font(Theme.font(34, .bold))
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassControl(in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are we\nmaking today?").font(Theme.font(28, .bold))
                Text("Convert, shrink and clean up any file.").font(Theme.font(15, .medium)).opacity(0.85)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                    heroButton("Photos", symbol: loadingPhotos ? "hourglass" : "photo.on.rectangle.angled")
                }
                .buttonStyle(SquishyButtonStyle())

                Button { showFiles = true } label: {
                    heroButton("Files", symbol: "folder.fill")
                }
                .buttonStyle(SquishyButtonStyle())
            }
        }
        .foregroundStyle(Theme.onBrand)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Theme.brand
                .overlay(alignment: .topTrailing) {
                    // Soft bubbles for a bit of play.
                    Circle().fill(.white.opacity(0.12)).frame(width: 150).offset(x: 50, y: -50)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(.white.opacity(0.10)).frame(width: 90).offset(x: -30, y: 30)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private func heroButton(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.font(16, .semibold))
            .foregroundStyle(Palette.current.textOnWhite)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassControl(in: Capsule(), tint: .white)
    }

    @ViewBuilder private var recent: some View {
        Text("Recent").font(Theme.font(20, .bold)).padding(.top, 6)
        if state.recent.isEmpty {
            VStack(spacing: 10) {
                SymbolBubble(symbol: "sparkles", size: 56)
                Text("Nothing yet").font(Theme.font(17, .semibold))
                Text("Files you convert show up here, and in the Files app under Morph.")
                    .font(Theme.font(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .card()
        } else {
            ForEach(state.recent) { entry in
                RecentRow(entry: entry) { preview = $0 }
            }
        }
    }

    // MARK: Photos

    // The system picker runs outside Morph and hands over only what the user picks, so no library permission is
    // needed (or asked for).

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingPhotos = true
        Task { @MainActor in
            var urls: [URL] = []
            for item in items {
                if let media = try? await item.loadTransferable(type: PickedMedia.self) { urls.append(media.url) }
            }
            loadingPhotos = false
            photoItems = []
            if urls.isEmpty {
                state.importError = "Those photos couldn't be loaded. If they're in iCloud, try again once they've downloaded."
            } else {
                state.openCopies(urls)
            }
        }
    }
}

/// A photo or video copied out of the library into Morph's inbox.
struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { try copy($0.file) }
        FileRepresentation(importedContentType: .image) { try copy($0.file) }
    }

    private static func copy(_ source: URL) throws -> PickedMedia {
        let dest = try AppState.newInbox().appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)
        return PickedMedia(url: dest)
    }
}

struct RecentRow: View {
    @EnvironmentObject private var state: AppState
    let entry: HistoryEntry
    let onPreview: (URL) -> Void

    private var available: [URL] {
        entry.undone ? [] : entry.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        Button {
            if let first = available.first { onPreview(first) }
        } label: {
            HStack(spacing: 14) {
                SymbolBubble(symbol: entry.undone ? "arrow.uturn.backward" : entry.outputs.isEmpty ? "xmark" : "checkmark")
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(Theme.font(16, .semibold)).strikethrough(entry.undone)
                    Text("\(entry.date.formatted(.relative(presentation: .named))) · \(entry.outputs.count) file\(entry.outputs.count == 1 ? "" : "s")")
                        .font(Theme.font(13)).foregroundStyle(.secondary)
                }
                Spacer()
                if !available.isEmpty {
                    ShareLink(items: available) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.brandText)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.tint))
                    }
                }
            }
            .card(padding: 14)
        }
        .buttonStyle(SquishyButtonStyle())
        .foregroundStyle(.primary)
        .contextMenu {
            if !available.isEmpty {
                Button(role: .destructive) {
                    _ = try? History.shared.undo(entry.id)
                    state.reload()
                } label: { Label("Delete Results", systemImage: "trash") }
            }
        }
    }
}

