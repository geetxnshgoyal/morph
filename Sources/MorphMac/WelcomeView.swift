import AppKit
import SwiftUI
import MorphCore

/// First-launch guide: what Morph is, how to use it (with a live drop zone), then setup.
struct WelcomeView: View {
    let onTry: ([URL]) -> Void
    let onFinish: () -> Void

    @State var page = 0
    @State private var forward = true
    private let pages = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: intro
                case 1: howItWorks
                default: setup
                }
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40).padding(.top, 44)
            .clipped()

            footer
        }
        .frame(width: 580, height: 560)
        .background(Theme.canvas)
        .tint(Theme.tangerine)
    }

    // MARK: Pages

    private var intro: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 128, height: 128)
                .shadow(color: Theme.coral.opacity(0.3), radius: 18, y: 8)
            VStack(spacing: 8) {
                Text("Welcome to Morph").font(Theme.font(32, .bold))
                Text("Convert, shrink and tidy up any file, right where it is.")
                    .font(Theme.font(15)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                feature("arrow.triangle.2.circlepath", "Convert", "Images, video, audio, PDFs and docs")
                feature("arrow.down.right.and.arrow.up.left", "Compress", "Hit a target size in one tap")
                feature("wand.and.stars", "Clean up", "Strip metadata, blur faces, read text")
            }
            .padding(.top, 8)
            Label("Everything runs on your Mac. Files never leave it.", systemImage: "lock.fill")
                .font(Theme.font(12)).foregroundStyle(.secondary)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(Theme.font(26, .bold))
            step(1, "Hand Morph some files", "While dragging a file anywhere, hold Shift: the wheel pops up right under it. Or drop on the menu bar icon.")
            step(2, "Pick from the wheel", "Only actions that fit your files show up. Hover one to see what it does.")
            step(3, "Find the result beside the original", "Originals are never touched, and any job can be undone from the menu bar.")
            TryItZone(onFiles: onTry).padding(.top, 4)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make it yours").font(Theme.font(26, .bold))
            Text("You can change all of this later in Settings.").font(Theme.font(13)).foregroundStyle(.secondary)
                .padding(.bottom, 4)
            if AppLocation.isBundled, !AppLocation.isInstalled { MoveToApplicationsRow() }
            LoginItemRow()
            DragShortcutRow()
            FinderServiceRow()
            FFmpegRow()
        }
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule().fill(i == page ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            Spacer()
            if page > 0 {
                Button("Back") { go(-1) }.buttonStyle(.plain).font(Theme.font(14, .medium)).foregroundStyle(.secondary)
                    .padding(.trailing, 10)
            }
            Button(page == pages - 1 ? "Start Using Morph" : "Continue") {
                page == pages - 1 ? onFinish() : go(1)
            }
            .buttonStyle(BubbleButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += delta }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            SymbolBubble(symbol: symbol, size: 44)
            Text(title).font(Theme.font(14, .semibold))
            Text(detail).font(Theme.font(11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 14)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(Theme.font(15, .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, .semibold))
                Text(detail).font(Theme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Dashed bubble that opens the wheel for whatever is dropped on it.
struct TryItZone: View {
    let onFiles: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            .foregroundStyle(targeted ? Theme.tangerine : .secondary.opacity(0.35))
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(targeted ? Theme.tint : Theme.surface.opacity(0.6)))
            .frame(height: 104)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                    Text("Try it: drop a file here").font(Theme.font(14, .semibold))
                    Text("A copy is made; your file stays as it is.").font(Theme.font(11)).foregroundStyle(.secondary)
                }
            }
            .scaleEffect(targeted ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
            .dropDestination(for: URL.self) { urls, _ in onFiles(urls); return true } isTargeted: { targeted = $0 }
    }
}
