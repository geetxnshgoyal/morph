using ImageMagick;
using PdfSharp.Drawing;
using PdfSharp.Pdf;
using PdfSharp.Pdf.Advanced;
using PdfSharp.Pdf.IO;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;
using PigDocument = UglyToad.PdfPig.PdfDocument;

namespace Morph;

public static class PdfOps
{
    static PdfDocument Open(string path, PdfDocumentOpenMode mode)
    {
        Fonts.Install();
        try { return PdfReader.Open(path, mode); }
        catch (PdfReaderException e) when (e.Message.Contains("password", StringComparison.OrdinalIgnoreCase))
        {
            throw new MorphException($"{Path.GetFileName(path)} is password-protected");
        }
        catch (Exception e) when (e is not MorphException)
        {
            throw new MorphException($"{Path.GetFileName(path)} isn't a readable PDF");
        }
    }

    public static string Merge(IReadOnlyList<string> paths, Options options)
    {
        if (paths.Count == 0) throw new MorphException("Nothing to merge");
        using var merged = new PdfDocument();
        foreach (var path in paths)
        {
            using var document = Open(path, PdfDocumentOpenMode.Import);
            foreach (var page in document.Pages) merged.AddPage(page);
        }
        var output = Output.Unique(options.OutputDirectory ?? Output.FolderOf(paths[0]), "Merged", "pdf");
        merged.Save(output);
        return output;
    }

    public static string Split(string path, Options options)
    {
        using var document = Open(path, PdfDocumentOpenMode.Import);
        var folder = Output.Folder(path, "pages", options);
        for (var i = 0; i < document.PageCount; i++)
        {
            using var single = new PdfDocument();
            single.AddPage(document.Pages[i]);
            single.Save(Path.Combine(folder, $"page {i + 1:000}.pdf"));
        }
        return folder;
    }

    /// One A4-width page per image, in drop order.
    public static string FromImages(IReadOnlyList<string> paths, Options options)
    {
        if (paths.Count == 0) throw new MorphException("No images");
        var name = paths.Count == 1 ? Path.GetFileNameWithoutExtension(paths[0]) : "Images";
        var output = Output.Unique(options.OutputDirectory ?? Output.FolderOf(paths[0]), name, "pdf");
        using var document = new PdfDocument();
        foreach (var path in paths)
        {
            using var image = ImageOps.Load(path, options.MaxPixel ?? 3000);
            // Photos go in as JPEG; anything with transparency stays lossless.
            var bytes = image.HasAlpha ? ImageOps.Encode(image, ImageFormat.Png, 1) : ImageOps.Encode(image, ImageFormat.Jpg, options.Quality ?? 0.9);
            var page = document.AddPage();
            page.Width = XUnit.FromPoint(595);
            page.Height = XUnit.FromPoint(595.0 * image.Height / image.Width);
            using var graphics = XGraphics.FromPdfPage(page);
            using var stream = new MemoryStream(bytes);
            using var picture = XImage.FromStream(stream);
            graphics.DrawImage(picture, 0, 0, page.Width.Point, page.Height.Point);
        }
        document.Save(output);
        return output;
    }

    public static async Task<string> ToImages(string path, Options options, CancellationToken cancel)
    {
        var pages = await RenderPages(path, cancel);
        var folder = Output.Folder(path, "images", options);
        for (var i = 0; i < pages.Count; i++)
            await File.WriteAllBytesAsync(Path.Combine(folder, $"page {i + 1:000}.png"), pages[i], cancel);
        return folder;
    }

    /// Every page as a PNG at 144 dpi.
    static Task<IReadOnlyList<byte[]>> RenderPages(string path, CancellationToken cancel, int? onlyPage = null) =>
#if WINDOWS
        WinPdf.Render(path, 2, onlyPage, cancel);
#else
        throw new MorphException("Turning PDF pages into images needs Windows");
#endif

