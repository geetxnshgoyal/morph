using System.Buffers.Binary;
using System.Security.Cryptography;
using ImageMagick;
using ImageMagick.Drawing;

namespace Morph;

public enum ImageFormat { Jpg, Png, Heic, Webp, Avif, Tiff, Gif, Bmp }

public static class ImageFormats
{
    static readonly Lazy<HashSet<MagickFormat>> writable = new(() =>
        MagickNET.SupportedFormats.Where(f => f.SupportsWriting).Select(f => f.Format).ToHashSet());

    public static string Extension(this ImageFormat format) => format.ToString().ToLowerInvariant();

    public static MagickFormat Magick(this ImageFormat format) => format switch
    {
        ImageFormat.Jpg => MagickFormat.Jpeg,
        ImageFormat.Png => MagickFormat.Png,
        ImageFormat.Heic => MagickFormat.Heic,
        ImageFormat.Webp => MagickFormat.WebP,
        ImageFormat.Avif => MagickFormat.Avif,
        ImageFormat.Tiff => MagickFormat.Tiff,
        ImageFormat.Gif => MagickFormat.Gif,
        _ => MagickFormat.Bmp,
    };

    /// Whether this build of ImageMagick can write the format (HEIC needs an HEVC encoder, which may be missing).
    public static bool IsAvailable(this ImageFormat format) => writable.Value.Contains(format.Magick());

    public static bool SupportsAlpha(this ImageFormat format) => format is not (ImageFormat.Jpg or ImageFormat.Bmp);

    public static bool IsLossy(this ImageFormat format) => format is ImageFormat.Jpg or ImageFormat.Heic or ImageFormat.Webp or ImageFormat.Avif;

    /// The format a file already is, by extension, if Morph can write it.
    public static ImageFormat? Of(string path) => FileKinds.Extension(path) switch
    {
        "jpg" or "jpeg" or "jpe" or "jfif" => ImageFormat.Jpg,
        "png" => ImageFormat.Png,
        "heic" or "heif" => ImageFormat.Heic,
        "webp" => ImageFormat.Webp,
        "avif" => ImageFormat.Avif,
        "tif" or "tiff" => ImageFormat.Tiff,
        "gif" => ImageFormat.Gif,
        "bmp" or "dib" => ImageFormat.Bmp,
        _ => null,
    };
}

public static class ImageOps
{
    /// Decodes the first frame with its EXIF orientation applied; downscales (never upscales) to `maxPixel`. SVGs are
    /// drawn at that size.
    public static MagickImage Load(string path, int? maxPixel = null)
    {
        if (VectorOps.IsSvg(path)) return VectorOps.Render(path, maxPixel);
        MagickImage image;
        try { image = new MagickImage(path); }
        catch (MagickException) { throw new MorphException($"{Path.GetFileName(path)} isn't a readable image"); }
        image.AutoOrient();
        if (maxPixel is int max && Math.Max(image.Width, image.Height) > max) image.Resize(new MagickGeometry((uint)max, (uint)max));
        return image;
    }

    static void Prepare(MagickImage image, ImageFormat format, double quality)
    {
        if (!format.SupportsAlpha() && image.HasAlpha)
        {
            image.BackgroundColor = MagickColors.White;
            image.Alpha(AlphaOption.Remove);
        }
        if (format.IsLossy()) image.Quality = (uint)Math.Clamp(Math.Round(quality * 100), 1, 100);
    }

    public static byte[] Encode(MagickImage image, ImageFormat format, double quality)
    {
        Prepare(image, format, quality);
        try { return image.ToByteArray(format.Magick()); }
        catch (MagickException e) { throw new MorphException($"Couldn't encode {format.Extension().ToUpperInvariant()}: {e.Message}"); }
    }

    public static void Write(MagickImage image, ImageFormat format, double quality, string path) =>
        File.WriteAllBytes(path, Encode(image, format, quality));

    /// The source's own format when Morph can write it, else PNG.
    public static ImageFormat OutputFormat(string path) =>
        ImageFormats.Of(path) is { } format && format.IsAvailable() ? format : ImageFormat.Png;

    // MARK: Actions

