using System.Xml;
using System.Xml.Linq;
using ImageMagick;

namespace Morph;

/// SVG in both directions. SVGs are drawn by ImageMagick, after every reference outside the file is stripped (and
/// any DOCTYPE with it), so drawing one never reaches the network or other files. Images become SVGs by tracing them
/// into shapes (see `Tracer`).
public static class VectorOps
{
    /// Icons are often drawn at 16-24 px, so SVGs render at least this big on the long side unless a size is set.
    const int MinimumPixel = 1024, MaximumPixel = 8192;

    public static bool IsSvg(string path) => FileKinds.Extension(path) == "svg";

    /// The SVG with only in-file references left: `#id` links and data: URLs.
    internal static byte[] Contained(string path)
    {
        XDocument document;
        try
        {
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null };
            using var reader = XmlReader.Create(path, settings);
            document = XDocument.Load(reader);
        }
        catch (XmlException) { throw new MorphException($"{Path.GetFileName(path)} isn't a readable SVG"); }
        var outside = document.Descendants()
            .SelectMany(e => e.Attributes())
            .Where(a => a.Name.LocalName == "href" && !a.Value.TrimStart().StartsWith('#')
                        && !a.Value.TrimStart().StartsWith("data:", StringComparison.OrdinalIgnoreCase))
            .ToList();
        foreach (var attribute in outside) attribute.Remove();
        using var stream = new MemoryStream();
        document.Save(stream);
        return stream.ToArray();
    }

    static MagickImage Read(byte[] svg, double density)
    {
        var settings = new MagickReadSettings { Format = MagickFormat.Svg, BackgroundColor = MagickColors.None, Density = new Density(density) };
        try { return new MagickImage(svg, settings); }
        catch (MagickException) { throw new MorphException("Couldn't draw the SVG"); }
    }

    /// Renders on a transparent background, at the SVG's own size raised to `MinimumPixel` on the long side, or
    /// exactly `maxPixel`: a vector scales up as cleanly as down.
    public static MagickImage Render(string path, int? maxPixel = null)
    {
        var svg = Contained(path);
        // Its own size at 96 dpi, where one SVG unit is one pixel; then drawn again at the density that gives the
        // size wanted, so curves and text are drawn sharp rather than scaled up.
        uint width, height;
        using (var probe = Read(svg, 96)) { width = probe.Width; height = probe.Height; }
        double longest = Math.Max(width, height);
        var target = maxPixel ?? Math.Clamp(longest, MinimumPixel, MaximumPixel);
        var scale = target / longest;
        var w = (uint)Math.Max(1, Math.Round(width * scale));
        var h = (uint)Math.Max(1, Math.Round(height * scale));
        var image = Read(svg, 96 * scale);
        if (image.Width != w || image.Height != h) image.Resize(new MagickGeometry(w, h) { IgnoreAspectRatio = true });
        return image;
    }

    /// Traces an image into an SVG of filled shapes. The palette size comes from `options.Colors`, or else from the
    /// compression level, which also sets how closely outlines follow the pixels: stronger makes simpler, smaller files.
    public static string Trace(string path, Options options)
    {
        using var image = ImageOps.Load(path);
        var settings = Tracer.Settings.For(options.Compression);
        if (options.Colors is int colors) settings.Colors = Math.Clamp(colors, 2, 64);
        // Big images are traced at about `WorkPixel` squared pixels (a cap on the long side would cost tall screenshots
        // their detail). Small ones are enlarged to 512 on the long side, so curves come out smooth rather than stepped;
        // enlarging anything bigger only stretches pixel noise into ragged edges.
        var fit = settings.WorkPixel / Math.Sqrt((double)image.Width * image.Height);
        var scale = fit < 1 ? fit : Math.Max(1, Math.Min(fit, 512.0 / Math.Max(image.Width, image.Height)));
        var w = (uint)Math.Max(1, Math.Round(image.Width * scale));
        var h = (uint)Math.Max(1, Math.Round(image.Height * scale));
        var sample = Pixels(image);
        Tracer.Bitmap work;
        using (var scaled = (MagickImage)image.Clone())
        {
            scaled.FilterType = FilterType.Lanczos;
            scaled.Resize(new MagickGeometry(w, h) { IgnoreAspectRatio = true });
            work = Pixels(scaled);
        }
        if (scale <= 1) sample = work;
        // The SVG keeps the image's size (or fits Max size); the shapes are in traced pixels, scaled by the viewBox.
        var size = options.MaxPixel is int max ? Math.Min(1, (double)max / Math.Max(image.Width, image.Height)) : 1;
        var svg = new Tracer(work, sample, settings).Svg((int)Math.Max(1, Math.Round(image.Width * size)), (int)Math.Max(1, Math.Round(image.Height * size)));
        var output = Output.For(path, "svg", options);
        File.WriteAllText(output, svg);
        return output;
    }

    /// Straight (not premultiplied) 8-bit RGBA.
    static Tracer.Bitmap Pixels(MagickImage image)
    {
        using var copy = (MagickImage)image.Clone();
        copy.ColorSpace = ColorSpace.sRGB;
        copy.Alpha(AlphaOption.Set);
        using var pixels = copy.GetPixelsUnsafe();
        var rgba = pixels.ToByteArray(PixelMapping.RGBA) ?? throw new MorphException("Couldn't read the image");
        return new Tracer.Bitmap((int)copy.Width, (int)copy.Height, rgba);
    }
}
