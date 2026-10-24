using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

namespace Morph.App;

/// The wheel: a ring of petals around a hub, with a bar below for switching wheels, in a borderless transparent
/// window centred on the cursor. Each wheel (Convert, Tools, Recipes, Actions) uses the same layout; the bar shows
/// the keys that summon each one mid-drag. In drop mode the window never takes focus, so the drag in progress
/// carries on into it.
public sealed class WheelWindow : Window
{
    public WheelModel Model { get; }
    readonly WheelRing ring;
    readonly Border hub;
    readonly ScaleTransform hubScale = new(1, 1);
    readonly Border bar;
    readonly Native.POINT anchor;
    bool closing;
    double scrollAccumulator;

    const double CenterX = WheelGeometry.CenterX, CenterY = WheelGeometry.CenterY;

    public WheelWindow(WheelModel model)
    {
        Model = model;
        Native.GetCursorPos(out anchor);
        Title = "Morph";
        Width = WheelGeometry.Width;
        Height = WheelGeometry.Height;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = !model.DropMode;
        WindowStartupLocation = WindowStartupLocation.Manual;
        // Off screen until placed in physical pixels under the cursor.
        Left = -10_000;
        Top = -10_000;
        Opacity = 0;
        AllowDrop = true;
        FontFamily = (FontFamily)FindResource("UiFont");
        UseLayoutRounding = true;

        var canvas = new Canvas { Width = Width, Height = Height };
        ring = new WheelRing(model)
        {
            Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Direction = 270, Opacity = 0.18, Color = Colors.Black },
        };
        Canvas.SetLeft(ring, CenterX - WheelGeometry.Side / 2);
        Canvas.SetTop(ring, CenterY - WheelGeometry.Side / 2);
        canvas.Children.Add(ring);

