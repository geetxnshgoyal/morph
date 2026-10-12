import AppKit
import Carbon.HIToolbox
import SwiftUI
import MorphCore

// MARK: - Wheel window

@MainActor
final class WheelPanel: NSPanel {
    static let size: CGFloat = 420
    private var monitor: Any?
    let model: WheelModel

    init(files: [URL], dropMode: Bool = false, group: Action.Group? = nil) {
        model = WheelModel(files: files, dropMode: dropMode, group: group)
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
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
        // Keep the whole wheel on the screen the cursor is on.
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - Self.size)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - Self.size)
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
            MainActor.assumeIsolated { self?.close() }
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

    override func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        super.close()
    }
}

// MARK: - Wheel model

@MainActor
final class WheelModel: ObservableObject {
    enum Phase { case choosing, running(Action, done: Int, total: Int), finished(Action, RunResult) }

    /// Bubbles per ring; more actions than this page around with a turn of the wheel.
    static let perPage = 8

    let files: [URL]
    let actions: [Action]
    let dropMode: Bool
    @Published private(set) var group: Action.Group
    @Published private(set) var page = 0
    /// +1 / -1: which way the last page turn went, for the rotation direction.
    @Published private(set) var turn = 1
    @Published var phase: Phase = .choosing
    @Published var hovered: String? {
        didSet {
            guard hovered != oldValue else { return }
            if hovered != nil { Feedback.shared.tick() }
            updatePetal()
        }
    }
    /// Angle (degrees) of the highlight petal, kept continuous so it never spins the long way round.
    @Published private(set) var petalAngle: Double = -90
    var dismiss: () -> Void = {}
    private var scrollAccumulator: CGFloat = 0

    init(files: [URL], dropMode: Bool = false, group: Action.Group? = nil) {
        self.files = files
        self.dropMode = dropMode
        // Work on a local copy: closures can't read `self` until every property is set.
        let available = Library.actions(for: files)
        actions = available
        let fallback: Action.Group = available.contains { $0.group == .convert } ? .convert : .tool
        self.group = group.flatMap { g in available.contains { $0.group == g } ? g : nil } ?? fallback
    }

    var groups: [Action.Group] {
        [.convert, .tool, .recipe].filter { g in actions.contains { $0.group == g } }
    }

    var visible: [Action] { actions.filter { $0.group == group } }
    var pages: Int { max(1, (visible.count + Self.perPage - 1) / Self.perPage) }
    var pageItems: [Action] { Array(visible.dropFirst(page * Self.perPage).prefix(Self.perPage)) }

    var summary: String {
        let kinds = Set(files.map { FileKind(url: $0) })
        let noun = kinds.count == 1 ? kinds.first!.rawValue : "file"
        return files.count == 1 ? files[0].lastPathComponent : "\(files.count) \(noun)s"
    }

    static func angle(of index: Int, count: Int) -> Double {
        Double(index) / Double(max(count, 1)) * 360 - 90
    }

