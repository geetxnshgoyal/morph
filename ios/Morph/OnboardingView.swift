import SwiftUI
import MorphCore

/// First-launch guide: what Morph is, how to use it, where it works, the settings worth choosing up front, and the
/// privacy promise. Picking a colour recolours the guide as you tap.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State var page = 0
    @AppStorage("compression") private var compression = CompressionLevel.balanced.rawValue
    @AppStorage(SizeLimit.key) private var sizeLimit = 0
    private let pages = 5

    var body: some View {
        PaletteScope {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    intro.tag(0)
                    howItWorks.tag(1)
                    everywhere.tag(2)
                    makeItYours.tag(3)
                    privacy.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    HStack(spacing: 6) {
                        ForEach(0..<pages, id: \.self) { i in
                            Capsule().fill(i == page ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                                .frame(width: i == page ? 24 : 8, height: 8)
                        }
                    }
                    Button(page == pages - 1 ? "Get Started" : "Continue") {
                        if page == pages - 1 { onFinish() } else { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 } }
                    }
                    .buttonStyle(BubbleButtonStyle(fullWidth: true))
                    Button("Skip", action: onFinish)
                        .font(Theme.font(15, .medium)).foregroundStyle(.secondary)
                        .opacity(page == pages - 1 ? 0 : 1)
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            }
            .background(Theme.canvas.ignoresSafeArea())
        }
    }

    private var intro: some View {
        ScrollView {
            VStack(spacing: 22) {
                LogoMark().padding(.top, 50)
                VStack(spacing: 8) {
                    Text("Welcome to Morph").font(Theme.font(32, .bold))
                    Text("Convert, shrink and tidy up any file, right on your phone.")
                        .font(Theme.font(17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                    feature("arrow.triangle.2.circlepath", "Convert", "Images, video, audio, PDFs and documents")
                    feature("arrow.down.right.and.arrow.up.left", "Compress", "Make big files small enough to send")
                    feature("wand.and.stars", "Clean up", "Strip location data, blur faces, read text")
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var howItWorks: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("How it works").font(Theme.font(32, .bold)).padding(.top, 60)
                step(1, "Pick some files", "Tap Photos or Files on the home screen, or share to Morph from any app.")
                step(2, "Choose what to make", "Only actions that fit your files show up.")
                step(3, "Share or save the result", "Results are kept in the Files app under Morph. Your originals never change.")
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var everywhere: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Works with your apps").font(Theme.font(32, .bold)).padding(.top, 60).padding(.bottom, 8)
                feature("square.and.arrow.up", "Share to Morph", "In Photos, Files or any app, tap Share, then Morph.")
                feature("app.connected.to.app.below.fill", "Shortcuts and Siri",
                        "Find Convert Images, Compress Files and more in the Shortcuts app, or ask Siri.")
                feature("hand.tap.fill", "Press and hold the icon", "Jump straight to Convert Photos or Choose Files.")
                feature("folder.fill", "Results in Files", "Everything you make is kept under On My iPhone → Morph.")
            }
            .padding(.horizontal, 24)
        }
    }

    private var makeItYours: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make it yours").font(Theme.font(32, .bold))
                    Text("You can change all of this later in Settings.").font(Theme.font(15)).foregroundStyle(.secondary)
                }
                .padding(.top, 60).padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Color").font(Theme.font(17, .semibold))
                        Spacer()
                        Text(Palette.current.name).font(Theme.font(15, .semibold)).foregroundStyle(Theme.brandText)
                    }
                    PalettePicker(size: 36)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Size limit").font(Theme.font(17, .semibold))
                        Spacer()
                        SizeLimitMenu(limit: $sizeLimit)
                    }
                    Text("Upload forms often want photos under 200 KB or 100 KB. Set a limit and Compress makes a JPG that fits.")
                        .font(Theme.font(14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Compression").font(Theme.font(17, .semibold))
                    PillPicker(options: CompressionLevel.allCases,
                               selection: Binding(get: { CompressionLevel(rawValue: compression) ?? .balanced },
                                                  set: { compression = $0.rawValue })) { $0.label }
                    Text((CompressionLevel(rawValue: compression) ?? .balanced).detail)
                        .font(Theme.font(14)).foregroundStyle(.secondary)
                }
                .card()
            }
            .padding(.horizontal, 24)
        }
    }

    private var privacy: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.tint).frame(width: 150, height: 150)
                    Circle().fill(Theme.brand).frame(width: 96, height: 96)
                    Image(systemName: "lock.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.onBrand)
                }
                .padding(.top, 70)
                Text("Private by design").font(Theme.font(32, .bold))
                Text("Everything happens on your device. No accounts, no uploads, no tracking.")
                    .font(Theme.font(17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            SymbolBubble(symbol: symbol, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(17, .semibold))
                Text(detail).font(Theme.font(14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(n)").font(Theme.font(18, .bold)).foregroundStyle(Theme.onBrand)
                .frame(width: 38, height: 38).background(Circle().fill(Theme.brand))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.font(19, .semibold))
                Text(detail).font(Theme.font(15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
