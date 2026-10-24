using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Morph.App;

/// First-launch guide: what Morph is, how to use it (with a live drop zone), the settings worth choosing up front,
/// then setup. Picking a colour recolours the guide as you click.
public sealed class WelcomeWindow : Window
{
    public const int Pages = 4;
    int page;
    readonly ContentControl body = new() { Focusable = false };
    readonly TranslateTransform slide = new();
    readonly StackPanel dots = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    readonly Button back;
    readonly Button next;
    readonly Action<string[]> onTry;
    readonly Action onFinish;
    WheelTour? tour;

    public WelcomeWindow(Action<string[]> onTry, Action onFinish)
    {
        this.onTry = onTry;
        this.onFinish = onFinish;
        Title = "Welcome to Morph";
        Width = 620;
        Height = 620;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = (FontFamily)FindResource("UiFont");
        this.Brush(BackgroundProperty, "Canvas");

        back = Ui.Plain("Back", () => Go(-1));
        next = Ui.Primary("Continue", () => { if (page == Pages - 1) onFinish(); else Go(1); });
        var footer = new DockPanel { Margin = new Thickness(28, 16, 28, 22), LastChildFill = false };
        footer.Children.Add(dots);
        DockPanel.SetDock(next, Dock.Right);
        DockPanel.SetDock(back, Dock.Right);
        footer.Children.Add(next);
        footer.Children.Add(back.Margin(0, 0, 10, 0));
        DockPanel.SetDock(footer, Dock.Bottom);

        body.RenderTransform = slide;
        var scroll = new ScrollViewer { Content = body, Style = (Style)FindResource("PageScroll"), Padding = new Thickness(40, 36, 40, 0) };
        var dock = new DockPanel();
        dock.Children.Add(footer);
        dock.Children.Add(scroll);
        Content = dock;
        Build();

        Preferences.Shared.PropertyChanged += Changed;
        Theme.Changed += Build;
        Closed += (_, _) => { Preferences.Shared.PropertyChanged -= Changed; Theme.Changed -= Build; tour?.Stop(); };
        SourceInitialized += (_, _) => Theme.DarkTitleBar(this);
    }