    public static string Convert(string path, ImageFormat format, Options options)
    {
        var output = Output.For(path, format.Extension(), options);
        // Animated GIFs and WebPs keep every frame when they become a GIF.
        if (format == ImageFormat.Gif && options.MaxPixel is null && FileKinds.Extension(path) is "gif" or "webp")
        {
            using var frames = new MagickImageCollection(path);
            if (frames.Count > 1)
            {
                frames.Coalesce();
                frames.Write(output, MagickFormat.Gif);
                return output;
            }
        }
        using var image = Load(path, options.MaxPixel);
        Write(image, format, options.Quality ?? 0.9, output);
        return output;
    }

    public static string Resize(string path, Options options)
    {
        if (options.ExactSize is { } size) return ResizeExactly(path, size, options);
        var format = OutputFormat(path);
        using var image = Load(path, options.MaxPixel ?? 2048);
        // Name by the size actually written: smaller images are never upscaled.
        var output = Output.For(path, format.Extension(), options, $"{Math.Max(image.Width, image.Height)}px");
        Write(image, format, options.Quality ?? 0.9, output);
        return output;
    }

    /// Exactly `size`, cropped to fill, as a JPG with no metadata: what passport, visa and exam forms ask for.
    /// With a caption, the name and the date the photo was taken go in a white strip at the bottom, inside the size.
    /// With a size limit, the JPG is fitted under it at that size.
    static string ResizeExactly(string path, PixelSize size, Options options)
    {
        // Decode big enough that cropping never has to stretch the photo.
        using var photo = Load(path, Math.Max(size.Width, size.Height) * 3);
        var taken = CaptureDate(photo) ?? DateTime.Now;
        var caption = options.Caption?.Trim() is { Length: > 0 } text ? text : null;
        uint w = (uint)size.Width, h = (uint)size.Height;
        var strip = caption is null ? 0u : (uint)Math.Max(Math.Round(h * 0.16), 18);
        var area = h - strip;
        // Cover the photo area, then crop: centred across, a bit above centre down (where faces are).
        photo.Resize(new MagickGeometry(w, area) { FillArea = true });
        photo.Crop(new MagickGeometry((int)(photo.Width - w) / 2, (int)Math.Round((photo.Height - area) * 0.3), w, area));
        photo.ResetPage();
        using var image = new MagickImage(MagickColors.White, w, h);
        image.Composite(photo, 0, 0, CompositeOperator.Over);
        if (caption is not null) DrawLines(image, [caption, taken.ToString("dd/MM/yyyy", System.Globalization.CultureInfo.InvariantCulture)], strip);
        image.Strip();
        var output = Output.For(path, ImageFormat.Jpg.Extension(), options, size.Key);
        if (options.TargetBytes is not long target)
        {
            Write(image, ImageFormat.Jpg, options.Quality ?? 0.92, output);
            return output;
        }
        // The size is fixed, so only quality can give: binary-search the best JPG that fits.
        double lo = 0.05, hi = 0.95;
        byte[]? best = null;
        for (var i = 0; i < 8; i++)
        {
            var mid = (lo + hi) / 2;
            var data = Encode(image, ImageFormat.Jpg, mid);
            if (data.Length <= target) { best = data; lo = mid; } else hi = mid;
        }
        if (best is null) throw new MorphException($"{size.Label} can't get under {SizeLimit.Label(target)}; pick a larger size limit");
        File.WriteAllBytes(output, best);
        return output;
    }

    /// Centred lines in the strip at the bottom (the first in bold), shrunk to fit the width.
    static void DrawLines(MagickImage image, string[] lines, uint strip)
    {
        double w = image.Width, h = image.Height;
        var size = strip * 0.36;
        // Roughly half an em per character is enough to keep long names inside the photo's width.
        var widest = lines.Max(l => l.Length) * 0.55 * size;
        if (widest > w * 0.92) size *= w * 0.92 / widest;
        var lineHeight = size * 1.15;
        var y = h - strip / 2.0 - lineHeight * (lines.Length - 1) / 2 + size * 0.35;
        for (var i = 0; i < lines.Length; i++)
        {
            var drawing = new Drawables().FontPointSize(size).FillColor(MagickColors.Black).TextAlignment(TextAlignment.Center);
            if (Fonts.SansFile(bold: i == 0) is { } font) drawing.Font(font);
            drawing.Text(w / 2, y, lines[i]).Draw(image);
            y += lineHeight;
        }
    }

    /// When the photo was taken, from its EXIF data.
    static DateTime? CaptureDate(MagickImage image) =>
        image.GetExifProfile()?.GetValue(ExifTag.DateTimeOriginal)?.Value is { } text
        && DateTime.TryParseExact(text, "yyyy:MM:dd HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture,
               System.Globalization.DateTimeStyles.None, out var date) ? date : null;

