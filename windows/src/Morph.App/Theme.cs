using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace Morph.App;

/// The accent colours people can choose in Settings. Teal Ink is Morph's own and the default; the app icon stays
/// Teal Ink whatever is picked. Values match the Mac, iPhone and Android apps.
public sealed record Palette(string Id, string Name, Color FillLight, Color FillDark, Color TextLight, Color TextDark, Color OnFill)
{
    public static readonly IReadOnlyList<Palette> All =
    [
        new("teal", "Teal Ink", Hex(0x0B6E69), Hex(0x157F79), Hex(0x0B6E69), Hex(0x4FC1B9), Colors.White),
        new("ultramarine", "Ultramarine", Hex(0x2F2EFF), Hex(0x2F2EFF), Hex(0x2F2EFF), Hex(0xA6A8FF), Colors.White),
        new("green", "Green", Hex(0x17804A), Hex(0x17804A), Hex(0x136B3E), Hex(0x62C48E), Colors.White),
        new("magenta", "Magenta", Hex(0xD6007A), Hex(0xD6007A), Hex(0xC2006E), Hex(0xFF8CC6), Colors.White),
        new("yellow", "Yellow", Hex(0xFFD60A), Hex(0xFFD60A), Hex(0x735A00), Hex(0xFFD60A), Hex(0x121318)),
    ];

    public static Palette Named(string id) => All.FirstOrDefault(p => p.Id == id) ?? All[0];

    public Color Fill(bool dark) => dark ? FillDark : FillLight;
    public Color Text(bool dark) => dark ? TextDark : TextLight;

    internal static Color Hex(int rgb) => Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
}

/// Morph's look: one flat brand colour on cool neutrals, with big rounded corners. Colours live in the
/// application's resources as brushes, so every window recolours at once when the palette or Windows' light or
/// dark mode changes.
public static class Theme
{
    public static bool IsDark { get; private set; }

    public static event Action? Changed;

    public static void Start()
    {
        Apply();
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category is UserPreferenceCategory.General or UserPreferenceCategory.Color or UserPreferenceCategory.VisualStyle)
                Application.Current.Dispatcher.BeginInvoke(() => Apply());
        };
        Preferences.Shared.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(Preferences.Palette)) Apply(); };
    }

    /// Windows' "Choose your app mode": dark unless apps are set to light.
    static bool ReadDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
        catch (System.Security.SecurityException) { return false; }
    }

    /// `dark` overrides Windows' app mode (the snapshot renderer draws both).
    public static void Apply(bool? dark = null)
    {
        IsDark = dark ?? ReadDark();
        var palette = Preferences.Shared.Palette;
        var r = Application.Current.Resources;
        var fill = palette.Fill(IsDark);
        Set(r, "Brand", fill);
        Set(r, "BrandText", palette.Text(IsDark));
        Set(r, "OnBrand", palette.OnFill);
        Set(r, "Tint", Color.FromArgb(31, fill.R, fill.G, fill.B));
        Set(r, "Canvas", IsDark ? Palette.Hex(0x0E1414) : Palette.Hex(0xF1F4F3));
        Set(r, "Surface", IsDark ? Palette.Hex(0x172020) : Colors.White);
        Set(r, "Primary", IsDark ? Palette.Hex(0xF2F5F4) : Palette.Hex(0x121818));
        Set(r, "Secondary", IsDark ? Color.FromArgb(166, 235, 245, 243) : Color.FromArgb(153, 18, 24, 24));
        Set(r, "Tertiary", IsDark ? Color.FromArgb(102, 235, 245, 243) : Color.FromArgb(97, 18, 24, 24));
        Set(r, "Stroke", IsDark ? Color.FromArgb(40, 255, 255, 255) : Color.FromArgb(28, 0, 0, 0));
        Set(r, "Hover", IsDark ? Color.FromArgb(20, 255, 255, 255) : Color.FromArgb(12, 0, 0, 0));
        // The wheel floats over whatever is behind it: frosted rather than solid.
        Set(r, "Glass", IsDark ? Color.FromArgb(235, 0x1B, 0x25, 0x25) : Color.FromArgb(240, 0xFB, 0xFC, 0xFC));
        Set(r, "GlassRim", IsDark ? Color.FromArgb(46, 255, 255, 255) : Color.FromArgb(255, 255, 255, 255));
        Set(r, "Danger", IsDark ? Palette.Hex(0xFF6B6B) : Palette.Hex(0xC62828));
        foreach (Window window in Application.Current.Windows) DarkTitleBar(window);
        Changed?.Invoke();
    }

    static void Set(ResourceDictionary resources, string key, Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        resources[key] = brush;
        resources[key + "Color"] = color;
    }

    public static Brush BrushOf(string key) => (Brush)Application.Current.Resources[key];
    public static Color ColorOf(string key) => (Color)Application.Current.Resources[key + "Color"];

    /// Title bars follow the app mode too (Windows 10 2004 and later honour this).
    public static void DarkTitleBar(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        var on = IsDark ? 1 : 0;
        Native.DwmSetWindowAttribute(handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, ref on, sizeof(int));
    }
}
