using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Morph.App;

/// Building blocks shared by Settings, the welcome guide and the tray panel, matching the Mac app's: soft cards,
/// tinted icon bubbles, pills and switches. Colours are resource references, so they follow the palette live.
public static class Ui
{
    public static T Brush<T>(this T element, DependencyProperty property, string key) where T : FrameworkElement
    {
        element.SetResourceReference(property, key);
        return element;
    }

    public static T Margin<T>(this T element, double left, double top, double right, double bottom) where T : FrameworkElement
    {
        element.Margin = new Thickness(left, top, right, bottom);
        return element;
    }

    public static TextBlock Text(string text, string style = "Body") => new() { Text = text, Style = (Style)Application.Current.FindResource(style) };

    public static TextBlock Glyph(string glyph, double size = 16, string brush = "BrandText")
    {
        var block = new TextBlock { Text = glyph, FontSize = size, Style = (Style)Application.Current.FindResource("Glyph") };
        return block.Brush(TextBlock.ForegroundProperty, brush);
    }

    /// Round tinted badge holding an icon.
    public static Border Bubble(string glyph, double size = 36) => new Border
    {
        Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), VerticalAlignment = VerticalAlignment.Center,
        Child = Glyph(glyph, size * 0.42),
    }.Brush(Border.BackgroundProperty, "Tint");

    public static Border Card(UIElement child, double padding = 16) => new()
    {
        Child = child, Style = (Style)Application.Current.FindResource("Card"), Padding = new Thickness(padding),
    };

    /// Icon, title, explanation and a trailing control, on a card.
    public static Border Row(string glyph, string title, string detail, UIElement? trailing = null)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Bubble(glyph));
        var texts = new StackPanel { Margin = new Thickness(14, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(Text(title, "Heading"));
        texts.Children.Add(Text(detail, "Detail").Margin(0, 2, 0, 0));
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        if (trailing is FrameworkElement element)
        {
            element.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(element, 2);
            grid.Children.Add(element);
        }
        return Card(grid, 14);
    }

    public static StackPanel Stack(double spacing, params UIElement?[] children)
    {
        var stack = new StackPanel();
        foreach (var child in children)
        {
            if (child is null) continue;
            if (stack.Children.Count > 0 && child is FrameworkElement f && f.Margin == default) f.Margin = new Thickness(0, spacing, 0, 0);
            stack.Children.Add(child);
        }
        return stack;
    }

    public static Button Soft(string text, Action onClick)
    {
        var button = new Button { Content = text, Style = (Style)Application.Current.FindResource("SoftButton") };
        button.Click += (_, _) => onClick();
        return button;
    }

    public static Button Primary(string text, Action onClick)
    {
        var button = new Button { Content = text, Style = (Style)Application.Current.FindResource("BubbleButton"), IsDefault = true };
        button.Click += (_, _) => onClick();
        return button;
    }

    public static Button Plain(object content, Action onClick, string? tip = null)
    {
        var button = new Button { Content = content, Style = (Style)Application.Current.FindResource("PlainButton"), ToolTip = tip };
        button.Click += (_, _) => onClick();
        return button;
    }

    public static CheckBox Switch(bool on, Action<bool> changed, string name)
    {
        var box = new CheckBox { IsChecked = on, Style = (Style)Application.Current.FindResource("Switch") };
        System.Windows.Automation.AutomationProperties.SetName(box, name);
        box.Click += (_, _) => changed(box.IsChecked == true);
        return box;
    }

    /// Bubbly replacement for a segmented control: the selection is an accent pill.
    public static Border Pills<T>(IEnumerable<T> options, T selected, Func<T, string> label, Action<T> choose)
    {
        var group = Guid.NewGuid().ToString("N");
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var option in options)
        {
            var pill = new RadioButton { Content = label(option), GroupName = group, IsChecked = Equals(option, selected), Style = (Style)Application.Current.FindResource("Pill") };
            pill.Checked += (_, _) => choose(option);
            row.Children.Add(pill);
        }
        return new Border { Child = row, Style = (Style)Application.Current.FindResource("PillTrack") };
    }

    /// One round swatch per palette; the chosen one wears a ring.
    public static StackPanel PalettePicker()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var current = Preferences.Shared.Palette;
        var group = Guid.NewGuid().ToString("N");
        foreach (var palette in Palette.All)
        {
            var swatch = new RadioButton
            {
                GroupName = group, IsChecked = palette == current, Style = (Style)Application.Current.FindResource("Swatch"),
                Background = new SolidColorBrush(palette.Fill(Theme.IsDark)), Foreground = new SolidColorBrush(palette.OnFill),
                BorderBrush = new SolidColorBrush(palette.Text(Theme.IsDark)), ToolTip = palette.Name,
            };
            System.Windows.Automation.AutomationProperties.SetName(swatch, palette.Name);
            swatch.Checked += (_, _) => Preferences.Shared.Palette = palette;
            row.Children.Add(swatch);
        }
        return row;
    }

    static Button MenuButton(string text, ContextMenu menu)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        content.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        content.Children.Add(Glyph(Icons.Chevron, 9).Margin(6, 1, 0, 0));
        var button = new Button { Content = content, Style = (Style)Application.Current.FindResource("SoftButton"), ContextMenu = menu };
        menu.PlacementTarget = button;
        menu.Placement = PlacementMode.Bottom;
        button.Click += (_, _) => menu.IsOpen = true;
        return button;
    }

    static MenuItem Item(string header, bool chosen, Action pick)
    {
        var item = new MenuItem { Header = header, IsCheckable = true, IsChecked = chosen };
        item.Click += (_, _) => pick();
        return item;
    }

    /// A pill that opens a menu of keys: single keys, modifier combinations, or off.
    public static Button KeyPicker(ActionGroup group)
    {
        var keys = Preferences.Shared.DragKeys(group);
        void Pick(DragKeys k) => Preferences.Shared.SetDragKeys(group, k);
        var menu = new ContextMenu();
        foreach (var single in DragKeyInfo.Singles) menu.Items.Add(Item(single.Label(), single == keys, () => Pick(single)));
        var combinations = new MenuItem { Header = "Combinations" };
        foreach (var combo in DragKeyInfo.Combinations) combinations.Items.Add(Item(combo.Label(), combo == keys, () => Pick(combo)));
        menu.Items.Add(combinations);
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Off", keys == DragKeys.Off, () => Pick(DragKeys.Off)));
        var button = MenuButton(keys.Label(), menu);
        System.Windows.Automation.AutomationProperties.SetName(button, $"{group.Label()} keys");
        return button;
    }

    /// Picks Compress's size limit: none, a common upload-form size, or any size typed in ("300 KB", "1.5 MB").
    public static Button SizeLimitPicker(Window owner)
    {
        var limit = Preferences.Shared.SizeLimit;
        void Pick(long bytes) => Preferences.Shared.SizeLimit = bytes;
        var menu = new ContextMenu();
        menu.Items.Add(Item("No limit", limit <= 0, () => Pick(0)));
        foreach (var preset in SizeLimit.Presets) menu.Items.Add(Item(SizeLimit.Label(preset), preset == limit, () => Pick(preset)));
        if (limit > 0 && !SizeLimit.Presets.Contains(limit)) menu.Items.Add(Item(SizeLimit.Label(limit), true, () => { }));
        menu.Items.Add(new Separator());
        var custom = new MenuItem { Header = "Custom size…" };
        custom.Click += (_, _) => { if (CustomSize.Ask(owner, limit) is long bytes) Pick(bytes); };
        menu.Items.Add(custom);
        var button = MenuButton(SizeLimit.Label(limit), menu);
        System.Windows.Automation.AutomationProperties.SetName(button, "Size limit");
        return button;
    }

    /// Picks Resize's exact size: off, a preset (passport, exams, signature, social), or any width × height typed in.
    public static Button PhotoSizePicker(Window owner)
    {
        var size = Preferences.Shared.PhotoSize;
        void Pick(PixelSize? value) => Preferences.Shared.PhotoSize = value;
        var menu = new ContextMenu();
        menu.Items.Add(Item("Off", size is null, () => Pick(null)));
        foreach (var (group, items) in PixelSize.Presets)
        {
            menu.Items.Add(new Separator());
            menu.Items.Add(new MenuItem { Header = group, IsEnabled = false });
            foreach (var (name, preset) in items) menu.Items.Add(Item($"{name} · {preset.Label}", preset == size, () => Pick(preset)));
        }
        menu.Items.Add(new Separator());
        var custom = new MenuItem { Header = "Custom size…" };
        custom.Click += (_, _) => { if (CustomPhotoSize.Ask(owner, size) is { } chosen) Pick(chosen); };
        menu.Items.Add(custom);
        var button = MenuButton(size?.Label ?? "Off", menu);
        System.Windows.Automation.AutomationProperties.SetName(button, "Photo size");
        return button;
    }

    /// Dashed bubble that takes dropped files.
    public static Border DropZone(UIElement content, Action<string[]> onFiles, double height)
    {
        var dash = new Rectangle { RadiusX = 16, RadiusY = 16, StrokeThickness = 2, StrokeDashArray = [3.5, 3] };
        dash.SetResourceReference(Shape.StrokeProperty, "Tertiary");
        var grid = new Grid { Height = height };
        grid.Children.Add(dash);
        grid.Children.Add(content);
        var zone = new Border { Child = grid, CornerRadius = new CornerRadius(16), AllowDrop = true }.Brush(Border.BackgroundProperty, "Surface");
        zone.DragEnter += (_, e) =>
        {
            var files = e.Data.GetDataPresent(DataFormats.FileDrop);
            e.Effects = files ? DragDropEffects.Copy : DragDropEffects.None;
            if (files) { zone.SetResourceReference(Border.BackgroundProperty, "Tint"); dash.SetResourceReference(Shape.StrokeProperty, "BrandText"); }
            e.Handled = true;
        };
        zone.DragOver += (_, e) => { e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
        void Reset() { zone.SetResourceReference(Border.BackgroundProperty, "Surface"); dash.SetResourceReference(Shape.StrokeProperty, "Tertiary"); }
        zone.DragLeave += (_, _) => Reset();
        zone.Drop += (_, e) =>
        {
            Reset();
            if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
            {
                e.Effects = DragDropEffects.Copy;
                zone.Dispatcher.BeginInvoke(() => onFiles(files));
            }
            e.Handled = true;
        };
        return zone;
    }

    public static string[]? ChooseFiles()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "Choose files for Morph" };
        return dialog.ShowDialog() == true ? dialog.FileNames : null;
    }

    /// A keycap: raised normally, filled when its wheel is showing.
    public static Border Keycap(string text, bool pressed)
    {
        var label = new TextBlock { Text = text, FontSize = 12, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        label.SetResourceReference(TextBlock.ForegroundProperty, pressed ? "OnBrand" : "Primary");
        var cap = new Border
        {
            MinWidth = 46, Height = 30, Padding = new Thickness(8, 0, 8, 0), CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1, 1, 1, pressed ? 1 : 3),
            Child = label, RenderTransform = new TranslateTransform(0, pressed ? 2 : 0),
        };
        cap.SetResourceReference(Border.BackgroundProperty, pressed ? "Brand" : "Surface");
        cap.SetResourceReference(Border.BorderBrushProperty, pressed ? "Brand" : "Stroke");
        return cap;
    }
}