        var diameter = WheelGeometry.HubRadius * 2;
        hub = new Border
        {
            Width = diameter, Height = diameter, CornerRadius = new CornerRadius(diameter / 2),
            Background = Theme.BrushOf("Glass"), BorderBrush = Theme.BrushOf("Stroke"), BorderThickness = new Thickness(1),
            RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = hubScale,
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 0, Opacity = 0.14, Color = Colors.Black },
        };
        Canvas.SetLeft(hub, CenterX - diameter / 2);
        Canvas.SetTop(hub, CenterY - diameter / 2);
        canvas.Children.Add(hub);

        bar = new Border
        {
            Background = Theme.BrushOf("Glass"), BorderBrush = Theme.BrushOf("Stroke"), BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(19), Padding = new Thickness(4),
            Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 4, Direction = 270, Opacity = 0.15, Color = Colors.Black },
        };
        bar.SizeChanged += (_, _) =>
        {
            Canvas.SetLeft(bar, CenterX - bar.ActualWidth / 2);
            Canvas.SetTop(bar, CenterY + WheelGeometry.OuterRadius + WheelGeometry.Lift + 42 - bar.ActualHeight / 2);
        };
        canvas.Children.Add(bar);
        Content = canvas;

        model.Changed += Refresh;
        model.Dismiss = CloseAnimated;
        Refresh();

        ring.MouseMove += (_, e) => { var p = Centered(e.GetPosition(ring)); Model.Hover(p.X, p.Y); };
        ring.MouseLeave += (_, _) => Model.ClearHover();
        ring.MouseLeftButtonUp += (_, e) =>
        {
            var p = Centered(e.GetPosition(ring));
            if (Model.ActionAt(p.X, p.Y) is { } action) Model.Run(action);
        };
        MouseWheel += (_, e) => Scroll(e.Delta);
        PreviewKeyDown += OnKey;
        Deactivated += (_, _) => { if (!Model.DropMode) CloseAnimated(); };
        DragEnter += OnDrag;
        DragOver += OnDrag;
        DragLeave += (_, _) => Model.ClearHover();
        Drop += OnDrop;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var style = (long)Native.GetWindowLongPtr(handle, Native.GWL_EXSTYLE) | Native.WS_EX_TOOLWINDOW;
            // Taking focus now would cancel the drag in progress.
            if (Model.DropMode) style |= Native.WS_EX_NOACTIVATE;
            Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE, (IntPtr)style);
        };
    }

    static Point Centered(Point p) => new(p.X - WheelGeometry.Side / 2, p.Y - WheelGeometry.Side / 2);

    /// Shows the wheel with its ring centred on the cursor, kept on the cursor's screen.
    public void Present()
    {
        Show();
        Place();
        // A different monitor's scaling resizes the window once it lands there; place it again after that.
        Dispatcher.BeginInvoke(Place, System.Windows.Threading.DispatcherPriority.Loaded);
        var motion = WheelRing.Motion;
        BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(motion ? 120 : 0)));
        if (motion)
        {
            var spring = new BackEase { Amplitude = 0.45, EasingMode = EasingMode.EaseOut };
            var grow = new DoubleAnimation(0.3, 1, TimeSpan.FromMilliseconds(380)) { EasingFunction = spring };
            hubScale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
            hubScale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
        }
        if (!Model.DropMode)
        {
            Activate();
            Focus();
        }
    }

    void Place()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero) return;
        var scale = Native.ScaleAt(anchor);
        var work = Native.WorkAreaAt(anchor);
        int width = (int)Math.Round(Width * scale), height = (int)Math.Round(Height * scale);
        var x = (int)Math.Round(anchor.X - CenterX * scale);
        var y = (int)Math.Round(anchor.Y - CenterY * scale);
        x = Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - width));
        y = Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - height));
        Native.SetWindowPos(handle, IntPtr.Zero, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
    }

    /// Closing pulls everything back into the hub (unless animations are off) before the window goes.
    public void CloseAnimated()
    {
        if (closing) return;
        closing = true;
        if (!WheelRing.Motion || !IsVisible) { Close(); return; }
        ring.Close();
        var shrink = new DoubleAnimation(0.3, TimeSpan.FromMilliseconds(200)) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn } };
        hubScale.BeginAnimation(ScaleTransform.ScaleXProperty, shrink);
        hubScale.BeginAnimation(ScaleTransform.ScaleYProperty, shrink);
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(220));
        fade.Completed += (_, _) => Close();
        BeginAnimation(OpacityProperty, fade);
    }

    public bool IsClosing => closing;

    /// Whether a screen point (physical pixels) is on the wheel's window.
    public bool Contains(Native.POINT point)
    {
        var handle = new WindowInteropHelper(this).Handle;
        return handle != IntPtr.Zero && Native.GetWindowRect(handle, out var r)
            && point.X >= r.Left && point.X < r.Right && point.Y >= r.Top && point.Y < r.Bottom;
    }

    // MARK: Input

    void OnKey(object sender, KeyEventArgs e)
    {
        if (Model.Phase != WheelPhase.Choosing) { if (e.Key == Key.Escape) CloseAnimated(); return; }
        switch (e.Key)
        {
            case Key.Right or Key.Down: Model.Step(1); break;
            case Key.Left or Key.Up: Model.Step(-1); break;
            case Key.Enter or Key.Space: Model.RunHighlighted(); break;
            case Key.Tab: Model.CycleGroup(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? -1 : 1); break;
            case Key.PageDown: Model.TurnPage(1); break;
            case Key.PageUp: Model.TurnPage(-1); break;
            case Key.Escape: CloseAnimated(); break;
            default: return;
        }
        e.Handled = true;
    }

    /// A mouse wheel notch is one step; precision touchpads send smaller deltas that add up to one.
    void Scroll(int delta)
    {
        if (Model.Phase != WheelPhase.Choosing) return;
        scrollAccumulator += delta;
        while (Math.Abs(scrollAccumulator) >= 120)
        {
            Model.Step(scrollAccumulator < 0 ? 1 : -1);
            scrollAccumulator -= Math.Sign(scrollAccumulator) * 120;
        }
    }

    static string[]? DraggedFiles(DragEventArgs e) =>
        e.Data.GetDataPresent(DataFormats.FileDrop) ? e.Data.GetData(DataFormats.FileDrop) as string[] : null;

    /// Morph only ever reads the files, so a drop is a copy whatever keys are held: the source never deletes them.
    static DragDropEffects CopyEffect(DragEventArgs e) =>
        e.AllowedEffects.HasFlag(DragDropEffects.Copy) ? DragDropEffects.Copy
        : e.AllowedEffects.HasFlag(DragDropEffects.Link) ? DragDropEffects.Link : DragDropEffects.None;

    void OnDrag(object sender, DragEventArgs e)
    {
        e.Handled = true;
        if (DraggedFiles(e) is not { Length: > 0 } files || Model.Phase != WheelPhase.Choosing) { e.Effects = DragDropEffects.None; return; }
        Model.SetFiles(files);
        var p = Centered(e.GetPosition(ring));
        Model.Hover(p.X, p.Y);
        e.Effects = Model.ActionAt(p.X, p.Y) is null ? DragDropEffects.None : CopyEffect(e);
    }

    void OnDrop(object sender, DragEventArgs e)
    {
        e.Handled = true;
        if (DraggedFiles(e) is not { Length: > 0 } files || Model.Phase != WheelPhase.Choosing) { e.Effects = DragDropEffects.None; return; }
        Model.SetFiles(files);
        var p = Centered(e.GetPosition(ring));
        if (Model.ActionAt(p.X, p.Y) is not { } action) { e.Effects = DragDropEffects.None; return; }
        e.Effects = CopyEffect(e);
        // Run after the drop returns: the source app waits on it, and some actions open dialogs.
        Dispatcher.BeginInvoke(() => Model.Run(action));
    }

    // MARK: Hub and bar

    void Refresh()
    {
        hub.Child = HubContent();
        var groups = Model.Groups;
        bar.Visibility = Model.Phase == WheelPhase.Choosing && groups.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var group in groups) row.Children.Add(BarButton(group));
        bar.Child = row;
    }

    UIElement BarButton(ActionGroup group)
    {
        var selected = group == Model.Group;
        var keys = Preferences.Shared.DragKeys(group);
        var ink = selected ? Theme.BrushOf("OnBrand") : Theme.BrushOf("Primary");
        var label = new StackPanel { Orientation = Orientation.Horizontal };
        if (keys != DragKeys.Off)
            label.Children.Add(new TextBlock { Text = keys.Label(), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = ink, Opacity = selected ? 0.85 : 0.5, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center });
        label.Children.Add(new TextBlock { Text = group.Label(), FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = ink, VerticalAlignment = VerticalAlignment.Center });
        var pill = new Border
        {
            Child = label, Padding = new Thickness(13, 7, 13, 7), CornerRadius = new CornerRadius(15),
            Background = selected ? Theme.BrushOf("Brand") : Brushes.Transparent, Cursor = Cursors.Hand,
            ToolTip = keys == DragKeys.Off ? group.Label() : $"{group.Label()}: tap {keys.Label()} while dragging",
        };
        pill.MouseLeftButtonUp += (_, _) => Model.Select(group);
        // Spring-loaded: hovering a drag over a wheel switches to it.
        pill.DragEnter += (_, _) => Model.Select(group);
        return pill;
    }

    TextBlock Line(string text, double size, FontWeight weight, string brush = "Primary", int lines = 1) => new()
    {
        Text = text, FontSize = size, FontWeight = weight, Foreground = Theme.BrushOf(brush),
        TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
        TextWrapping = lines > 1 ? TextWrapping.Wrap : TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis,
        MaxHeight = lines * size * 1.4, MaxWidth = WheelGeometry.HubRadius * 2 - 26,
    };

    UIElement HubContent()
    {
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        switch (Model.Phase)
        {
            case WheelPhase.Choosing:
                stack.Children.Add(Line(Model.HoverTitle ?? Model.Summary, 14, FontWeights.SemiBold, lines: 2));
                stack.Children.Add(Spaced(Line(Model.Caption, 11, FontWeights.Normal, "Secondary"), 4));
                if (Model.Pages > 1)
                {
                    var dots = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
                    for (var i = 0; i < Model.Pages; i++)
                        dots.Children.Add(new Border
                        {
                            Width = i == Model.Page ? 12 : 5, Height = 5, CornerRadius = new CornerRadius(2.5), Margin = new Thickness(2, 0, 2, 0),
                            Background = i == Model.Page ? Theme.BrushOf("Brand") : Theme.BrushOf("Stroke"),
                        });
                    stack.Children.Add(dots);
                }
                break;
            case WheelPhase.Running:
                stack.Children.Add(new MorphLoader(54));
                stack.Children.Add(Spaced(Line(Model.Running?.Title ?? "", 14, FontWeights.SemiBold), 8));
                if (Model.Total > 1) stack.Children.Add(Line($"{Model.Done} of {Model.Total}", 11, FontWeights.Normal, "Secondary"));
                break;
            case WheelPhase.Finished when Model.Result is { } result:
                var failed = result.Failures.Count > 0;
                stack.Children.Add(new TextBlock
                {
                    Text = failed ? Icons.Warning : result.Unchanged ? Icons.Info : Icons.Check,
                    FontFamily = (FontFamily)FindResource("IconFont"), FontSize = 24, HorizontalAlignment = HorizontalAlignment.Center,
                    Foreground = Theme.BrushOf(failed ? "Danger" : "BrandText"),
                });
                stack.Children.Add(Spaced(Line(failed ? $"{result.Failures.Count} failed" : result.Unchanged ? "Already small" : "Done", 14, FontWeights.SemiBold), 5));
                if (Model.Running is { ReportsSize: true } && result.SizeSummary is { } sizes && result.SizeChange is { } change)
                {
                    stack.Children.Add(Line(sizes, 12, FontWeights.SemiBold));
                    stack.Children.Add(Line(change, 11, FontWeights.Normal, "Secondary"));
                }
                else if (result.Unchanged) stack.Children.Add(Line("Any smaller would look worse", 10.5, FontWeights.Normal, "Secondary", 2));
                else if (failed) stack.Children.Add(Line(result.Failures[0], 10.5, FontWeights.Normal, "Secondary", 3));
                if (result.Outputs.Count > 0)
                {
                    var show = new Button { Content = "Show in Explorer", Style = (Style)FindResource("SoftButton"), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0), FontSize = 11, Padding = new Thickness(10, 4, 10, 4) };
                    show.Click += (_, _) => Model.Reveal();
                    stack.Children.Add(show);
                }
                break;
        }
        return stack;
    }

    static FrameworkElement Spaced(FrameworkElement element, double top)
    {
        element.Margin = new Thickness(0, top, 0, 0);
        return element;
    }
}

