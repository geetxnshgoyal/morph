using System.Windows;
using System.Windows.Controls;

namespace Morph.App;

/// Setup rows shared by the welcome guide and Settings.
public static class Rows
{
    public static UIElement Login()
    {
        var problem = Ui.Text("", "Detail").Margin(14, 6, 14, 0);
        problem.SetResourceReference(TextBlock.ForegroundProperty, "Danger");
        problem.Visibility = Visibility.Collapsed;
        var toggle = Ui.Switch(false, async on =>
        {
            var message = await LoginItem.Set(on);
            problem.Text = message ?? "";
            problem.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
        }, "Open at login");
        toggle.Loaded += async (_, _) => toggle.IsChecked = await LoginItem.IsOn();
        return Ui.Stack(0, Ui.Row(Icons.Power, "Open at login", "Keep Morph in the taskbar corner, ready whenever you need it.", toggle), problem);
    }

    public static UIElement DragShortcuts()
    {
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.Children.Add(Ui.Bubble(Icons.Hand));
        var texts = Ui.Stack(2, Ui.Text("Drag shortcuts", "Heading"),
            Ui.Text("While dragging files from File Explorer or the desktop, tap a wheel's keys to open it under the cursor. Tap another wheel's keys to switch, or Esc to close.", "Detail"));
        texts.Margin = new Thickness(14, 0, 0, 0);
        Grid.SetColumn(texts, 1);
        header.Children.Add(texts);
        var stack = Ui.Stack(8, header);
        foreach (var group in WheelKeyMap.Wheels)
        {
            var line = new Grid { Margin = new Thickness(50, 8, 0, 0) };
            line.ColumnDefinitions.Add(new ColumnDefinition());
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var label = Ui.Text(group.Label(), "Body");
            label.VerticalAlignment = VerticalAlignment.Center;
            line.Children.Add(label);
            var picker = Ui.KeyPicker(group);
            Grid.SetColumn(picker, 1);
            line.Children.Add(picker);
            stack.Children.Add(line);
        }
        return Ui.Card(stack, 14);
    }

    public static UIElement Color() => Ui.Row(Icons.Palette, "Color",
        $"{Preferences.Shared.Palette.Name} for highlights and buttons. The app icon stays Teal Ink.", Ui.PalettePicker());

    public static UIElement Sounds() => Ui.Row(Icons.Volume, "Sounds",
        "A soft tick as you move around the wheel, and a chime when a job finishes.",
        Ui.Switch(Preferences.Shared.PlaySounds, on => Preferences.Shared.PlaySounds = on, "Sounds"));

    public static UIElement Reveal() => Ui.Row(Icons.Folder, "Show results in File Explorer",
        "Open a File Explorer window on the new files when a job finishes.",
        Ui.Switch(Preferences.Shared.RevealWhenDone, on => Preferences.Shared.RevealWhenDone = on, "Show results in File Explorer"));

    public static UIElement ContextMenu() => Ui.Row(Icons.OpenFile, "Right-click in File Explorer", Shell.ContextMenuHint);

    public static UIElement Tray() => Ui.Row(Icons.Pin, "Keep the icon in view",
        "Windows may tuck new icons behind the ^ arrow in the taskbar. Drag Morph out, or turn it on under Other system tray icons.",
        Ui.Soft("Taskbar Settings", () => Shell.Open("ms-settings:taskbar")));

    public static UIElement FFmpeg()
    {
        var installed = ExternalTool.FFmpeg is not null;
        if (installed)
            return Ui.Row(Icons.Check, "Extra formats unlocked", "ffmpeg found: MP3, WebM, FLAC, OGG and more are on.");
        var copy = Ui.Soft("Copy Command", () => { });
        copy.Click += (_, _) =>
        {
            Clipboard.SetText(ExternalTool.InstallHint);
            copy.Content = "Copied! Paste it in Terminal";
        };
        return Ui.Row(Icons.Video, "Extra formats (optional)",
            $"Install ffmpeg for MP3, WebM, FLAC and more: {ExternalTool.InstallHint}. Windows' own encoders cover MP4, M4A, WAV and FLAC without it.", copy);
    }

    public static UIElement Compression() => Ui.Card(Ui.Stack(10,
        Ui.Text("Compression", "Heading"),
        Ui.Pills(Enum.GetValues<CompressionLevel>(), Preferences.Shared.Compression, l => l.Label(), l => Preferences.Shared.Compression = l),
        Ui.Text(Preferences.Shared.Compression.Detail(), "Detail")));

    public static UIElement PhotoSize(Window owner)
    {
        var prefs = Preferences.Shared;
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Bubble(Icons.Compress));
        var detail = prefs.PhotoSize is { } size
            ? $"Resize makes photos exactly {size.Label} as a JPG, cropped to fill, and under your size limit if one is set. For passport, visa and exam forms."
            : "Pick the exact size a form asks for, like 600 × 600, and Resize makes it.";
        var texts = Ui.Stack(2, Ui.Text("Photo size", "Heading"), Ui.Text(detail, "Detail"));
        texts.Margin = new Thickness(14, 0, 8, 0);
        texts.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        var picker = Ui.PhotoSizePicker(owner);
        Grid.SetColumn(picker, 2);
        grid.Children.Add(picker);
        if (prefs.PhotoSize is null) return Ui.Card(grid, 14);
        // Saved when the box loses focus, so the page doesn't redraw under the typing.
        var caption = new TextBox { Text = prefs.PhotoCaption, FontSize = 13, Margin = new Thickness(0, 12, 0, 0) };
        caption.LostFocus += (_, _) => { if (caption.Text != prefs.PhotoCaption) prefs.PhotoCaption = caption.Text; };
        return Ui.Card(Ui.Stack(0, grid, Ui.Text("Name to print below the photo, with the date it was taken (optional, for exam forms)", "Caption").Margin(0, 12, 0, 0), caption), 14);
    }

    public static UIElement SizeLimit(Window owner, string detail)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Bubble(Icons.Compress));
        var texts = Ui.Stack(2, Ui.Text("Size limit", "Heading"), Ui.Text(detail, "Detail"));
        texts.Margin = new Thickness(14, 0, 8, 0);
        texts.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        var picker = Ui.SizeLimitPicker(owner);
        Grid.SetColumn(picker, 2);
        grid.Children.Add(picker);
        return Ui.Card(grid, 14);
    }
}