    /// Embedded text where present, OCR for scanned pages (on Windows).
    public static async Task<string> Text(string path, CancellationToken cancel = default)
    {
        var pages = new List<string>();
        try
        {
            using var document = PigDocument.Open(path);
            foreach (var page in document.GetPages())
            {
                var text = ContentOrderTextExtractor.GetText(page).Trim();
                if (text.Length == 0 && Platform.HasWindowsApis)
                {
                    var rendered = await RenderPages(path, cancel, page.Number - 1);
                    if (rendered.Count > 0)
                    {
                        using var image = new MagickImage(rendered[0]);
                        text = await VisionOps.RecognizeText(image, cancel);
                    }
                }
                pages.Add(text);
            }
        }
        catch (Exception e) when (e is not (MorphException or OperationCanceledException))
        {
            throw new MorphException(e.Message.Contains("encrypt", StringComparison.OrdinalIgnoreCase)
                ? $"{Path.GetFileName(path)} is password-protected" : $"{Path.GetFileName(path)} isn't a readable PDF");
        }
        return string.Join("\n\n", pages.Where(p => p.Length > 0));
    }

    public static async Task<string> ToText(string path, Options options, CancellationToken cancel)
    {
        var text = await Text(path, cancel);
        var output = Output.For(path, "txt", options);
        await File.WriteAllTextAsync(output, text, cancel);
        return output;
    }

    /// Re-saves with photos recompressed at screen resolution and streams deflated. Text stays selectable.
    public static string Compress(string path, Options options)
    {
        using var document = Open(path, PdfDocumentOpenMode.Modify);
        var quality = (uint)Math.Round((options.Quality ?? options.Compression.ImageQuality()) * 100);
        var longest = (uint)(options.Compression switch { CompressionLevel.Light => 2400, CompressionLevel.Balanced => 1600, _ => 1100 });
        foreach (var item in document.Internals.GetAllObjects())
        {
            if (item is not PdfDictionary { Stream: { } stream } image || image.Elements.GetName("/Subtype") != "/Image") continue;
            if (!IsPlainJpeg(image)) continue;
            try
            {
                using var picture = new MagickImage(stream.Value);
                if (Math.Max(picture.Width, picture.Height) > longest) picture.Resize(new MagickGeometry(longest, longest));
                picture.Strip();
                picture.Quality = quality;
                var smaller = picture.ToByteArray(MagickFormat.Jpeg);
                if (smaller.Length >= stream.Value.Length * 0.9) continue;
                stream.Value = smaller;
                image.Elements.SetInteger("/Width", (int)picture.Width);
                image.Elements.SetInteger("/Height", (int)picture.Height);
                image.Elements.SetInteger("/BitsPerComponent", 8);
            }
            catch (MagickException) { }
        }
        document.Options.CompressContentStreams = true;
        document.Options.NoCompression = false;
        document.Options.FlateEncodeMode = PdfFlateEncodeMode.BestCompression;
        var output = Output.For(path, "pdf", options, "compressed");
        document.Save(output);
        return output;
    }

    /// A JPEG image in RGB or grey with no decode tricks, which can be swapped for a smaller JPEG safely.
    static bool IsPlainJpeg(PdfDictionary image)
    {
        var filter = image.Elements["/Filter"];
        var isJpeg = filter switch
        {
            PdfName name => name.Value == "/DCTDecode",
            PdfArray { Elements.Count: 1 } array => array.Elements[0] is PdfName { Value: "/DCTDecode" },
            _ => false,
        };
        if (!isJpeg || image.Elements.ContainsKey("/Decode")) return false;
        return image.Elements["/ColorSpace"] switch
        {
            PdfName name => name.Value is "/DeviceRGB" or "/DeviceGray",
            PdfArray array => array.Elements.Count == 2 && array.Elements[0] is PdfName { Value: "/ICCBased" },
            _ => false,
        };
    }
}