/// "Type a size such as 300 KB or 1.5 MB."
sealed class CustomSize : Window
{
    readonly TextBox box = new() { FontSize = 14, Margin = new Thickness(0, 12, 0, 0), MinWidth = 260 };
    long? result;

    CustomSize(Window owner, long current)
    {
        Title = "Custom size limit";
        Owner = owner;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        this.Brush(BackgroundProperty, "Canvas");
        box.Text = current > 0 ? SizeLimit.Label(current) : "";
        var error = Ui.Text("", "Detail");
        error.SetResourceReference(TextBlock.ForegroundProperty, "Danger");
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(Ui.Plain("Cancel", Close));
        buttons.Children.Add(Ui.Primary("Set", () =>
        {
            if (Options.ParseSize(box.Text) is long bytes && bytes >= SizeLimit.Minimum) { result = bytes; Close(); }
            else error.Text = $"Type a size of at least {SizeLimit.Label(SizeLimit.Minimum)}, such as 300 KB or 1.5 MB.";
        }).Margin(8, 0, 0, 0));
        Content = new StackPanel
        {
            Margin = new Thickness(24),
            Children = { Ui.Text("Custom size limit", "Heading"), Ui.Text("Type a size such as 300 KB or 1.5 MB.", "Detail").Margin(0, 4, 0, 0), box, error, buttons },
        };
        SourceInitialized += (_, _) => Theme.DarkTitleBar(this);
        Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
    }