    /// Makes the file smaller without a visible change: re-encodes at a range of qualities, compares each with
    /// the original and keeps the smallest that still looks the same at the chosen compression level. Throws
    /// `MorphNote` when that saves under 5%, rather than writing a near-identical copy. With a target size, makes
    /// a JPEG (what upload forms accept), binary-searching quality and then downscaling until the file fits.
    public static string Compress(string path, Options options)
    {
        var image = Load(path, options.MaxPixel);
        try
        {
            var source = ImageFormats.Of(path);
            var originalBytes = Bytes.Of(path);
            if (options.TargetBytes is not long target)
            {
                var format = source is { } s && s.IsLossy() && s.IsAvailable() ? s
                    : image.HasAlpha ? (ImageFormat.Webp.IsAvailable() ? ImageFormat.Webp : ImageFormat.Png)
                    : ImageFormat.Jpg;
                byte[] data;
                if (options.Quality is double quality) data = Encode(image, format, quality);
                else
                {
                    var best = format.IsLossy() ? SmallestLookalike(image, format, options.Compression.MinimumSimilarity()) : Encode(image, format, 1);
                    if (best is null || best.Length >= originalBytes * 0.95)
                        throw new MorphNote($"{Path.GetFileName(path)} is already as small as it can get without losing quality");
                    data = best;
                }
                var output = Output.For(path, format.Extension(), options, "compressed");
                File.WriteAllBytes(output, data);
                return output;
            }
            if (source == ImageFormat.Jpg && originalBytes <= target)
                throw new MorphNote($"{Path.GetFileName(path)} is already under {SizeLimit.Label(target)}");
            var jpg = Output.For(path, ImageFormat.Jpg.Extension(), options, "compressed");
            var longest = Math.Max(image.Width, image.Height);
            for (var round = 0; round < 10; round++)
            {
                double lo = 0.05, hi = 0.95;
                byte[]? best = null;
                for (var i = 0; i < 7; i++)
                {
                    var mid = (lo + hi) / 2;
                    var data = Encode(image, ImageFormat.Jpg, mid);
                    if (data.Length <= target) { best = data; lo = mid; } else hi = mid;
                }
                if (best is not null) { File.WriteAllBytes(jpg, best); return jpg; }
                longest = (uint)(longest * 0.8);
                if (longest <= 64) break;
                image.Dispose();
                image = Load(path, (int)longest);
            }
            throw new MorphException($"Couldn't get {Path.GetFileName(path)} under {SizeLimit.Label(target)}");
        }
        finally { image.Dispose(); }
    }

    /// The smallest encoding that still scores at least `similarity` against `image`. Qualities are tried from
    /// high to low, stopping once quality clearly falls short: size and similarity aren't perfectly monotonic
    /// (encoders change chroma subsampling at some steps), so every passing step is kept and the smallest wins.
    static byte[]? SmallestLookalike(MagickImage image, ImageFormat format, double similarity)
    {
        using var sample = Sample(image);
        Prepare(sample, format, 1);
        var reference = new Similarity(sample);
        var qualities = Enumerable.Range(0, 14).Select(i => 0.95 - i * 0.05).ToArray();
        // The sample is small, so every quality is tried at once, one per core.
        var results = new (int Size, bool Passes)?[qualities.Length];
        Parallel.For(0, qualities.Length, i =>
        {
            try
            {
                using var copy = (MagickImage)sample.Clone();
                var data = Encode(copy, format, qualities[i]);
                using var decoded = new MagickImage(data);
                results[i] = (data.Length, reference.Score(decoded) >= similarity);
            }
            catch (MagickException) { }
            catch (MorphException) { }
        });
        // Read back from high quality to low, exactly as if they had been tried one by one.
        double? chosen = null;
        var chosenSize = int.MaxValue;
        var misses = 0;
        for (var i = 0; i < qualities.Length; i++)
        {
            if (results[i] is not { } result) continue;
            if (result.Passes)
            {
                misses = 0;
                if (result.Size < chosenSize) (chosen, chosenSize) = (qualities[i], result.Size);
            }
            // One step can dip and the next recover; two in a row means it only gets worse from here.
            else if (++misses == 2) break;
        }
        return chosen is double q ? Encode(image, format, q) : null;
    }