    void Changed(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(Build);

    public void ShowPage(int index)
    {
        page = Math.Clamp(index, 0, Pages - 1);
        Build();
    }

    void Go(int delta)
    {
        page = Math.Clamp(page + delta, 0, Pages - 1);
        Build();
        if (!WheelRing.Motion) return;
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        slide.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(delta > 0 ? 60 : -60, 0, TimeSpan.FromMilliseconds(320)) { EasingFunction = ease });
        body.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(260)));
    }

    void Build()
    {
        tour?.Stop();
        tour = null;
        body.Content = page switch
        {
            0 => Intro(),
            1 => HowItWorks(),
            2 => MakeItYours(),
            _ => Setup(),
        };
        dots.Children.Clear();
        for (var i = 0; i < Pages; i++)
            dots.Children.Add(new Border { Width = i == page ? 22 : 8, Height = 8, CornerRadius = new CornerRadius(4), Margin = new Thickness(0, 0, 6, 0) }
                .Brush(Border.BackgroundProperty, i == page ? "Brand" : "Stroke"));
        back.Visibility = page > 0 ? Visibility.Visible : Visibility.Collapsed;
        next.Content = page == Pages - 1 ? "Start Using Morph" : "Continue";
    }

    static UIElement Intro()
    {
        var icon = new Image { Source = new BitmapImage(new Uri("pack://application:,,,/Assets/Morph.png")), Width = 112, Height = 112, HorizontalAlignment = HorizontalAlignment.Center };
        var title = Ui.Text("Welcome to Morph", "Title");
        title.FontSize = 32;
        title.HorizontalAlignment = HorizontalAlignment.Center;
        var subtitle = Ui.Text("Convert, shrink and tidy up any file, right where it is.", "Detail");
        subtitle.FontSize = 15;
        subtitle.TextAlignment = TextAlignment.Center;
        var features = new UniformGrid3();
        features.Add(Feature(Icons.Convert, "Convert", "Images, video, audio, PDFs and docs"));
        features.Add(Feature(Icons.Compress, "Compress", "Fit any size limit in one drop"));
        features.Add(Feature(Icons.Clean, "Clean up", "Strip metadata, blur faces, read text"));
        var privacy = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        privacy.Children.Add(Ui.Glyph(Icons.Lock, 12, "Secondary").Margin(0, 0, 6, 0));
        privacy.Children.Add(Ui.Text("Everything runs on your PC. Files never leave it.", "Detail"));
        return Ui.Stack(16, icon, title, subtitle, features.Panel, privacy);
    }

    static UIElement Feature(string glyph, string title, string detail)
    {
        var heading = Ui.Text(title, "Heading");
        heading.HorizontalAlignment = HorizontalAlignment.Center;
        var text = Ui.Text(detail, "Detail");
        text.TextAlignment = TextAlignment.Center;
        var bubble = Ui.Bubble(glyph, 44);
        bubble.HorizontalAlignment = HorizontalAlignment.Center;
        return Ui.Card(Ui.Stack(8, bubble, heading, text), 14);
    }

    UIElement HowItWorks()
    {
        tour = new WheelTour();
        var zoneContent = Ui.Stack(4,
            Ui.Glyph(Icons.Download, 24),
            Centered(Ui.Text("Try it: drop a file here", "Heading")),
            Centered(Ui.Text("A copy is made; your file stays as it is.", "Detail")));
        zoneContent.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Stack(16,
            Ui.Stack(6, Ui.Text("How it works", "Title"),
                Ui.Text("Drag files from File Explorer or the desktop and tap a key: that wheel pops up under your cursor. Drop on an action and the result lands beside the original, which is never touched.", "Detail")),
            tour.View,
            Ui.DropZone(zoneContent, onTry, 104));
    }

    static TextBlock Centered(TextBlock text)
    {
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.TextAlignment = TextAlignment.Center;
        return text;
    }

    UIElement MakeItYours() => Ui.Stack(10,
        Ui.Text("Make it yours", "Title"),
        Ui.Text("You can change all of this later in Settings.", "Detail").Margin(0, 4, 0, 4),
        Rows.Color(),
        Rows.SizeLimit(this, "Upload forms often want photos under 200 KB or 100 KB. Set a limit and Compress makes a JPG that fits."),
        Rows.Compression());

    static UIElement Setup() => Ui.Stack(10,
        Ui.Text("Finish setting up", "Title"),
        Ui.Text("You can change all of this later in Settings.", "Detail").Margin(0, 4, 0, 4),
        Rows.Login(), Rows.DragShortcuts(), Rows.Tray(), Rows.ContextMenu(), Rows.FFmpeg());

    /// Three equal columns.
    sealed class UniformGrid3
    {
        public readonly System.Windows.Controls.Primitives.UniformGrid Panel = new() { Columns = 3, Rows = 1 };
        public void Add(UIElement element)
        {
            if (element is FrameworkElement f) f.Margin = new Thickness(Panel.Children.Count == 0 ? 0 : 6, 0, Panel.Children.Count == 2 ? 0 : 6, 0);
            Panel.Children.Add(element);
        }
    }
}

/// "How it works" demo: a small wheel that plays through each wheel in turn, with that wheel's keys lit up beside
/// it, so the drag shortcuts are learned by watching rather than reading.
public sealed class WheelTour
{
    const int StepsPerWheel = 4;
    public readonly Grid View = new();
    readonly MiniWheel wheel = new();
    readonly StackPanel keys = new() { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(24, 0, 0, 0) };
    readonly DispatcherTimer timer;
    int tick;

    static IReadOnlyList<ActionGroup> Wheels
    {
        get
        {
            var set = WheelKeyMap.Wheels.Where(g => Preferences.Shared.DragKeys(g) != DragKeys.Off).ToList();
            return set.Count > 0 ? set : WheelKeyMap.Wheels;
        }
    }

    ActionGroup Current => Wheels[tick / StepsPerWheel % Wheels.Count];

