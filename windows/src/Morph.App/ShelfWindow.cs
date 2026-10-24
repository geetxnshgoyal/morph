using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace Morph.App;

/// The panel the tray icon opens: a drop zone, Choose Files, recent jobs with Show and Undo, and the way to
/// Settings. It hides when it loses focus, except while the button is held: that click may be the start of a
/// drag from File Explorer onto the drop zone, so it waits for the release to decide.
public sealed class ShelfWindow : Window
{
    const double PanelWidth = 330;
    readonly Action<string[]> onFiles;
    readonly Action onSettings;
    readonly Action onWelcome;
    readonly Action onQuit;
    readonly Border panel;
    readonly DispatcherTimer release;
    DateTime droppedAt = DateTime.MinValue;

    public ShelfWindow(Action<string[]> onFiles, Action onSettings, Action onWelcome, Action onQuit)
    {
        this.onFiles = onFiles;
        this.onSettings = onSettings;
        this.onWelcome = onWelcome;
        this.onQuit = onQuit;
        Title = "Morph";
        Width = PanelWidth + 24;
        SizeToContent = SizeToContent.Height;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        FontFamily = (FontFamily)FindResource("UiFont");
        panel = new Border
        {
            Margin = new Thickness(12), Padding = new Thickness(16), CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 4, Direction = 270, Opacity = 0.22 },
        };
        panel.SetResourceReference(Border.BackgroundProperty, "Canvas");
        panel.SetResourceReference(Border.BorderBrushProperty, "Stroke");
        Content = panel;

