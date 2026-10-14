using System.Text.RegularExpressions;
using ImageMagick;
using ZXing;
using ZXing.Common;

namespace Morph;

/// A rectangle in image pixels, top-left origin.
public readonly record struct Box(double X, double Y, double Width, double Height)
{
    public Box Union(Box other)
    {
        var x = Math.Min(X, other.X);
        var y = Math.Min(Y, other.Y);
        return new Box(x, y, Math.Max(X + Width, other.X + other.Width) - x, Math.Max(Y + Height, other.Y + other.Height) - y);
    }
}

public sealed record TextLine(string Text, IReadOnlyList<(string Text, Box Box)> Words);

public static class VisionOps
{
    // MARK: Codes

    /// QR codes and barcodes in an image, or on every page of a PDF.
    public static async Task<IReadOnlyList<string>> Codes(string path, CancellationToken cancel = default)
    {
        var images = new List<MagickImage>();
        try
        {
            if (FileKinds.Of(path) == FileKind.Pdf)
            {
#if WINDOWS
                foreach (var page in await WinPdf.Render(path, 2, null, cancel)) images.Add(new MagickImage(page));
#else
                throw new MorphException("Reading codes in PDFs needs Windows");
#endif
            }
            else images.Add(ImageOps.Load(path, 2400));

            var reader = new BarcodeReaderGeneric
            {
                AutoRotate = true,
                Options = new DecodingOptions { TryHarder = true, TryInverted = true },
            };
            var seen = new List<string>();
            foreach (var image in images)
            {
                using var pixels = image.GetPixelsUnsafe();
                var bytes = pixels.ToByteArray(PixelMapping.BGRA) ?? [];
                var source = new RGBLuminanceSource(bytes, (int)image.Width, (int)image.Height, RGBLuminanceSource.BitmapFormat.BGRA32);
                foreach (var result in reader.DecodeMultiple(source) ?? [])
                    if (!seen.Contains(result.Text)) seen.Add(result.Text);
            }
            return seen;
        }
        finally
        {
            foreach (var image in images) image.Dispose();
        }
    }

    public static async Task<string> ReadCodes(string path, Options options, CancellationToken cancel)
    {
        var codes = await Codes(path, cancel);
        if (codes.Count == 0) throw new MorphException($"No QR codes or barcodes found in {Path.GetFileName(path)}");
        var output = Output.For(path, "txt", options, "codes");
        await File.WriteAllTextAsync(output, string.Join("\n", codes), cancel);
        return output;
    }

    // MARK: Text

    public static async Task<IReadOnlyList<TextLine>> RecognizeLines(MagickImage image, CancellationToken cancel = default)
    {
#if WINDOWS
        return await WinVision.Ocr(image, cancel);
#else
        await Task.CompletedTask;
        throw new MorphException("Text recognition needs Windows");
#endif
    }

    public static async Task<string> RecognizeText(MagickImage image, CancellationToken cancel = default) =>
        string.Join("\n", (await RecognizeLines(image, cancel)).Select(l => l.Text));

    public static async Task<string> Ocr(string path, Options options, CancellationToken cancel)
    {
        if (FileKinds.Of(path) == FileKind.Pdf) return await PdfOps.ToText(path, options, cancel);
        using var image = ImageOps.Load(path);
        var text = await RecognizeText(image, cancel);
        if (text.Trim().Length == 0) throw new MorphException($"No text found in {Path.GetFileName(path)}");
        var output = Output.For(path, "txt", options);
        await File.WriteAllTextAsync(output, text, cancel);
        return output;
    }

    // MARK: Redaction

    /// Patterns treated as personal info when redacting text in screenshots.
    static readonly Regex[] sensitivePatterns = new[]
    {
        @"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}",      // email
        @"\+?\d[\d\s().-]{7,}\d",                        // phone
        @"\b(?:\d[ -]?){13,19}\b",                       // card number
        @"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b",             // IBAN
        @"\b\d{3}-\d{2}-\d{4}\b",                        // SSN
        @"\b\d{4}\s?\d{4}\s?\d{4}\b",                    // Aadhaar
        @"\b[A-Z]{5}\d{4}[A-Z]\b",                       // PAN
        @"(?:\d{1,3}\.){3}\d{1,3}",                      // IPv4
    }.Select(p => new Regex(p, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)).ToArray();