    /// Full-resolution patches from across the image, the 4×4 grid of 256-pixel squares that `Similarity` checks,
    /// packed into one 1024-pixel image. Patches sit on the 16-pixel grid JPEG blocks use, so each one compresses
    /// just as it does inside the whole image, and trying a quality on this costs a fraction of trying it on a big
    /// photo. Small images are used whole.
    static MagickImage Sample(MagickImage image)
    {
        const int side = 256;
        if (image.Width <= side * 2 && image.Height <= side * 2) return (MagickImage)image.Clone();
        int width = (int)image.Width, height = (int)image.Height;
        int w = Math.Min(side, width), h = Math.Min(side, height);
        var sample = new MagickImage(image.HasAlpha ? MagickColors.Transparent : MagickColors.White, (uint)w * 4, (uint)h * 4);
        for (var row = 0; row < 4; row++)
        {
            for (var column = 0; column < 4; column++)
            {
                int x = (width - w) * column / 3 / 16 * 16, y = (height - h) * row / 3 / 16 * 16;
                using var patch = image.CloneArea(x, y, (uint)w, (uint)h);
                sample.Composite(patch, column * w, row * h, CompositeOperator.Copy);
            }
        }
        return sample;
    }

    // MARK: Privacy

    public sealed record StripReport(string Output, IReadOnlyList<string> Removed, bool Lossless);

    /// Human-readable list of identifying metadata in the first frame.
    public static List<string> PrivateFields(string path)
    {
        using var image = new MagickImage(path);
        var found = new List<string>();
        if (image.GetExifProfile() is { } exif) Exif.Describe(Exif.Parse(exif.ToByteArray()).Tags, found);
        if (image.GetIptcProfile() is not null) found.Add("IPTC captions/credits");
        if (image.GetXmpProfile() is not null) found.Add("XMP");
        if (FileKinds.Extension(path) == "png" && Chunks.PngHasText(File.ReadAllBytes(path))) found.Add("PNG text");
        else if (!string.IsNullOrEmpty(image.Comment)) found.Add("Comment");
        return found;
    }

    /// Removes identifying metadata, keeping orientation. JPEG, PNG and WebP are rewritten byte for byte without
    /// the metadata, and the pixels are checked to be identical; anything else is re-encoded at full quality.
    public static StripReport StripMetadata(string path, Options options)
    {
        var removed = PrivateFields(path);
        var output = Output.For(path, FileKinds.Extension(path), options, "clean");
        var before = PixelHash(path);
        var bytes = File.ReadAllBytes(path);
        var stripped = FileKinds.Extension(path) switch
        {
            "jpg" or "jpeg" or "jpe" or "jfif" => Chunks.StripJpeg(bytes),
            "png" => Chunks.StripPng(bytes),
            "webp" => Chunks.StripWebp(bytes),
            _ => null,
        };
        if (stripped is not null)
        {
            File.WriteAllBytes(output, stripped);
            if (PrivateFields(output).Count == 0 && PixelHash(output) == before) return new StripReport(output, removed, true);
        }

        // Fallback: re-encode the upright pixels with nothing attached.
        using (var image = Load(path))
        {
            image.Strip();
            image.Comment = null;
            Write(image, OutputFormat(path), 1.0, output);
        }
        if (PrivateFields(output).Count > 0)
        {
            File.Delete(output);
            throw new MorphException("Private metadata survived; no output was saved");
        }
        return new StripReport(output, removed, PixelHash(output) == before);
    }

    /// SHA-256 of the decoded, un-oriented pixels: proves a clean copy is visually identical.
    static string? PixelHash(string path)
    {
        try
        {
            using var image = new MagickImage(path);
            using var pixels = image.GetPixelsUnsafe();
            return System.Convert.ToHexString(SHA256.HashData(pixels.ToByteArray(PixelMapping.RGBA) ?? []));
        }
        catch (MagickException) { return null; }
    }

    public static Dictionary<string, string> Summary(string path)
    {
        var info = new MagickImageInfo(path);
        var privateFields = PrivateFields(path);
        return new()
        {
            ["Type"] = info.Format.ToString(),
            ["Size"] = $"{info.Width} × {info.Height}",
            ["Private metadata"] = privateFields.Count == 0 ? "none" : string.Join(", ", privateFields),
        };
    }
}