        release = new DispatcherTimer(TimeSpan.FromMilliseconds(50), DispatcherPriority.Input, (_, _) => WaitForRelease(), Dispatcher);
        release.Stop();
        Deactivated += (_, _) =>
        {
            if (Native.IsDown(Native.VK_LBUTTON)) release.Start(); else Hide();
        };
        PreviewKeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) Hide(); };
        History.Shared.Changed += () => Dispatcher.BeginInvoke(() => { if (IsVisible) Build(); });
        Theme.Changed += () => { if (IsVisible) Build(); };
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var style = (long)Native.GetWindowLongPtr(handle, Native.GWL_EXSTYLE) | Native.WS_EX_TOOLWINDOW;
            Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE, (IntPtr)style);
        };
    }

    void WaitForRelease()
    {
        if (Native.IsDown(Native.VK_LBUTTON)) return;
        release.Stop();
        // A drop on the zone opens the wheel, which hides the shelf itself; anything else ends here.
        if (!IsActive && (DateTime.UtcNow - droppedAt).TotalMilliseconds > 400) Hide();
    }

    /// Opens above the taskbar corner nearest the cursor (where the tray icon is).
    public void Present()
    {
        Build();
        Native.GetCursorPos(out var cursor);
        var work = Native.WorkAreaAt(cursor);
        var scale = Native.ScaleAt(cursor);
        Show();
        UpdateLayout();
        var handle = new WindowInteropHelper(this).Handle;
        int width = (int)(ActualWidth * scale), height = (int)(ActualHeight * scale);
        // The taskbar is usually at the bottom; keep the panel inside the work area wherever it is.
        var x = Math.Clamp(cursor.X - width / 2, work.Left, work.Right - width);
        var y = cursor.Y > work.Bottom ? work.Bottom - height : cursor.Y < work.Top ? work.Top : Math.Clamp(cursor.Y - height, work.Top, work.Bottom - height);
        if (cursor.X > work.Right) x = work.Right - width;
        if (cursor.X < work.Left) x = work.Left;
        Native.SetWindowPos(handle, IntPtr.Zero, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOZORDER);
        Activate();
        Native.SetForegroundWindow(handle);
    }

    public void Build()
    {
        var header = new DockPanel();
        var menu = new ContextMenu();
        void Add(string text, Action act) { var item = new MenuItem { Header = text }; item.Click += (_, _) => { Hide(); act(); }; menu.Items.Add(item); }
        Add("Settings…", onSettings);
        Add("Welcome Guide", onWelcome);
        menu.Items.Add(new Separator());
        Add("Quit Morph", onQuit);
        var gear = Ui.Plain(Ui.Glyph(Icons.Settings, 15, "Secondary"), () => { }, "Settings and more");
        gear.ContextMenu = menu;
        menu.PlacementTarget = gear;
        gear.Click += (_, _) => menu.IsOpen = true;
        DockPanel.SetDock(gear, Dock.Right);
        header.Children.Add(gear);
        var title = Ui.Text("Morph", "Heading");
        title.FontSize = 17;
        title.FontWeight = FontWeights.Bold;
        title.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(title);

        var choose = Ui.Soft("Choose Files…", () => { if (Ui.ChooseFiles() is { } files) Open(files); });
        choose.HorizontalAlignment = HorizontalAlignment.Center;
        var dropLabel = Ui.Text("Drop files here", "Heading");
        dropLabel.FontSize = 15;
        dropLabel.HorizontalAlignment = HorizontalAlignment.Center;
        var zoneContent = Ui.Stack(8, Ui.Glyph(Icons.Download, 26), dropLabel, choose);
        zoneContent.VerticalAlignment = VerticalAlignment.Center;
        var zone = Ui.DropZone(zoneContent, files => { droppedAt = DateTime.UtcNow; Open(files); }, 124);

        var stack = Ui.Stack(14, header, zone);
        var recent = History.Shared.Entries.TakeLast(5).Reverse().ToList();
        if (recent.Count == 0)
        {
            var tip = new DockPanel();
            tip.Children.Add(Ui.Glyph(Icons.Hand, 13, "Secondary").Margin(0, 1, 8, 0));
            tip.Children.Add(Ui.Text("Tip: drag files from File Explorer and tap Shift to open the wheel right there.", "Detail"));
            stack.Children.Add(tip.Margin(0, 14, 0, 0));
        }
        else
        {
            var list = Ui.Stack(4, Ui.Text("Recent", "Caption").Margin(4, 0, 0, 0));
            foreach (var entry in recent) list.Children.Add(Row(entry).Margin(0, 4, 0, 0));
            stack.Children.Add(list.Margin(0, 14, 0, 0));
        }
        if (ExternalTool.FFmpeg is null)
        {
            var unlock = Ui.Plain(Ui.Text("Unlock MP3, WebM and more", "Detail").Brush(TextBlock.ForegroundProperty, "BrandText"), () => { Hide(); onSettings(); });
            unlock.HorizontalAlignment = HorizontalAlignment.Left;
            unlock.Padding = new Thickness(4, 2, 4, 2);
            stack.Children.Add(unlock.Margin(0, 10, 0, 0));
        }
        panel.Child = stack;
    }

    void Open(string[] files)
    {
        Hide();
        onFiles(files);
    }

    Border Row(HistoryEntry entry)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Bubble(entry.Undone ? Icons.Undo : entry.Outputs.Count == 0 ? Icons.Warning : Icons.Check, 26));
        var title = Ui.Text(entry.Title, "Body");
        title.FontWeight = FontWeights.Medium;
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        title.TextWrapping = TextWrapping.NoWrap;
        if (entry.Undone) title.TextDecorations = TextDecorations.Strikethrough;
        var texts = Ui.Stack(0, title, Ui.Text($"{entry.Inputs.Count} in → {entry.Outputs.Count} out", "Caption"));
        texts.Margin = new Thickness(10, 0, 4, 0);
        texts.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        if (entry.Outputs.Count > 0 && !entry.Undone)
        {
            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            actions.Children.Add(Ui.Plain(Ui.Glyph(Icons.Folder, 13, "Secondary"), () => Shell.Reveal(entry.Outputs), "Show in File Explorer"));
            actions.Children.Add(Ui.Plain(Ui.Glyph(Icons.Undo, 13, "Secondary"), () =>
            {
                try { History.Shared.Undo(entry.Id); } catch (MorphException e) { Shell.Alert("Couldn't undo that", e.Message); }
                Build();
            }, "Move results to the Recycle Bin"));
            Grid.SetColumn(actions, 2);
            grid.Children.Add(actions);
        }
        var row = new Border { Child = grid, CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 6, 4, 6) };
        row.SetResourceReference(Border.BackgroundProperty, "Surface");
        return row;
    }
}
