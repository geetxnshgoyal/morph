using System.IO;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Morph.App;

/// Morph lives in the taskbar corner. While you drag files from File Explorer, tapping a wheel's keys opens that
/// wheel under the cursor; files also arrive from "Open in Morph", the tray panel and the command line.
public partial class App : Application
{
    SingleInstance? instance;
    Forms.NotifyIcon? tray;
    DragShortcut? dragShortcut;
    ShelfWindow? shelf;
    WheelWindow? wheel;
    WelcomeWindow? welcome;
    SettingsWindow? settings;
    readonly List<string> pending = [];
    DispatcherTimer? batch;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var args = e.Args;
        if (args.Length >= 2 && args[0] == "--snapshots")
        {
            Shutdown(Snapshots.Run(args[1]));
            return;
        }

        instance = new SingleInstance();
        if (!instance.IsFirst)
        {
            SingleInstance.Forward(args);
            Shutdown();
            return;
        }

        Theme.Start();
        DispatcherUnhandledException += (_, error) =>
        {
            error.Handled = true;
            Shell.Alert("Morph ran into a problem", error.Exception.GetBaseException().Message);
        };

        tray = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(Path.Combine(AppContext.BaseDirectory, "Assets", "Morph.ico"), Forms.SystemInformation.SmallIconSize),
            Text = "Morph",
            Visible = true,
            ContextMenuStrip = TrayMenu(),
        };
        tray.MouseClick += (_, click) => { if (click.Button == Forms.MouseButtons.Left) ToggleShelf(); };

        dragShortcut = new DragShortcut(Dispatcher)
        {
            // Tap a wheel's keys while dragging files: that wheel appears under the cursor to drop on.
            OnTrigger = group => ShowWheel([], dropMode: true, group),
            OnSwitch = group => { if (wheel is { Model.DropMode: true } w) w.Model.Select(group); },
            // Esc mid-drag: the wheel never has focus in drop mode, so it can't hear the key itself.
            OnCancel = CloseDropWheel,
            OnDragEnded = CloseDropWheel,
            // A press anywhere else closes the wheel. Deactivation can't be relied on: a wheel opened from a drag never
            // takes focus, and one opened for another launch's files may not be allowed to.
            OnPress = point => { if (wheel is { IsClosing: false } w && !w.Contains(point)) w.CloseAnimated(); },
        };
        dragShortcut.Start();
        instance.Listen((folder, forwarded) => Dispatcher.BeginInvoke(() => Handle(folder, forwarded, relaunch: true)));

        Handle(Environment.CurrentDirectory, args, relaunch: false);
    }

    void CloseDropWheel()
    {
        if (wheel is { Model.DropMode: true, Model.Phase: WheelPhase.Choosing } w) w.CloseAnimated();
    }

    /// Files open the wheel; a plain launch shows the welcome guide the first time and the tray panel after that,
    /// so starting Morph from the Start menu always shows where it lives. Launches at sign-in stay quiet.
    void Handle(string folder, IReadOnlyList<string> args, bool relaunch)
    {
        var files = args.Where(a => !a.StartsWith("--"))
            .Select(a => Path.GetFullPath(a, folder))
            .Where(p => File.Exists(p) || Directory.Exists(p))
            .ToList();
        if (files.Count > 0) { Queue(files); return; }
        if (args.Contains("--settings")) { ShowSettings(); return; }
        var quiet = args.Contains("--background") || (!relaunch && LaunchedAtSignIn());
        if (!Preferences.Shared.HasSeenWelcome && !quiet) ShowWelcome();
        else if (!quiet) ShowShelf();
    }

    static bool LaunchedAtSignIn()
    {
        if (!Shell.IsPackaged) return false;
        try { return global::Windows.ApplicationModel.AppInstance.GetActivatedEventArgs()?.Kind == global::Windows.ApplicationModel.Activation.ActivationKind.StartupTask; }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException) { return false; }
    }

    /// "Open in Morph" on several files starts Morph once per file; gather them into one wheel.
    void Queue(IEnumerable<string> files)
    {
        foreach (var file in files) if (!pending.Contains(file, StringComparer.OrdinalIgnoreCase)) pending.Add(file);
        batch ??= new DispatcherTimer(TimeSpan.FromMilliseconds(350), DispatcherPriority.Normal, (_, _) =>
        {
            batch!.Stop();
            var all = pending.ToList();
            pending.Clear();
            ShowWheel(all);
        }, Dispatcher);
        batch.Stop();
        batch.Start();
    }

    Forms.ContextMenuStrip TrayMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Morph", null, (_, _) => ShowShelf());
        menu.Items.Add("Choose Files…", null, (_, _) => { if (Ui.ChooseFiles() is { } files) ShowWheel(files); });
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettings());
        menu.Items.Add("Welcome Guide", null, (_, _) => ShowWelcome());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit Morph", null, (_, _) => Quit());
        return menu;
    }

    // MARK: Windows

    ShelfWindow Shelf => shelf ??= new ShelfWindow(files => ShowWheel(files), () => ShowSettings(), ShowWelcome, Quit);

    void ToggleShelf()
    {
        if (shelf is { IsVisible: true }) shelf.Hide(); else ShowShelf();
    }

    void ShowShelf() => Shelf.Present();

    public void ShowWelcome()
    {
        if (welcome is null)
        {
            welcome = new WelcomeWindow(files => ShowWheel(files), FinishWelcome);
            welcome.Closed += (_, _) => { Preferences.Shared.HasSeenWelcome = true; welcome = null; };
        }
        Present(welcome);
    }

    void FinishWelcome()
    {
        Preferences.Shared.HasSeenWelcome = true;
        welcome?.Close();
        // Show where Morph lives from now on.
        Shell.After(350, ShowShelf);
    }

    public void ShowSettings(SettingsWindow.Tab tab = SettingsWindow.Tab.General)
    {
        if (settings is null)
        {
            settings = new SettingsWindow(ShowWelcome, tab);
            settings.Closed += (_, _) => settings = null;
        }
        else settings.Show(tab);
        Present(settings);
    }

    static void Present(Window window)
    {
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Show();
        window.Activate();
    }

    /// `dropMode`: summoned mid-drag, so the wheel waits for a drop instead of a click and leaves focus alone.
    public void ShowWheel(IReadOnlyList<string> files, bool dropMode = false, ActionGroup? group = null)
    {
        if (files.Count == 0 && !dropMode) return;
        shelf?.Hide();
        wheel?.Close();
        var model = new WheelModel(files, dropMode, group);
        var window = new WheelWindow(model);
        window.Closed += (_, _) => { if (wheel == window) wheel = null; };
        wheel = window;
        window.Present();
    }

    void Quit()
    {
        if (tray is not null) { tray.Visible = false; tray.Dispose(); }
        dragShortcut?.Dispose();
        instance?.Dispose();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (tray is not null) tray.Visible = false;
        base.OnExit(e);
    }
}