    public static long? Ask(Window owner, long current)
    {
        var dialog = new CustomSize(owner, current);
        dialog.ShowDialog();
        return dialog.result;
    }
}

/// Asks for an exact photo size, like "600 x 600", for forms that want one.
sealed class CustomPhotoSize : Window
{
    readonly TextBox box = new() { FontSize = 14, Margin = new Thickness(0, 12, 0, 0), MinWidth = 260 };
    PixelSize? result;

    CustomPhotoSize(Window owner, PixelSize? current)
    {
        Title = "Custom photo size";
        Owner = owner;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        this.Brush(BackgroundProperty, "Canvas");
        box.Text = current is null ? "" : $"{current.Width} x {current.Height}";
        var error = Ui.Text("", "Detail");
        error.SetResourceReference(TextBlock.ForegroundProperty, "Danger");
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(Ui.Plain("Cancel", Close));
        buttons.Children.Add(Ui.Primary("Set", () =>
        {
            if (PixelSize.Parse(box.Text) is { } size) { result = size; Close(); }
            else error.Text = "Type a width and height in pixels, such as 600 x 600.";
        }).Margin(8, 0, 0, 0));
        Content = new StackPanel
        {
            Margin = new Thickness(24),
            Children = { Ui.Text("Custom photo size", "Heading"), Ui.Text("Width × height in pixels, as the form asks for it.", "Detail").Margin(0, 4, 0, 0), box, error, buttons },
        };
        SourceInitialized += (_, _) => Theme.DarkTitleBar(this);
        Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
    }

    public static PixelSize? Ask(Window owner, PixelSize? current)
    {
        var dialog = new CustomPhotoSize(owner, current);
        dialog.ShowDialog();
        return dialog.result;
    }
}