    private var motion: Animation? {
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
        withAnimation(motion) {
            turn = delta
            page = (page + delta + pages) % pages
        }
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

    func runHighlighted() {
        if let action = pageItems.first(where: { $0.id == hovered }) { run(action) }
    }

    private func updatePetal() {
        let items = pageItems
        guard let id = hovered, let i = items.firstIndex(where: { $0.id == id }) else { return }
        var target = Self.angle(of: i, count: items.count)
        // Pick the copy of the angle nearest the current one.
        while target - petalAngle > 180 { target -= 360 }
        while petalAngle - target > 180 { target += 360 }
        withAnimation(motion ?? .linear(duration: 0)) { petalAngle = target }
    }

    // MARK: Running

    func run(_ action: Action) {
        phase = .running(action, done: 0, total: files.count)
        let files = files
        let prefs = Preferences.shared
        Task {
            let result = await Runner.run(action, inputs: files, options: prefs.options) { done, total in
                Task { @MainActor in
                    if case .running = self.phase { self.phase = .running(action, done: done, total: total) }
                }
            }
            phase = .finished(action, result)
            if result.failures.isEmpty {
                if prefs.playSounds { NSSound(named: "Glass")?.play() }
                if prefs.revealWhenDone, !result.outputs.isEmpty { reveal(result); return }
                try? await Task.sleep(for: .seconds(2.5))
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

struct WheelView: View {
    @ObservedObject var model: WheelModel

    private let radius: CGFloat = 150
    private let hub: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Theme.tangerine.opacity(0.25), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                .frame(width: (radius + 48) * 2, height: (radius + 48) * 2)

            if case .choosing = model.phase {
                petal
                ring
            }

            hubView
        }
        .frame(width: WheelPanel.size, height: WheelPanel.size)
    }

    /// Soft gradient wedge that glides to the highlighted bubble.
    @ViewBuilder private var petal: some View {
        if model.hovered != nil, model.pageItems.contains(where: { $0.id == model.hovered }) {
            let span = min(64, 360 / Double(max(model.pageItems.count, 1)) - 8)
            let shape = Petal(center: model.petalAngle, span: span, inner: radius - 40, outer: radius + 40)
            // A round-joined stroke softens the corners; fading the pair as one keeps the overlap invisible.
            ZStack {
                shape.fill(Theme.accent)
                shape.stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineJoin: .round))
            }
            .compositingGroup()
            .opacity(0.22)
            .transition(.opacity)
        }
    }

    private var ring: some View {
        let items = model.pageItems
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, action in
                let angle = Angle.degrees(WheelModel.angle(of: index, count: items.count))
                WheelButton(action: action, hovered: model.hovered == action.id) { model.run(action) }
                    .onHover { setHovered(action, $0) }
                    // Dropping the dragged files on a bubble runs it.
                    .onDrop(of: [.fileURL], isTargeted: Binding(get: { model.hovered == action.id }, set: { setHovered(action, $0) })) { _ in
                        model.run(action)
                        return true
                    }
                    .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
            }
        }
        .id("\(model.group)-\(model.page)")
        .transition(.asymmetric(
            insertion: .modifier(active: Turn(angle: Double(model.turn) * 40, opacity: 0), identity: Turn(angle: 0, opacity: 1)),
            removal: .modifier(active: Turn(angle: Double(-model.turn) * 40, opacity: 0), identity: Turn(angle: 0, opacity: 1))
        ))
    }

    @ViewBuilder private var hubView: some View {
        ZStack {
            Circle().fill(Theme.surface.opacity(0.92)).frame(width: hub, height: hub)
                .shadow(color: Theme.coral.opacity(0.15), radius: 12)
            switch model.phase {
            case .choosing:
                VStack(spacing: 6) {
                    Text(hoverTitle ?? (model.dropMode && !model.actions.isEmpty ? "Drop on an action" : model.summary))
                        .font(Theme.font(14, .semibold))
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(width: hub - 28)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.12), value: model.hovered)
                    if model.actions.isEmpty {
                        Text("Nothing fits these files").font(.caption).foregroundStyle(.secondary)
                    } else if model.groups.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(model.groups, id: \.self) { g in
                                Button { model.select(g) } label: {
                                    Text(g.label).font(Theme.font(10, .semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Capsule().fill(g == model.group ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.tint)))
                                        .foregroundStyle(g == model.group ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                                // Spring-loaded: hovering a drag over a group switches to it.
                                .onDrop(of: [.fileURL], isTargeted: Binding(get: { false }, set: { if $0 { model.select(g) } })) { _ in false }
                            }
                        }
                    }
                    if model.pages > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<model.pages, id: \.self) { i in
                                Capsule().fill(i == model.page ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                                    .frame(width: i == model.page ? 12 : 5, height: 5)
                            }
                        }
                        .padding(.top, 2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.page)
                    }
                }
            case let .running(action, done, total):
                VStack(spacing: 8) {
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0).progressViewStyle(.circular)
                        .tint(Theme.tangerine)
                    Text(action.title).font(Theme.font(14, .semibold))
                    if total > 1 { Text("\(done) of \(total)").font(.caption).foregroundStyle(.secondary) }
                }
            case let .finished(_, result):
                VStack(spacing: 6) {
                    Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(result.failures.isEmpty ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.coral))
                    Text(result.failures.isEmpty ? "Done" : "\(result.failures.count) failed")
                        .font(Theme.font(14, .semibold))
                    if let first = result.failures.first {
                        Text(first).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            .multilineTextAlignment(.center).frame(width: hub - 30)
                    }
                    if !result.outputs.isEmpty {
                        Button("Show in Finder") { model.reveal(result) }.buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
    }

    private func setHovered(_ action: Action, _ on: Bool) {
        model.hovered = on ? action.id : (model.hovered == action.id ? nil : model.hovered)
    }

    private var hoverTitle: String? {
        model.hovered.flatMap { id in model.actions.first { $0.id == id } }.map { action in
            action.group == .convert ? "Convert to \(action.title)" : action.title
        }
    }
}

/// Rotates and fades a page of bubbles in or out around the hub.
private struct Turn: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle)).opacity(opacity)
    }
}

/// An annular wedge centred on `center` degrees; animatable so it glides between bubbles.
struct Petal: Shape {
    var center: Double
    var span: Double
    var inner: CGFloat
    var outer: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(center, span) }
        set { center = newValue.first; span = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: c, radius: outer, startAngle: .degrees(center - span / 2), endAngle: .degrees(center + span / 2), clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: .degrees(center + span / 2), endAngle: .degrees(center - span / 2), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct WheelButton: View {
    let action: Action
    let hovered: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                Image(systemName: action.symbol).font(.system(size: 15))
                Text(action.title).font(Theme.font(9, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 58, height: 58)
            .background(Circle().fill(hovered ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface)))
            .shadow(color: hovered ? Theme.coral.opacity(0.4) : .black.opacity(0.08), radius: hovered ? 10 : 4, y: 2)
            .foregroundStyle(hovered ? .white : .primary)
            .scaleEffect(hovered ? 1.14 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hovered)
        }
        .buttonStyle(.plain)
        .help(action.title)
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
