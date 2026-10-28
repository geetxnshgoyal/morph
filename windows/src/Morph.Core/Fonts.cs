using PdfSharp.Fonts;

namespace Morph;

/// Gives PDFsharp the system's own fonts: Segoe UI and Consolas on Windows (Arial, Courier New or DejaVu elsewhere).
static class Fonts
{
    public const string Sans = "Morph Sans";
    public const string Mono = "Morph Mono";

    static int installed;

    /// The sans font file (Segoe UI on Windows), for drawing text into images.
    public static string? SansFile(bool bold) => Resolver.File("sans", bold ? 1 : 0);

    public static void Install()
    {
        if (Interlocked.Exchange(ref installed, 1) == 0 && GlobalFontSettings.FontResolver is null)
            GlobalFontSettings.FontResolver = new Resolver();
    }

    sealed class Resolver : IFontResolver
    {
        static readonly string windowsFonts = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Fonts");

        /// Files for each face, best first: regular, bold, italic, bold italic.
        static readonly Dictionary<string, string[][]> candidates = new()
        {
            ["sans"] =
            [
                [Path.Combine(windowsFonts, "segoeui.ttf"), Path.Combine(windowsFonts, "arial.ttf"), "/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
                [Path.Combine(windowsFonts, "segoeuib.ttf"), Path.Combine(windowsFonts, "arialbd.ttf"), "/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
                [Path.Combine(windowsFonts, "segoeuii.ttf"), Path.Combine(windowsFonts, "ariali.ttf"), "/System/Library/Fonts/Supplemental/Arial Italic.ttf"],
                [Path.Combine(windowsFonts, "segoeuiz.ttf"), Path.Combine(windowsFonts, "arialbi.ttf"), "/System/Library/Fonts/Supplemental/Arial Bold Italic.ttf"],
            ],
            ["mono"] =
            [
                [Path.Combine(windowsFonts, "consola.ttf"), Path.Combine(windowsFonts, "cour.ttf"), "/System/Library/Fonts/Supplemental/Courier New.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"],
                [Path.Combine(windowsFonts, "consolab.ttf"), Path.Combine(windowsFonts, "courbd.ttf"), "/System/Library/Fonts/Supplemental/Courier New Bold.ttf"],
                [Path.Combine(windowsFonts, "consolai.ttf"), Path.Combine(windowsFonts, "couri.ttf"), "/System/Library/Fonts/Supplemental/Courier New Italic.ttf"],
                [Path.Combine(windowsFonts, "consolaz.ttf"), Path.Combine(windowsFonts, "courbi.ttf"), "/System/Library/Fonts/Supplemental/Courier New Bold Italic.ttf"],
            ],
        };

        internal static string? File(string family, int style) => candidates[family][style].FirstOrDefault(System.IO.File.Exists);

        public FontResolverInfo? ResolveTypeface(string familyName, bool bold, bool italic)
        {
            var family = familyName.Contains("Mono", StringComparison.OrdinalIgnoreCase) ? "mono" : "sans";
            var style = (bold ? 1 : 0) + (italic ? 2 : 0);
            if (File(family, style) is not null) return new FontResolverInfo($"{family}-{style}");
            // No file for this style: let PDFsharp embolden or slant the regular face.
            return File(family, 0) is null ? null : new FontResolverInfo($"{family}-0", bold, italic);
        }

        public byte[]? GetFont(string faceName)
        {
            var parts = faceName.Split('-');
            return File(parts[0], int.Parse(parts[1])) is { } path ? System.IO.File.ReadAllBytes(path) : null;
        }
    }
}
