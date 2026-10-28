import AppKit
import Carbon.HIToolbox
import SwiftUI
import MorphCore

// MARK: - Geometry

/// The wheel's measurements, shared by the panel (to centre the wheel on the cursor) and the view.
enum WheelMetrics {
    static let width: CGFloat = 440
    static let height: CGFloat = 496
    /// Centre of the ring, from the panel's top-left; the wheel bar hangs below the ring.
    static let center = CGPoint(x: 220, y: 220)
    static let outerRadius: CGFloat = 168
    static let innerRadius: CGFloat = 88
    static let hubRadius: CGFloat = 76
    /// Neighbouring petals are this far apart all the way out.
    static let gapWidth: CGFloat = 7
    /// How far a highlighted petal grows outward.
    static let lift: CGFloat = 12
    /// Square the ring is drawn in, with room for a lifted petal.
    static let side: CGFloat = (outerRadius + lift + 12) * 2
    static let labelRadius: CGFloat = (innerRadius + outerRadius) / 2 + 2
}

// MARK: - Wheel window

@MainActor
final class WheelPanel: NSPanel {
    private var monitor: Any?
    let model: WheelModel

    init(files: [URL], dropMode: Bool = false, group: Action.Group? = nil) {
        model = WheelModel(files: files, dropMode: dropMode, group: group)
        super.init(contentRect: NSRect(x: 0, y: 0, width: WheelMetrics.width, height: WheelMetrics.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        model.dismiss = { [weak self] in self?.close() }
        let host = NSHostingView(rootView: WheelView(model: model))
        host.frame = contentRect(forFrameRect: frame)
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    func present(at point: NSPoint) {
        // Centre the ring (not the panel) under the cursor, keeping the whole panel on the cursor's screen.
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - WheelMetrics.center.x,
                             y: point.y - (WheelMetrics.height - WheelMetrics.center.y))
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - WheelMetrics.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - WheelMetrics.height)
        }
        setFrameOrigin(origin)
        alphaValue = 0
        if model.dropMode {
            // Activating now would cancel the drag in progress.
            orderFrontRegardless()
        } else {
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // The folder permission panel runs in another process; clicking it isn't clicking away.
            MainActor.assumeIsolated { if !FolderAccess.isAsking { self?.close() } }
        }
    }

    /// Scrolling and keys steer the wheel before SwiftUI sees them.
    override func sendEvent(_ event: NSEvent) {
        guard case .choosing = model.phase else { return super.sendEvent(event) }
        switch event.type {
        case .scrollWheel:
            model.scroll(event)
            return
        case .keyDown:
            switch Int(event.keyCode) {
            case kVK_RightArrow, kVK_DownArrow: model.step(1); return
            case kVK_LeftArrow, kVK_UpArrow: model.step(-1); return
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: model.runHighlighted(); return
            case kVK_Tab: model.cycleGroup(event.modifierFlags.contains(.shift) ? -1 : 1); return
            case kVK_Escape: close(); return
            default: break
            }
        default: break
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    /// Closing melts the wheel back into a drop (unless Reduce Motion is on) before the window goes.
    override func close() {
        guard !isClosing else { return }
        isClosing = true
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return super.close() }
        model.closing = true
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.24; animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { super.close() }
        }
    }

    private var isClosing = false
}

// MARK: - Wheel model

@MainActor
final class WheelModel: ObservableObject {
    enum Phase { case choosing, running(Action, done: Int, total: Int), finished(Action, RunResult) }

    /// Petals per ring; more actions than this page around with a turn of the wheel.
    static let perPage = 8

    private(set) var files: [URL]
    let actions: [Action]
    let dropMode: Bool
    @Published private(set) var group: Action.Group
    @Published private(set) var page = 0
    @Published var phase: Phase = .choosing
    /// The window is going away: the view plays the wheel's exit.
    @Published var closing = false
    @Published var hovered: String? {
        didSet { if hovered != oldValue, hovered != nil { Feedback.shared.tick() } }
    }
    var dismiss: () -> Void = {}
    private var scrollAccumulator: CGFloat = 0

    init(files: [URL], dropMode: Bool = false, group: Action.Group? = nil) {
        self.files = files
        self.dropMode = dropMode
        // Work on a local copy: closures can't read `self` until every property is set.
        let available = Library.actions(for: files) + FileActions.actions(for: files)
        actions = available
        let fallback: Action.Group = available.contains { $0.group == .convert } ? .convert : .tool
        self.group = group.flatMap { g in available.contains { $0.group == g } ? g : nil } ?? fallback
    }

    var groups: [Action.Group] {
        Preferences.wheels.filter { g in actions.contains { $0.group == g } }
    }