/// The "working on it" loader: Morph's seven drops turning, the outer six breathing in and out.
public sealed class MorphLoader : Canvas
{
    public MorphLoader(double size)
    {
        Width = Height = size;
        HorizontalAlignment = HorizontalAlignment.Center;
        var spin = new RotateTransform(0, size / 2, size / 2);
        var breathe = new ScaleTransform(1, 1, size / 2, size / 2);
        RenderTransform = new TransformGroup { Children = { breathe, spin } };
        double reach = size * 0.31, radius = size * 0.12;
        for (var i = -1; i < 6; i++)
        {
            var angle = i * Math.PI / 3 - Math.PI / 2;
            var dot = new Ellipse { Width = radius * 2, Height = radius * 2, Fill = Theme.BrushOf("Brand") };
            SetLeft(dot, size / 2 + (i < 0 ? 0 : Math.Cos(angle) * reach) - radius);
            SetTop(dot, size / 2 + (i < 0 ? 0 : Math.Sin(angle) * reach) - radius);
            Children.Add(dot);
        }
        if (!WheelRing.Motion) return;
        spin.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.8)) { RepeatBehavior = RepeatBehavior.Forever });
        var pulse = new DoubleAnimation(1, 0.8, TimeSpan.FromSeconds(0.6)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase() };
        breathe.BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
        breathe.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
    }
}