    /// Boxes around recognised words that are part of a personal-info match.
    public static List<Box> SensitiveBoxes(IReadOnlyList<TextLine> lines)
    {
        var boxes = new List<Box>();
        foreach (var line in lines)
        {
            // Match against the words as OCR spaced them, then map each match back to the words it covers.
            var starts = new List<int>();
            var text = "";
            foreach (var (word, _) in line.Words)
            {
                if (text.Length > 0) text += " ";
                starts.Add(text.Length);
                text += word;
            }
            foreach (var pattern in sensitivePatterns)
            {
                foreach (Match match in pattern.Matches(text))
                {
                    Box? box = null;
                    for (var i = 0; i < line.Words.Count; i++)
                    {
                        var start = starts[i];
                        var end = start + line.Words[i].Text.Length;
                        if (end <= match.Index || start >= match.Index + match.Length) continue;
                        box = box is { } b ? b.Union(line.Words[i].Box) : line.Words[i].Box;
                    }
                    if (box is { } found) boxes.Add(found);
                }
            }
        }
        return boxes;
    }

    /// Pixelates (averaged down to a coarse grid, so it can't be undone) or blacks out each box, grown by `padding`.
    public static void Redact(MagickImage image, IEnumerable<Box> boxes, RedactStyle style, double padding)
    {
        foreach (var b in boxes)
        {
            var x = (int)Math.Max(0, Math.Floor(b.X - b.Width * padding));
            var y = (int)Math.Max(0, Math.Floor(b.Y - b.Height * padding));
            var right = (int)Math.Min(image.Width, Math.Ceiling(b.X + b.Width * (1 + padding)));
            var bottom = (int)Math.Min(image.Height, Math.Ceiling(b.Y + b.Height * (1 + padding)));
            if (right <= x || bottom <= y) continue;
            var width = (uint)(right - x);
            var height = (uint)(bottom - y);
            using var patch = style == RedactStyle.Solid
                ? new MagickImage(MagickColors.Black, width, height)
                : (MagickImage)image.CloneArea(x, y, width, height);
            if (style == RedactStyle.Pixelate)
            {
                const uint blocks = 8;
                patch.Resize(new MagickGeometry(blocks, Math.Max(1, (uint)Math.Round(blocks * (double)height / width))) { IgnoreAspectRatio = true });
                patch.Sample(new MagickGeometry(width, height) { IgnoreAspectRatio = true });
            }
            image.Composite(patch, x, y, CompositeOperator.Over);
        }
    }

    static async Task<string> RedactFile(string path, Options options, double padding, RedactStyle style,
                                         Func<MagickImage, Task<List<Box>>> detect, string none)
    {
        using var image = ImageOps.Load(path);
        var boxes = await detect(image);
        if (boxes.Count == 0) throw new MorphException(none);
        Redact(image, boxes, style, padding);
        var format = ImageOps.OutputFormat(path);
        var output = Output.For(path, format.Extension(), options, "redacted");
        // Metadata is deliberately dropped: a redacted photo shouldn't leak where it was taken.
        image.Strip();
        ImageOps.Write(image, format, 0.92, output);
        return output;
    }

    public static Task<string> RedactFaces(string path, Options options, CancellationToken cancel) =>
        RedactFile(path, options, 0.2, options.RedactStyle,
#if WINDOWS
            async image => [.. await WinVision.Faces(image, cancel)],
#else
            _ => throw new MorphException("Face detection needs Windows"),
#endif
            $"No faces found in {Path.GetFileName(path)}");

    public static Task<string> RedactPersonalInfo(string path, Options options, CancellationToken cancel) =>
        RedactFile(path, options, 0.08, RedactStyle.Solid, async image => SensitiveBoxes(await RecognizeLines(image, cancel)),
            $"No emails, phone or card numbers found in {Path.GetFileName(path)}");
}