    var visible: [Action] { actions.filter { $0.group == group } }
    var pages: Int { max(1, (visible.count + Self.perPage - 1) / Self.perPage) }
    var pageItems: [Action] { Array(visible.dropFirst(page * Self.perPage).prefix(Self.perPage)) }

    var summary: String {
        let kinds = Set(files.map { FileKind(url: $0) })
        let noun = kinds.count == 1 ? kinds.first!.rawValue : "file"
        return files.count == 1 ? files[0].lastPathComponent : "\(files.count) \(noun)s"
    }

    /// Centre of petal `index`, in degrees: the first points straight up, the rest follow clockwise.
    static func angle(of index: Int, count: Int) -> Double {
        Double(index) / Double(max(count, 1)) * 360 - 90
    }

    /// The petal under `point` (relative to the ring's centre), or nil over the hub or far outside the ring.
    static func slot(at point: CGPoint, count: Int) -> Int? {
        let distance = hypot(point.x, point.y)
        guard count > 0, distance >= WheelMetrics.hubRadius,
              distance <= WheelMetrics.outerRadius + WheelMetrics.lift + 24 else { return nil }
        let sector = 360 / Double(count)
        var degrees = atan2(point.y, point.x) * 180 / .pi + 90
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return Int((degrees + sector / 2) / sector) % count
    }

    var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }

    // MARK: Navigation

    func select(_ newGroup: Action.Group) {
        guard newGroup != group, groups.contains(newGroup) else { return }
        withAnimation(motion) {
            group = newGroup
            page = 0
            hovered = nil
        }
        Feedback.shared.tick()
    }

    func cycleGroup(_ delta: Int) {
        guard let i = groups.firstIndex(of: group), groups.count > 1 else { return }
        select(groups[(i + delta + groups.count) % groups.count])
    }

    /// Highlights the petal under `point`, as the pointer or a drag moves over the ring.
    func hover(at point: CGPoint) {
        let items = pageItems
        hovered = Self.slot(at: point, count: items.count).map { items[$0].id }
    }

    func action(at point: CGPoint) -> Action? {
        let items = pageItems
        return Self.slot(at: point, count: items.count).map { items[$0] }
    }

    /// Moves the highlight around the ring, turning to the next page at the ends.
    func step(_ delta: Int) {
        let items = pageItems
        guard !items.isEmpty else { return }
        guard let id = hovered, let i = items.firstIndex(where: { $0.id == id }) else {
            hovered = (delta >= 0 ? items.first : items.last)?.id
            return
        }
        let j = i + delta
        if j >= items.count || j < 0 {
            if pages > 1 {
                turnPage(j < 0 ? -1 : 1)
                hovered = (j < 0 ? pageItems.last : pageItems.first)?.id
            } else {
                hovered = items[(j + items.count) % items.count].id
            }
            return
        }
        hovered = items[j].id
    }

    func turnPage(_ delta: Int) {
        guard pages > 1 else { return }
        withAnimation(motion) { page = (page + delta + pages) % pages }
    }

    /// Mouse wheel: one notch per step. Trackpad: a step every few points of travel.
    func scroll(_ event: NSEvent) {
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard delta != 0 else { return }
        guard event.hasPreciseScrollingDeltas else { step(delta < 0 ? 1 : -1); return }
        scrollAccumulator += delta
        let threshold: CGFloat = 16
        while abs(scrollAccumulator) >= threshold {
            step(scrollAccumulator < 0 ? 1 : -1)
            scrollAccumulator -= scrollAccumulator < 0 ? -threshold : threshold
        }
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccumulator = 0 }
    }

    /// Takes the files from a drop on the wheel. The App Store build can't read a dragged file until it's dropped
    /// on Morph, so the paths seen mid-drag only pick the actions; the drop itself brings the access.
    func takeDropped(_ pasteboard: NSPasteboard) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { files = urls.map(\.standardizedFileURL) }
    }

    func runHighlighted() {
        if let action = pageItems.first(where: { $0.id == hovered }) { run(action) }
    }

    // MARK: Running

    func run(_ action: Action) {
        let files = files
        let prefs = Preferences.shared
        if action.group == .file {
            // Acts on the files themselves and may open its own window, so get out of the way first.
            dismiss()
            Task {
                do { _ = try await action.run(files, Options()) } catch { FileActions.report(error) }
            }
            return
        }
        guard let options = prefs.options(for: files) else { dismiss(); return }
        phase = .running(action, done: 0, total: files.count)
        Task {
            let result = await Runner.run(action, inputs: files, options: options) { done, total in
                Task { @MainActor in
                    if case .running = self.phase { self.phase = .running(action, done: done, total: total) }
                }
            }
            phase = .finished(action, result)
            if result.failures.isEmpty {
                if prefs.playSounds { NSSound(named: "Glass")?.play() }
                if prefs.revealWhenDone, !result.outputs.isEmpty { reveal(result); return }
                // Long enough to read "171 KB → 144 KB".
                try? await Task.sleep(for: .seconds(3.5))
                if case .finished = phase { dismiss() }
            } else if prefs.playSounds {
                NSSound.beep()
            }
        }
    }

    func reveal(_ result: RunResult) {
        NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
        dismiss()
    }
}

