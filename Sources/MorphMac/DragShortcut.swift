import AppKit
import Carbon.HIToolbox
import MorphCore

/// The keys that summon one wheel while files are being dragged: any combination of ⌘ ⌥ ⌃ ⇧, or Tab alone.
/// Bit values follow the order modifiers are read in (⌘ 1, ⌥ 2, ⌃ 4, ⇧ 8); Tab is 16. No keys means off.
struct DragKeys: OptionSet, Hashable {
    let rawValue: Int

    static let command = DragKeys(rawValue: 1)
    static let option = DragKeys(rawValue: 2)
    static let control = DragKeys(rawValue: 4)
    static let shift = DragKeys(rawValue: 8)
    static let tab = DragKeys(rawValue: 16)
    static let off: DragKeys = []

    /// Apple's menu order, used for symbols and names.
    private static let modifiers: [(DragKeys, symbol: String, name: String)] = [
        (.control, "⌃", "Control"), (.option, "⌥", "Option"), (.shift, "⇧", "Shift"), (.command, "⌘", "Command"),
    ]

    /// Single keys first, in the order people reach for them.
    static let singles: [DragKeys] = [.shift, .command, .option, .control, .tab]

    /// Every two-, three- and four-modifier combination, fewest keys first.
    static let combinations: [DragKeys] = (1...15).map(DragKeys.init(rawValue:))
        .filter { $0.count > 1 }
        .sorted { ($0.count, $0.rawValue) < ($1.count, $1.rawValue) }

    var count: Int { rawValue.nonzeroBitCount }

    /// "⌃⇧", or "⇥" for Tab.
    var symbols: String {
        if self == .tab { return "⇥" }
        return Self.modifiers.filter { contains($0.0) }.map(\.symbol).joined()
    }

    var label: String {
        if isEmpty { return "Off" }
        if self == .tab { return "⇥ Tab" }
        let names = Self.modifiers.filter { contains($0.0) }.map(\.name)
        return count == 1 ? "\(symbols) \(names[0])" : symbols
    }

    /// What is held right now. Reading key state needs neither Accessibility nor Input Monitoring access.
    static var pressed: DragKeys {
        let system = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        let flags = NSEvent.modifierFlags.union(system)
        var keys: DragKeys = []
        if flags.contains(.command) { keys.insert(.command) }
        if flags.contains(.option) { keys.insert(.option) }
        if flags.contains(.control) { keys.insert(.control) }
        if flags.contains(.shift) { keys.insert(.shift) }
        if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Tab)) { keys.insert(.tab) }
        return keys
    }
}

/// Which wheel the keyboard asks for during one drag. A wheel is chosen the moment its exact keys go down and
/// stays chosen once they are released, so a tap is enough; pressing another wheel's keys switches to it, and
/// keys that match no wheel change nothing. Escape, or the end of the drag, clears the choice.
struct WheelShortcutState {
    private(set) var group: Action.Group?
    private var previous: DragKeys = []
    private var wasDragging = false

    mutating func update(keys: DragKeys, dragging: Bool, escape: Bool, match: (DragKeys) -> Action.Group?) {
        if dragging, !escape {
            // Only a key going down can choose; on the drag's first frame, keys already held count too.
            let newlyPressed = keys.subtracting(previous)
            if !wasDragging || !newlyPressed.isEmpty, let chosen = match(keys) { group = chosen }
        } else {
            group = nil
        }
        previous = keys
        wasDragging = dragging
    }
}

/// Watches for file drags in any app and turns the keyboard into wheel choices: opens the chosen wheel in drop
/// mode, switches it when another wheel's keys are tapped, closes it on Escape, and asks for it to go away
/// when the drag ends without a drop on the wheel.
@MainActor
final class DragShortcut {
    var onTrigger: ([URL], Action.Group) -> Void = { _, _ in }
    var onSwitch: (Action.Group) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onDragEnded: () -> Void = {}

    private var state = WheelShortcutState()
    /// The wheel on screen for this drag, if any.
    private var shown: Action.Group?

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
        state = WheelShortcutState()
        shown = nil
        fired = false
        timer?.invalidate()
        // Poll while the button is held: keys can go down at any point of the drag, even with the mouse still.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    private func mouseUp() {
        timer?.invalidate()
        timer = nil
        shown = nil
        // A drop on the wheel arrives just after mouse-up; give it a moment before tidying up.
        if fired { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.onDragEnded() } }
    }

    private func poll() {
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        let escape = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape))
        state.update(keys: .pressed, dragging: dragging, escape: escape, match: Preferences.shared.group(for:))
        guard dragging else { mouseUp(); return }

        switch (shown, state.group) {
        case let (nil, group?):
            // A changed drag pasteboard means a real drag started after the click; until then, keep the choice.
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragCountAtMouseDown else { return }
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return }
            shown = group
            fired = true
            onTrigger(urls, group)
        case let (current?, group?) where current != group:
            shown = group
            onSwitch(group)
        case (_?, nil):
            shown = nil
            onCancel()
        default:
            break
        }
    }
}
