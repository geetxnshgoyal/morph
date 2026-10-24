using System.Diagnostics;
using System.Windows.Threading;

namespace Morph.App;

/// Watches for file drags and turns the keyboard into wheel choices: opens the chosen wheel in drop mode, switches
/// it when another wheel's keys are tapped, closes it on Escape, and asks for it to go away when the drag ends
/// without a drop on the wheel.
///
/// Windows has no shared drag pasteboard to read, so a drag counts once the left button is held and the pointer has
/// moved past the system's drag distance, either from File Explorer or the desktop, or with the shell's drag image
/// showing (which apps that drag files draw). The wheel learns which files they are when the drag reaches it.
public sealed class DragShortcut : IDisposable
{
    public Action<ActionGroup> OnTrigger = _ => { };
    public Action<ActionGroup> OnSwitch = _ => { };
    public Action OnCancel = () => { };
    public Action OnDragEnded = () => { };
    /// Any left-button press, anywhere: a drop-mode wheel closes when the press is somewhere else.
    public Action<Native.POINT> OnPress = _ => { };

    readonly Dispatcher dispatcher;
    readonly DispatcherTimer timer;
    readonly WheelShortcutState state = new();
    Thread? hookThread;
    uint hookThreadId;
    // Kept in a field: the hook only holds a function pointer, and a collected delegate would crash.
    Native.HookProc? hookProc;

    ActionGroup? shown;
    bool fired, pressed, moved, fromShell, inMoveSize;
    Native.POINT start;

    static readonly int ownProcess = Environment.ProcessId;

    public DragShortcut(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        // Polls only while the button is held: keys can go down at any point of the drag, even with the mouse still.
        timer = new DispatcherTimer(TimeSpan.FromMilliseconds(1000.0 / 60), DispatcherPriority.Input, (_, _) => Poll(), dispatcher);
        timer.Stop();
    }

    public void Start()
    {
        if (hookThread is not null) return;
        // The hook lives on its own thread with its own message loop, so a busy UI thread never delays mouse input
        // (Windows drops low-level hooks that answer too slowly).
        hookThread = new Thread(HookLoop) { IsBackground = true, Name = "Morph drag watcher" };
        hookThread.Start();
    }

    void HookLoop()
    {
        hookThreadId = Native.GetCurrentThreadId();
        hookProc = (code, wParam, lParam) =>
        {
            if (code >= 0)
            {
                var message = (int)wParam;
                if (message == Native.WM_LBUTTONDOWN) dispatcher.BeginInvoke(MouseDown);
                else if (message == Native.WM_LBUTTONUP) dispatcher.BeginInvoke(MouseUp);
            }
            return Native.CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
        };
        var hook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, hookProc, Native.GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero) return;
        while (Native.GetMessage(out _, IntPtr.Zero, 0, 0) > 0) { }
        Native.UnhookWindowsHookEx(hook);
    }

    public void Dispose()
    {
        timer.Stop();
        if (hookThreadId != 0) Native.PostThreadMessage(hookThreadId, Native.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
    }

    void MouseDown()
    {
        Native.GetCursorPos(out start);
        pressed = true;
        moved = false;
        shown = null;
        fired = false;
        (fromShell, inMoveSize) = Inspect(start);
        OnPress(start);
        state.Update(DragKeys.Off, false, false, _ => null);
        timer.Start();
    }

    void MouseUp()
    {
        if (!pressed) return;
        pressed = false;
        timer.Stop();
        state.Update(DragKeys.Off, false, false, _ => null);
        shown = null;
        // A drop on the wheel arrives around mouse-up; give it a moment before tidying up.
        if (fired) Shell.After(250, () => OnDragEnded());
    }

    /// Whether the press landed in File Explorer or on the desktop, and whether it started moving or sizing a
    /// window (a title bar drag, which never carries files).
    static (bool Shell, bool MoveSize) Inspect(Native.POINT point)
    {
        var root = Native.GetAncestor(Native.WindowFromPoint(point), Native.GA_ROOT);
        if (root == IntPtr.Zero) return (false, false);
        var thread = Native.GetWindowThreadProcessId(root, out var pid);
        if (pid == ownProcess) return (false, false);
        bool shell;
        try
        {
            using var process = Process.GetProcessById((int)pid);
            shell = string.Equals(process.ProcessName, "explorer", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { shell = false; }
        var info = new Native.GUITHREADINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.GUITHREADINFO>() };
        var moveSize = Native.GetGUIThreadInfo(thread, ref info) && (info.flags & Native.GUI_INMOVESIZE) != 0;
        return (shell, moveSize);
    }

    /// The shell's drag image window, shown while files (or anything else with a drag image) are being dragged.
    static bool DragImageShowing()
    {
        var window = Native.FindWindow("SysDragImage", null);
        return window != IntPtr.Zero && Native.IsWindowVisible(window);
    }

    static DragKeys Pressed()
    {
        var keys = DragKeys.Off;
        if (Native.IsDown(Native.VK_CONTROL)) keys |= DragKeys.Ctrl;
        if (Native.IsDown(Native.VK_MENU)) keys |= DragKeys.Alt;
        if (Native.IsDown(Native.VK_SHIFT)) keys |= DragKeys.Shift;
        if (Native.IsDown(Native.VK_LWIN) || Native.IsDown(Native.VK_RWIN)) keys |= DragKeys.Win;
        if (Native.IsDown(Native.VK_TAB)) keys |= DragKeys.Tab;
        return keys;
    }

    void Poll()
    {
        var dragging = Native.IsDown(Native.VK_LBUTTON);
        if (!dragging) { MouseUp(); return; }
        if (!moved)
        {
            Native.GetCursorPos(out var now);
            moved = Math.Abs(now.X - start.X) > Native.GetSystemMetrics(Native.SM_CXDRAG)
                 || Math.Abs(now.Y - start.Y) > Native.GetSystemMetrics(Native.SM_CYDRAG);
        }
        var escape = Native.IsDown(Native.VK_ESCAPE);
        state.Update(Pressed(), dragging, escape, Preferences.Shared.Group);

        switch (shown, state.Group)
        {
            case (null, { } group):
                if (!moved || inMoveSize || !(fromShell || DragImageShowing())) return;
                shown = group;
                fired = true;
                OnTrigger(group);
                break;
            case ({ } current, { } group) when current != group:
                shown = group;
                OnSwitch(group);
                break;
            case (not null, null):
                shown = null;
                OnCancel();
                break;
        }
    }
}