    public WheelTour()
    {
        View.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        View.ColumnDefinitions.Add(new ColumnDefinition());
        View.Children.Add(wheel);
        Grid.SetColumn(keys, 1);
        View.Children.Add(keys);
        timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(WheelRing.Motion ? 750 : 1800) };
        timer.Tick += (_, _) => { tick++; Refresh(); };
        View.Loaded += (_, _) => timer.Start();
        View.Unloaded += (_, _) => timer.Stop();
        Refresh();
    }

    public void Stop() => timer.Stop();

    void Refresh()
    {
        var current = Current;
        wheel.Show(current, tick % StepsPerWheel);
        keys.Children.Clear();
        foreach (var group in Wheels)
        {
            var active = group == current;
            var keyText = Preferences.Shared.DragKeys(group) is var k && k != DragKeys.Off ? k.Label() : "–";
            var row = new Grid { Margin = new Thickness(0, 0, 0, 9), Opacity = active ? 1 : 0.6, Background = System.Windows.Media.Brushes.Transparent, Cursor = System.Windows.Input.Cursors.Hand };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            var cap = Ui.Keycap(keyText, active);
            cap.HorizontalAlignment = HorizontalAlignment.Left;
            row.Children.Add(cap);
            var texts = Ui.Stack(1, Ui.Text(group.Label(), "Heading"), Ui.Text(Detail(group), "Detail"));
            texts.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(texts, 1);
            row.Children.Add(texts);
            var g = group;
            row.MouseLeftButtonUp += (_, _) =>
            {
                tick = Wheels.ToList().IndexOf(g) * StepsPerWheel;
                Refresh();
            };
            keys.Children.Add(row);
        }
    }

    static string Detail(ActionGroup group) => group switch
    {
        ActionGroup.Convert => "Images, video, audio and docs to any format",
        ActionGroup.Tool => "Compress, clean up, read text and codes",
        ActionGroup.Recipe => "Several steps in one drop",
        _ => "Share, copy, move, open Terminal",
    };
}

/// A small wheel with sample petals for the tour.
public sealed class MiniWheel : FrameworkElement
{
    const double Size = 184;
    ActionGroup group;
    int highlight;

    static readonly Dictionary<ActionGroup, string[]> samples = new()
    {
        [ActionGroup.Convert] = ["photo", "photo", "doc.richtext", "film", "waveform", "sparkles.rectangle.stack"],
        [ActionGroup.Tool] = ["arrow.down.right.and.arrow.up.left", "arrow.up.left.and.down.right.magnifyingglass", "eye.slash", "text.viewfinder", "qrcode.viewfinder", "doc.zipper"],
        [ActionGroup.Recipe] = ["lock.shield", "globe", "envelope", "wand.and.stars"],
        [ActionGroup.File] = ["square.and.arrow.up", "doc.on.doc", "link", "folder", "plus.rectangle.on.folder", "terminal"],
    };

    public MiniWheel()
    {
        Width = Height = Size;
        VerticalAlignment = VerticalAlignment.Center;
    }

    public void Show(ActionGroup group, int step)
    {
        this.group = group;
        highlight = step;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        var c = new Point(Size / 2, Size / 2);
        var symbols = samples[group];
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var font = new Typeface((FontFamily)Application.Current.Resources["IconFont"], FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        for (var i = 0; i < symbols.Length; i++)
        {
            var lit = i == highlight % symbols.Length;
            var angle = WheelGeometry.Angle(i, symbols.Length);
            var shape = WheelRing.Petal(c, angle, 360.0 / symbols.Length, 4, 40, lit ? 88 : 82, 6);
            dc.DrawGeometry(Theme.BrushOf(lit ? "Brand" : "Surface"), new Pen(Theme.BrushOf("Stroke"), 1), shape);
            var radians = angle * Math.PI / 180;
            var at = new Point(c.X + Math.Cos(radians) * 62, c.Y + Math.Sin(radians) * 62);
            var icon = new FormattedText(Icons.For(symbols[i]), System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                font, 17, Theme.BrushOf(lit ? "OnBrand" : "Primary"), dpi);
            dc.DrawText(icon, new Point(at.X - icon.Width / 2, at.Y - icon.Height / 2));
        }
        dc.DrawEllipse(Theme.BrushOf("Surface"), new Pen(Theme.BrushOf("Stroke"), 1), c, 34, 34);
        var label = new FormattedText(group.Label(), System.Globalization.CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface((FontFamily)Application.Current.Resources["UiFont"], FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal), 12, Theme.BrushOf("Primary"), dpi);
        dc.DrawText(label, new Point(c.X - label.Width / 2, c.Y - label.Height / 2));
    }
}