/// Just enough of the EXIF (TIFF) layout to list which tags are present and read the orientation.
static class Exif
{
    public static (HashSet<int> Tags, int Orientation) Parse(byte[]? data)
    {
        var tags = new HashSet<int>();
        var orientation = 1;
        if (data is null) return (tags, orientation);
        var span = data.AsSpan();
        if (span.StartsWith("Exif\0\0"u8)) span = span[6..];
        if (span.Length < 8) return (tags, orientation);
        var little = span[0] == (byte)'I';
        var tiff = span.ToArray();
        int U16(long at) => at + 2 > tiff.Length ? 0 : little ? BinaryPrimitives.ReadUInt16LittleEndian(tiff.AsSpan((int)at)) : BinaryPrimitives.ReadUInt16BigEndian(tiff.AsSpan((int)at));
        long U32(long at) => at + 4 > tiff.Length ? 0 : little ? BinaryPrimitives.ReadUInt32LittleEndian(tiff.AsSpan((int)at)) : BinaryPrimitives.ReadUInt32BigEndian(tiff.AsSpan((int)at));
        if (U16(2) != 42) return (tags, orientation);

        var visited = new HashSet<long>();
        void Directory(long offset, int depth)
        {
            if (depth > 3 || offset <= 0 || offset + 2 > tiff.Length || !visited.Add(offset)) return;
            var count = U16(offset);
            for (var i = 0; i < count; i++)
            {
                var entry = offset + 2 + i * 12;
                if (entry + 12 > tiff.Length) break;
                var tag = U16(entry);
                tags.Add(tag);
                if (tag == 0x0112 && U16(entry + 2) == 3) orientation = U16(entry + 8);
                // Exif, GPS and interoperability sub-directories.
                if (tag is 0x8769 or 0x8825 or 0xA005) Directory(U32(entry + 8), depth + 1);
            }
        }
        Directory(U32(4), 0);
        return (tags, orientation);
    }

    public static void Describe(HashSet<int> tags, List<string> found)
    {
        void Flag(string label, params int[] ids) { if (ids.Any(tags.Contains) && !found.Contains(label)) found.Add(label); }
        Flag("GPS location", 0x8825);
        Flag("Capture date", 0x9003, 0x9004, 0x0132);
        Flag("Lens", 0xA433, 0xA434);
        Flag("Serial numbers", 0xA431, 0xA435);
        Flag("Owner name", 0xA430);
        Flag("Comment", 0x9286, 0x010E);
        Flag("Camera settings", 0x829A, 0x8827, 0x829D);
        Flag("Camera make/model", 0x010F, 0x0110);
        Flag("Software/device", 0x0131, 0x013C);
        Flag("Author/copyright", 0x013B, 0x8298);
        Flag("Maker notes", 0x927C);
    }

    /// An APP1 segment holding nothing but the orientation, so a cleaned photo still shows the right way up.
    public static byte[] OrientationOnlyApp1(int orientation)
    {
        var body = new byte[32];
        "Exif\0\0II"u8.CopyTo(body);
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(8), 42);
        BinaryPrimitives.WriteUInt32LittleEndian(body.AsSpan(10), 8);
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(14), 1);
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(16), 0x0112);
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(18), 3);
        BinaryPrimitives.WriteUInt32LittleEndian(body.AsSpan(20), 1);
        BinaryPrimitives.WriteUInt16LittleEndian(body.AsSpan(24), (ushort)orientation);
        var segment = new byte[4 + body.Length];
        segment[0] = 0xFF;
        segment[1] = 0xE1;
        BinaryPrimitives.WriteUInt16BigEndian(segment.AsSpan(2), (ushort)(body.Length + 2));
        body.CopyTo(segment, 4);
        return segment;
    }
}

