using System.Windows;
using System.Windows.Controls;

namespace Morph.App;

/// Settings: General (login, drag shortcuts, color, sounds), Output (where results go, compression, size limit)
/// and Tools (ffmpeg, the right-click menu, the tray icon).
public sealed class SettingsWindow : Window
{
    public enum Tab { General, Output, Tools }

    Tab tab;
    readonly ScrollViewer scroll = new() { Style = (Style)Application.Current.FindResource("PageScroll") };
    readonly ContentControl tabs = new() { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 20, 0, 14), Focusable = false };
    readonly Action onWelcome;

    public SettingsWindow(Action onWelcome, Tab start = Tab.General)
    {
        this.onWelcome = onWelcome;
        tab = start;
        Title = "Morph Settings";
        Width = 580;
        Height = 560;
        MinHeight = 400;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = (System.Windows.Media.FontFamily)FindResource("UiFont");
        this.Brush(BackgroundProperty, "Canvas");
        var dock = new DockPanel();
        DockPanel.SetDock(tabs, Dock.Top);
        dock.Children.Add(tabs);
        dock.Children.Add(scroll);
        Content = dock;
        Build();

        // Rebuilt on any change so labels such as the color name and the size limit stay current.
        Preferences.Shared.PropertyChanged += Changed;
        Theme.Changed += Build;
        Activated += (_, _) => Build();
        Closed += (_, _) => { Preferences.Shared.PropertyChanged -= Changed; Theme.Changed -= Build; };
        SourceInitialized += (_, _) => Theme.DarkTitleBar(this);
    }

    void Changed(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(Build);

    public void Show(Tab start)
    {
        tab = start;
        Build();
    }

    void Build()
    {
        tabs.Content = Ui.Pills(Enum.GetValues<Tab>(), tab, t => t.ToString(), t => { tab = t; Dispatcher.BeginInvoke(Build); });
        var offset = scroll.VerticalOffset;
        var page = tab switch
        {
            Tab.General => General(),
            Tab.Output => Output(),
            _ => Tools(),
        };
        page.Margin = new Thickness(24, 0, 24, 24);
        scroll.Content = page;
        scroll.ScrollToVerticalOffset(offset);
    }

    StackPanel General()
    {
        var footer = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
        footer.Children.Add(Ui.Soft("Show Welcome Guide", onWelcome));
        var about = Ui.Text($"Morph {Shell.Version} · Everything stays on your PC", "Caption");
        about.HorizontalAlignment = HorizontalAlignment.Right;
        about.VerticalAlignment = VerticalAlignment.Center;
        footer.Children.Add(about);
        return Ui.Stack(10, Rows.Login(), Rows.DragShortcuts(), Rows.Color(), Rows.Sounds(), Rows.Reveal(), footer);
    }

    StackPanel Output()
    {
        var prefs = Preferences.Shared;
        var group = Guid.NewGuid().ToString("N");
        RadioButton Choice(string text, bool selected, Action pick)
        {
            var choice = new RadioButton { Content = text, IsChecked = selected, GroupName = group, Margin = new Thickness(0, 10, 0, 0), Style = (Style)FindResource("Choice") };
            choice.Click += (_, _) => pick();
            return choice;
        }
        var folder = prefs.OutputFolder;
        var save = Ui.Stack(0,
            Ui.Text("Save results", "Heading"),
            Choice("Next to the original", folder is null, () => prefs.OutputFolder = null),
            Choice(folder is null ? "In a folder I choose…" : $"In {System.IO.Path.GetFileName(System.IO.Path.TrimEndingDirectorySeparator(folder))}", folder is not null, ChooseFolder),
            folder is null ? null : Ui.Text(folder, "Caption").Margin(26, 2, 0, 0),
            Ui.Text("Originals are never overwritten.", "Caption").Margin(0, 10, 0, 0));
        return Ui.Stack(10, Ui.Card(save), Rows.Compression(), Rows.SizeLimit(this, SizeLimit.Detail(prefs.SizeLimit)), Rows.PhotoSize(this));
    }

    void ChooseFolder()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = "Save Morph's results in" };
        if (dialog.ShowDialog(this) == true) Preferences.Shared.OutputFolder = dialog.FolderName;
        else Build();
    }

    static StackPanel Tools() => Ui.Stack(10, Rows.FFmpeg(), Rows.ContextMenu(), Rows.Tray());
}
