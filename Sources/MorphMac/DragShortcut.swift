import AppKit
import Carbon.HIToolbox
import MorphCore

/// A key that summons a wheel while files are being dragged anywhere on the Mac.
enum DragKey: String, CaseIterable {
    case shift, command, option, control, tab, off

    var label: String {
        switch self {
        case .shift: "⇧ Shift"
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .tab: "⇥ Tab"
        case .off: "Off"
        }
    }

    /// Reads live keyboard state; neither call needs Accessibility or Input Monitoring access.
    var isDown: Bool {
        let flags = NSEvent.modifierFlags
        switch self {
        case .shift: return flags.contains(.shift)
        case .command: return flags.contains(.command)
        case .option: return flags.contains(.option)
        case .control: return flags.contains(.control)
        case .tab: return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Tab))
        case .off: return false
        }
    }
}

/// Watches for file drags in any app. Each wheel (Convert, Tools, Recipes) has its own key: pressing one
/// mid-drag opens that wheel in drop mode, and tapping another switches to it. When the drag ends without
/// a drop on the wheel, asks for it to go away.
@MainActor
final class DragShortcut {
    var onTrigger: ([URL], Action.Group) -> Void = { _, _ in }
    var onSwitch: (Action.Group) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private static let order: [Action.Group] = [.convert, .tool, .recipe]
    private var held: Set<Action.Group> = []

    private var monitors: [Any] = []
    private var timer: Timer?
    private var dragCountAtMouseDown = 0
    private var fired = false

    func start() {
        guard monitors.isEmpty else { return }
        // Global mouse monitors only see other apps' events, which is exactly where Finder drags happen.
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
            MainActor.assumeIsolated { self.mouseDown() }
        }) { monitors.append(down) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            MainActor.assumeIsolated { self.mouseUp() }
        }) { monitors.append(up) }
    }

    private func mouseDown() {
        dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        fired = false
        held = []
        timer?.invalidate()
        // Poll while the button is held: the key can go down at any point of the drag, even with the mouse still.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    private func mouseUp() {
        timer?.invalidate()
        timer = nil
        // A drop on the wheel arrives just after mouse-up; give it a moment before tidying up.
        if fired { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.onDragEnded() } }
    }

    private func poll() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { mouseUp(); return }
        let prefs = Preferences.shared
        let down = Set(Self.order.filter { prefs.dragKey(for: $0).isDown })
        let newlyPressed = Self.order.first { down.contains($0) && !held.contains($0) }
        held = down
        if fired {
            if let group = newlyPressed { onSwitch(group) }
            return
        }
        guard let group = newlyPressed ?? Self.order.first(where: down.contains) else { return }
        // A changed drag pasteboard means a real drag started after the click.
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragCountAtMouseDown else { return }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        fired = true
        onTrigger(urls, group)
    }
}