/// Lossless metadata removal by dropping chunks and segments; the compressed image data is copied untouched.
static class Chunks
{
    /// Keeps the frame, tables, JFIF, ICC and Adobe colour segments; drops EXIF, XMP, IPTC, comments, maker
    /// segments and anything after the image ends (multi-picture trailers, embedded motion clips).
    public static byte[]? StripJpeg(byte[] data)
    {
        if (data.Length < 4 || data[0] != 0xFF || data[1] != 0xD8) return null;
        var orientation = Segments(data).Where(s => s.Marker == 0xE1).Select(s => data.AsSpan(s.Start + 4, s.Length - 2).ToArray())
            .Where(p => p.AsSpan().StartsWith("Exif\0\0"u8)).Select(p => Exif.Parse(p).Orientation).FirstOrDefault(1);
        using var output = new MemoryStream(data.Length);
        output.Write(data, 0, 2);
        // The orientation goes right after SOI (after JFIF when there is one), where readers look for EXIF.
        var placed = orientation is < 2 or > 8;
        foreach (var (marker, start, length) in Segments(data))
        {
            if (!placed && marker != 0xE0) { output.Write(Exif.OrientationOnlyApp1(orientation)); placed = true; }
            if (marker == 0xDA)
            {
                output.Write(data, start, EndOfImage(data, start) - start);
                return output.ToArray();
            }
            var payload = data.AsSpan(start + 4, Math.Max(length - 2, 0));
            var keep = marker switch
            {
                0xE0 => true,                                   // JFIF
                0xE2 => payload.StartsWith("ICC_PROFILE\0"u8),  // colour profile, but not the MPF index
                0xEE => true,                                   // Adobe colour transform, needed to decode CMYK
                >= 0xE1 and <= 0xEF => false,
                0xFE => false,                                  // comment
                _ => true,
            };
            if (keep) output.Write(data, start, 2 + length);
        }
        return null;
    }

    /// Marker segments up to and including the first start-of-scan, whose length is left at 0.
    static IEnumerable<(byte Marker, int Start, int Length)> Segments(byte[] data)
    {
        var pos = 2;
        while (pos + 4 <= data.Length && data[pos] == 0xFF)
        {
            var marker = data[pos + 1];
            if (marker == 0xFF) { pos++; continue; }
            if (marker == 0xDA) { yield return (marker, pos, 0); yield break; }
            if (marker is >= 0xD0 and <= 0xD7 or 0x01) { pos += 2; continue; }
            var length = BinaryPrimitives.ReadUInt16BigEndian(data.AsSpan(pos + 2));
            if (length < 2 || pos + 2 + length > data.Length) yield break;
            yield return (marker, pos, length);
            pos += 2 + length;
        }
    }

    /// In entropy-coded data 0xFF is always followed by 0x00 or a restart marker, so the first FFD9 ends the image.
    static int EndOfImage(byte[] data, int from)
    {
        for (var i = from; i + 1 < data.Length; i++)
            if (data[i] == 0xFF && data[i + 1] == 0xD9) return i + 2;
        return data.Length;
    }

    static readonly HashSet<string> pngDropped = ["tEXt", "zTXt", "iTXt", "eXIf", "tIME"];

    public static byte[]? StripPng(byte[] data) => FilterPng(data, out _);

    public static bool PngHasText(byte[] data)
    {
        FilterPng(data, out var dropped);
        return dropped.Any(t => t is "tEXt" or "zTXt" or "iTXt");
    }

    static byte[]? FilterPng(byte[] data, out List<string> dropped)
    {
        dropped = [];
        ReadOnlySpan<byte> signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        if (!data.AsSpan().StartsWith(signature)) return null;
        using var output = new MemoryStream(data.Length);
        output.Write(signature);
        var pos = 8;
        while (pos + 12 <= data.Length)
        {
            var length = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(pos));
            if (length < 0 || pos + 12 + length > data.Length) return null;
            var type = System.Text.Encoding.ASCII.GetString(data, pos + 4, 4);
            if (pngDropped.Contains(type)) dropped.Add(type);
            else output.Write(data, pos, 12 + length);
            pos += 12 + length;
            if (type == "IEND") break;
        }
        return output.ToArray();
    }

    /// Drops the EXIF and XMP chunks of an extended WebP and clears their flags.
    public static byte[]? StripWebp(byte[] data)
    {
        if (data.Length < 12 || !data.AsSpan().StartsWith("RIFF"u8) || !data.AsSpan(8).StartsWith("WEBP"u8)) return null;
        using var output = new MemoryStream(data.Length);
        output.Write(data, 0, 12);
        var pos = 12;
        while (pos + 8 <= data.Length)
        {
            var type = System.Text.Encoding.ASCII.GetString(data, pos, 4);
            var size = (int)BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(pos + 4));
            var padded = size + (size & 1);
            if (size < 0 || pos + 8 + size > data.Length) return null;
            var chunk = data.AsSpan(pos, Math.Min(8 + padded, data.Length - pos)).ToArray();
            if (type == "VP8X" && chunk.Length > 8) chunk[8] &= unchecked((byte)~(0x08 | 0x04));
            if (type is not ("EXIF" or "XMP ")) output.Write(chunk);
            pos += 8 + padded;
        }
        var bytes = output.ToArray();
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(4), (uint)(bytes.Length - 8));
        return bytes;
    }
}