// MARK: - Wheel view

/// A ring of glass petals around a glass hub, with a bar below for switching wheels. Each wheel (Convert,
/// Tools, Recipes, Actions) uses the same layout; the bar shows the keys that summon each one mid-drag.
struct WheelView: View {
    @ObservedObject var model: WheelModel
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Open and not on its way out: drives the hub's drop-like entrance and exit.
    private var present: Bool { appeared && !model.closing }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                // Liquid Glass leaves the window's own pixels clear, and macOS hands clicks and drops on clear
                // pixels to the window behind. A fill too faint to see keeps the ring, gaps included, ours.
                Circle().fill(.black.opacity(0.01))
                if case .choosing = model.phase {
                    PetalRing(model: model, items: model.pageItems)
                        .id("\(model.group)-\(model.page)")
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                WheelHub(model: model)
                    .scaleEffect(present ? 1 : 0.3)
                    .blur(radius: present ? 0 : 12)
                    .opacity(present ? 1 : 0)
            }
            .frame(width: WheelMetrics.side, height: WheelMetrics.side)
            .position(WheelMetrics.center)

            if case .choosing = model.phase, model.groups.count > 1 {
                WheelBar(model: model)
                    .scaleEffect(present ? 1 : 0.85)
                    .opacity(present ? 1 : 0)
                    .position(x: WheelMetrics.center.x, y: WheelMetrics.center.y + WheelMetrics.outerRadius + WheelMetrics.lift + 42)
                    .transition(.opacity)
            }
        }
        .frame(width: WheelMetrics.width, height: WheelMetrics.height)
        // In: the hub springs out of a drop. Out: everything is pulled back into it.
        .animation(reduceMotion ? nil : model.closing ? .easeIn(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.6),
                   value: present)
        .onAppear { appeared = true }
    }
}

/// The petals of one page. Every petal blooms out of the hub when the ring appears, so switching wheel or
/// page replays the opening; hover, click and drop all find their petal by position, gaps included.
private struct PetalRing: View {
    @ObservedObject var model: WheelModel
    let items: [Action]
    @State private var bloomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, action in
                PetalView(action: action, index: index, count: items.count,
                          highlighted: model.hovered == action.id, bloomed: bloomed)
                    .animation(reduceMotion ? nil : model.closing ? .easeIn(duration: 0.18)
                        : .spring(response: 0.48, dampingFraction: 0.74).delay(Double(index) * 0.022), value: bloomed)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.68),
                               value: model.hovered == action.id)
            }
        }
        .frame(width: WheelMetrics.side, height: WheelMetrics.side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): model.hover(at: centered(location))
            case .ended: model.hovered = nil
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in
            if let action = model.action(at: centered(location)) { model.run(action) }
        }
        // Dropping the dragged files on a petal runs it.
        .onDrop(of: [.fileURL], delegate: RingDropDelegate(model: model, centered: centered))
        .onAppear { bloomed = true }
        .onChange(of: model.closing) { _, closing in if closing { bloomed = false } }
    }

    private func centered(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - WheelMetrics.side / 2, y: point.y - WheelMetrics.side / 2)
    }
}

private struct RingDropDelegate: DropDelegate {
    let model: WheelModel
    let centered: (CGPoint) -> CGPoint

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated { model.hover(at: centered(info.location)) }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { model.hovered = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            guard let action = model.action(at: centered(info.location)) else { return false }
            model.takeDropped(NSPasteboard(name: .drag))
            model.run(action)
            return true
        }
    }
}

/// One action: a glass wedge with a light rim, its icon and its name. Highlighted, it lifts outward and fills with
/// Teal Ink.
private struct PetalView: View {
    let action: Action
    let index: Int
    let count: Int
    let highlighted: Bool
    let bloomed: Bool

    private typealias M = WheelMetrics

