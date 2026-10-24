using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ImageMagick;

namespace Morph.App;

/// `Morph.exe --snapshots <folder>` draws every screen, in light and dark, to PNGs without opening a window.
/// CI runs it on each build, since the Mac the app is written on can't run Windows UI.
public static class Snapshots
{
    public static bool Active { get; private set; }

    /// Returns the process exit code; a failure is written to error.txt in the folder, since the app has no console.
    public static int Run(string folder)
    {
        Directory.CreateDirectory(folder);
        try
        {
            Draw(folder);
            return 0;
        }
        catch (Exception e)
        {
            File.WriteAllText(Path.Combine(folder, "error.txt"), e.ToString());
            return 1;
        }
    }

    static void Draw(string folder)
    {
        Active = true;
        var home = Path.Combine(Path.GetTempPath(), "morph-snapshots-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);
        // Settings and history go to a scratch folder, never the real ones.
        Environment.SetEnvironmentVariable("MORPH_HOME", home);

        var photo = Path.Combine(home, "photo.jpg");
        using (var image = new MagickImage("gradient:#0B6E69-#F1F4F3", 1600, 1200)) image.Write(photo);
        var pdf = DocOps.Convert(Write(home, "notes.md", "# Notes\n\nA page."), "pdf", new Options());

        foreach (var dark in new[] { false, true })
        {
            Theme.Apply(dark);
            var mode = dark ? "dark" : "light";
            Wheel(folder, $"wheel-convert-{mode}", [photo], ActionGroup.Convert, hover: 2);
            Wheel(folder, $"wheel-tools-{mode}", [photo], ActionGroup.Tool, hover: 0);
            Wheel(folder, $"wheel-recipes-{mode}", [photo], ActionGroup.Recipe, hover: 1);
            Wheel(folder, $"wheel-actions-{mode}", [photo, pdf], ActionGroup.File, hover: 3);
            Wheel(folder, $"wheel-waiting-{mode}", [], ActionGroup.Convert, hover: null);
            foreach (var tab in Enum.GetValues<SettingsWindow.Tab>())
                Render(Detach(new SettingsWindow(() => { }, tab)), 580, 520, Path.Combine(folder, $"settings-{tab.ToString().ToLowerInvariant()}-{mode}.png"));
            for (var page = 0; page < WelcomeWindow.Pages; page++)
            {
                var welcome = new WelcomeWindow(_ => { }, () => { });
                welcome.ShowPage(page);
                Render(Detach(welcome), 620, 580, Path.Combine(folder, $"welcome-{page + 1}-{mode}.png"));
            }
            var shelf = new ShelfWindow(_ => { }, () => { }, () => { }, () => { });
            shelf.Build();
            Render(Detach(shelf), 354, double.NaN, Path.Combine(folder, $"shelf-{mode}.png"), clear: true);
        }

        // Microsoft Store screenshots, 1920 × 1080, in the style of the Play Store ones.
        var store = Path.Combine(folder, "store");
        Directory.CreateDirectory(store);
        Theme.Apply(false);
        Store(store, "1-wheel", "Drag a file, tap a key, drop it on the wheel", "Convert, compress and clean up files right where they are.",
            WheelElement([photo], ActionGroup.Convert, 2), WheelGeometry.Width, WheelGeometry.Height);
        Store(store, "2-size-limit", "Fit any upload limit", "Set 200 KB or 50 KB once, and Compress makes a JPG that fits.",
            WheelElement([photo], ActionGroup.Tool, 0), WheelGeometry.Width, WheelGeometry.Height);
        Store(store, "3-actions", "Share, copy or move in one drop", "The Actions wheel works on the files themselves.",
            WheelElement([photo, pdf], ActionGroup.File, 3), WheelGeometry.Width, WheelGeometry.Height);
        var guide = new WelcomeWindow(_ => { }, () => { });
        guide.ShowPage(1);
        Store(store, "4-welcome", "Learn it in a minute", "Each wheel has its own key, and you can change them all.", Detach(guide), 620, 580);
        Store(store, "5-settings", "Make it yours", "Choose a size limit, how hard to compress and where results go.",
            Detach(new SettingsWindow(() => { }, SettingsWindow.Tab.Output)), 580, 520);
        Theme.Apply(true);
        Store(store, "6-dark", "Light or dark, like Windows", "Nothing is uploaded. Your originals are never changed.",
            WheelElement([photo], ActionGroup.Recipe, 1), WheelGeometry.Width, WheelGeometry.Height);
    }

    static string Write(string folder, string name, string text)
    {
        var path = Path.Combine(folder, name);
        File.WriteAllText(path, text);
        return path;
    }

    static void Wheel(string folder, string name, IReadOnlyList<string> files, ActionGroup group, int? hover) =>
        Render(WheelElement(files, group, hover), WheelGeometry.Width, WheelGeometry.Height, Path.Combine(folder, name + ".png"));

    static UIElement WheelElement(IReadOnlyList<string> files, ActionGroup group, int? hover)
    {
        var model = new WheelModel(files, dropMode: files.Count == 0, group);
        if (hover is int slot && model.PageItems.Count > slot)
        {
            var radians = WheelGeometry.Angle(slot, model.PageItems.Count) * Math.PI / 180;
            var r = (WheelGeometry.InnerRadius + WheelGeometry.OuterRadius) / 2;
            model.Hover(Math.Cos(radians) * r, Math.Sin(radians) * r);
        }
        return Detach(new WheelWindow(model));
    }

    /// A headline on Teal Ink with the screen on a rounded card beside it.
    static void Store(string folder, string name, string headline, string detail, UIElement screen, double width, double height)
    {
        var teal = Palette.Hex(0x0B6E69);
        var grid = new Grid { Width = 1920, Height = 1080, Background = new SolidColorBrush(teal) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(820) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var title = new TextBlock
        {
            Text = headline, FontSize = 72, FontWeight = FontWeights.Bold, Foreground = Brushes.White, TextWrapping = TextWrapping.Wrap,
            FontFamily = (FontFamily)Application.Current.Resources["DisplayFont"], LineHeight = 82,
        };
        var subtitle = new TextBlock
        {
            Text = detail, FontSize = 30, Foreground = new SolidColorBrush(Color.FromArgb(220, 255, 255, 255)), TextWrapping = TextWrapping.Wrap,
            FontFamily = (FontFamily)Application.Current.Resources["UiFont"], Margin = new Thickness(0, 28, 0, 0),
        };
        var words = new StackPanel { Margin = new Thickness(120, 0, 40, 0), VerticalAlignment = VerticalAlignment.Center, Children = { title, subtitle } };
        grid.Children.Add(words);
        var holder = new Border { Width = width, Height = height, Child = screen };
        holder.SetResourceReference(Border.BackgroundProperty, "Canvas");
        var scale = Math.Min(900 / height, 980 / width);
        var card = new Border
        {
            Child = new Viewbox { Child = holder, Width = width * scale, Height = height * scale },
            CornerRadius = new CornerRadius(28), ClipToBounds = true, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 60, ShadowDepth = 16, Direction = 270, Opacity = 0.3 },
        };
        card.SetResourceReference(Border.BackgroundProperty, "Canvas");
        holder.Clip = new RectangleGeometry(new Rect(0, 0, width, height), 28 / scale, 28 / scale);
        Grid.SetColumn(card, 1);
        grid.Children.Add(card);
        grid.Measure(new Size(1920, 1080));
        grid.Arrange(new Rect(0, 0, 1920, 1080));
        grid.UpdateLayout();
        var bitmap = new RenderTargetBitmap(1920, 1080, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(grid);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(Path.Combine(folder, $"{name}.png"));
        encoder.Save(stream);
    }

    static UIElement Detach(Window window)
    {
        var content = (UIElement)window.Content;
        window.Content = null;
        return content;
    }

    /// Lays the element out at the given size (or its own height) on the canvas colour and saves it at 2x.
    static void Render(UIElement element, double width, double height, string path, bool clear = false)
    {
        var host = new Border { Child = element, Width = width };
        if (!double.IsNaN(height)) host.Height = height;
        if (!clear) host.SetResourceReference(Border.BackgroundProperty, "Canvas");
        else host.Background = Theme.BrushOf(Theme.IsDark ? "Surface" : "Canvas");
        host.Measure(new Size(width, double.IsNaN(height) ? double.PositiveInfinity : height));
        var size = new Size(width, double.IsNaN(height) ? host.DesiredSize.Height : height);
        host.Arrange(new Rect(size));
        host.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width * 2), (int)Math.Ceiling(size.Height * 2), 192, 192, PixelFormats.Pbgra32);
        bitmap.Render(host);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
        host.Child = null;
    }
}