    var body: some View {
        let angle = WheelModel.angle(of: index, count: count)
        let shape = PetalShape(centerAngle: angle, sectorAngle: 360 / Double(count), gapWidth: M.gapWidth,
                               innerRadius: highlighted ? M.innerRadius - 3 : M.innerRadius,
                               outerRadius: !bloomed ? M.innerRadius + 6 : highlighted ? M.outerRadius + M.lift : M.outerRadius)
        let radians = angle * .pi / 180
        let labelRadius = M.labelRadius + (highlighted ? M.lift / 2 : 0)

        ZStack {
            Color.clear.wheelGlass(in: shape)
            shape.fill(highlighted ? Theme.brand : Color.clear)
            // The rim is brighter on the highlighted petal so it stands off dark backgrounds too.
            shape.stroke(LinearGradient(colors: [.white.opacity(highlighted ? 0.55 : 0.5), .white.opacity(highlighted ? 0.25 : 0.06)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: highlighted ? 1.5 : 1)
                .opacity(bloomed ? 1 : 0)

            VStack(spacing: 3) {
                Image(systemName: action.symbol).font(.system(size: highlighted ? 19 : 17, weight: .medium))
                Text(action.title).font(Theme.font(10.5, .semibold))
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
            }
            .frame(width: labelWidth)
            .foregroundStyle(highlighted ? Theme.onBrand : Color.primary)
            .offset(x: cos(radians) * labelRadius, y: sin(radians) * labelRadius)
            .opacity(bloomed ? 1 : 0)
        }
        .frame(width: M.side, height: M.side)
        .opacity(bloomed ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Wide enough to use the petal, narrow enough to stay inside it.
    private var labelWidth: CGFloat {
        let chord = 2 * M.labelRadius * sin(.pi / Double(max(count, 2))) - M.gapWidth - 14
        return min(92, max(54, chord))
    }
}

/// The glass hub: names the highlighted action (or the files), shows progress while running and the result after.
private struct WheelHub: View {
    @ObservedObject var model: WheelModel

    private let diameter = WheelMetrics.hubRadius * 2

    var body: some View {
        ZStack {
            Color.clear.wheelGlass(in: Circle())
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 14)
            content.frame(width: diameter - 26)
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .choosing:
            VStack(spacing: 5) {
                Text(hoverTitle ?? model.summary)
                    .font(Theme.font(14, .semibold))
                    .lineLimit(2).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: model.hovered)
                Text(caption).font(Theme.font(11)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if model.pages > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<model.pages, id: \.self) { i in
                            Capsule().fill(i == model.page ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                                .frame(width: i == model.page ? 12 : 5, height: 5)
                        }
                    }
                    .padding(.top, 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.page)
                }
            }
        case let .running(action, done, total):
            VStack(spacing: 8) {
                MorphLoader(size: 58)
                Text(action.title).font(Theme.font(14, .semibold))
                if total > 1 { Text("\(done) of \(total)").font(.caption).foregroundStyle(.secondary) }
            }
        case let .finished(action, result):
            // Nothing made and nothing failed: every file was already as small as it can usefully get.
            let unchanged = result.outputs.isEmpty && result.failures.isEmpty && !result.notes.isEmpty
            VStack(spacing: 5) {
                Image(systemName: !result.failures.isEmpty ? "exclamationmark.triangle.fill"
                      : unchanged ? "equal.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(result.failures.isEmpty ? Theme.brandText : Color.red)
                Text(!result.failures.isEmpty ? "\(result.failures.count) failed" : unchanged ? "Already small" : "Done")
                    .font(Theme.font(14, .semibold))
                if action.reportsSize, let sizes = result.sizeSummary, let change = result.sizeChange {
                    Text(sizes).font(Theme.font(12, .semibold)).monospacedDigit()
                    Text(change).font(Theme.font(11)).foregroundStyle(.secondary)
                } else if unchanged {
                    Text("Any smaller would look worse").font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if let first = result.failures.first {
                    Text(first).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        .multilineTextAlignment(.center)
                }
                if !result.outputs.isEmpty {
                    Button("Show in Finder") { model.reveal(result) }.buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    private var caption: String {
        if model.actions.isEmpty { return "Nothing fits these files" }
        if model.hovered != nil { return model.dropMode ? "Release to run" : "Click to run" }
        return model.dropMode ? "Drop on an action" : model.group.label
    }

    private var hoverTitle: String? {
        model.hovered.flatMap { id in model.actions.first { $0.id == id } }.map { action in
            action.group == .convert ? "Convert to \(action.title)" : action.title
        }
    }
}

/// Glass bar of the wheels these files have, each labelled with the keys that summon it mid-drag. Clicking,
/// Tab, or hovering a drag over one switches to it.
private struct WheelBar: View {
    @ObservedObject var model: WheelModel
    @ObservedObject private var prefs = Preferences.shared
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.groups, id: \.self) { group in
                let selected = group == model.group
                let keys = prefs.dragKeys(for: group)
                Button { model.select(group) } label: {
                    HStack(spacing: 5) {
                        if !keys.isEmpty {
                            Text(keys.symbols).font(Theme.font(11, .bold)).opacity(selected ? 0.85 : 0.5)
                        }
                        Text(group.label).font(Theme.font(12, .semibold))
                    }
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .foregroundStyle(selected ? Theme.onBrand : Color.primary)
                    .background {
                        if selected { Capsule().fill(Theme.brand).matchedGeometryEffect(id: "pill", in: pill) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(keys.isEmpty ? group.label : "\(group.label): tap \(keys.symbols) while dragging")
                // Spring-loaded: hovering a drag over a wheel switches to it.
                .onDrop(of: [.fileURL], isTargeted: Binding(get: { false }, set: { if $0 { model.select(group) } })) { _ in false }
            }
        }
        .padding(4)
        .background(Capsule().fill(.black.opacity(0.01)))
        .wheelGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

private extension View {
    /// Liquid Glass that follows the system's Clear or Tinted setting; frosted material before macOS 26.
    func wheelGlass(in shape: some Shape, tint: Color? = nil) -> some View {
        modifier(MorphGlass(shape: shape, tint: tint))
    }
}

/// An annular wedge whose sides run parallel to the boundary between petals, so the gap to each neighbour keeps
/// the same width from hub to rim, with softly rounded corners. Animatable, so a petal can bloom out of the hub
/// and lift when highlighted. Angles are in degrees, clockwise from three o'clock.
struct PetalShape: Shape {
    var centerAngle: Double
    var sectorAngle: Double
    var gapWidth: CGFloat
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var cornerRadius: CGFloat = 9

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(centerAngle, sectorAngle), AnimatablePair(innerRadius, outerRadius)) }
        set {
            centerAngle = newValue.first.first
            sectorAngle = newValue.first.second
            innerRadius = newValue.second.first
            outerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        guard outerRadius > innerRadius, innerRadius > 0 else { return path }

        // A lone petal is the whole ring.
        if sectorAngle >= 359.9 {
            path.addArc(center: c, radius: outerRadius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            path.closeSubpath()
            path.move(to: CGPoint(x: c.x + innerRadius, y: c.y))
            path.addArc(center: c, radius: innerRadius, startAngle: .zero, endAngle: .degrees(-360), clockwise: true)
            path.closeSubpath()
            return path
        }

        let mid = centerAngle * .pi / 180
        // Half the petal's angle at radius r, after giving half the gap to each side.
        func half(_ r: CGFloat) -> Double { sectorAngle * .pi / 360 - Double(asin(min(1, gapWidth / 2 / r))) }
        let ho = half(outerRadius), hi = half(innerRadius)
        guard ho > 0, hi > 0 else { return path }

        func point(_ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        // Direction of travel along a circle at angle a, toward larger angles.
        func ahead(_ a: Double) -> CGVector { CGVector(dx: -sin(a), dy: cos(a)) }
        func offset(_ p: CGPoint, _ v: CGVector, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + v.dx * d, y: p.y + v.dy * d) }

        let r = min(cornerRadius, (outerRadius - innerRadius) / 3)
        let outerStart = point(outerRadius, mid - ho), outerEnd = point(outerRadius, mid + ho)
        let innerEnd = point(innerRadius, mid + hi), innerStart = point(innerRadius, mid - hi)

        // Start partway up the leading side, then fillet each corner into the arc beside it.
        path.move(to: CGPoint(x: (innerStart.x + outerStart.x) / 2, y: (innerStart.y + outerStart.y) / 2))
        path.addArc(tangent1End: outerStart, tangent2End: offset(outerStart, ahead(mid - ho), r * 2), radius: r)
        path.addArc(center: c, radius: outerRadius, startAngle: .radians(mid - ho + Double(r / outerRadius)),
                    endAngle: .radians(mid + ho - Double(r / outerRadius)), clockwise: false)
        path.addArc(tangent1End: outerEnd, tangent2End: innerEnd, radius: r)
        path.addArc(tangent1End: innerEnd, tangent2End: offset(innerEnd, ahead(mid + hi), -r * 2), radius: r)
        path.addArc(center: c, radius: innerRadius, startAngle: .radians(mid + hi - Double(r / innerRadius)),
                    endAngle: .radians(mid - hi + Double(r / innerRadius)), clockwise: true)
        path.addArc(tangent1End: innerStart, tangent2End: outerStart, radius: r)
        path.closeSubpath()
        return path
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
