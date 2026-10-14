using Windows.Data.Pdf;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Morph;

/// PDF pages to pictures with Windows' own PDF renderer (the one Edge uses).
static class WinPdf
{
    /// PNGs of every page, or of one, at `scale` × 72 dpi.
    public static async Task<IReadOnlyList<byte[]>> Render(string path, double scale, int? onlyPage, CancellationToken cancel)
    {
        PdfDocument document;
        try { document = await PdfDocument.LoadFromFileAsync(await StorageFile.GetFileFromPathAsync(path)).AsTask(cancel); }
        catch (Exception e) when (e.HResult == unchecked((int)0x8007052B))
        {
            throw new MorphException($"{Path.GetFileName(path)} is password-protected");
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            throw new MorphException($"{Path.GetFileName(path)} isn't a readable PDF");
        }
        var pages = new List<byte[]>();
        IEnumerable<int> indices = onlyPage is int one ? [one] : Enumerable.Range(0, (int)document.PageCount);
        foreach (var index in indices)
        {
            cancel.ThrowIfCancellationRequested();
            using var page = document.GetPage((uint)index);
            using var stream = new InMemoryRandomAccessStream();
            // Page sizes are in 96 dpi pixels; scale 2 is 144 dpi, like the Mac app.
            await page.RenderToStreamAsync(stream, new PdfPageRenderOptions
            {
                DestinationWidth = (uint)Math.Max(1, Math.Round(page.Size.Width * scale * 0.75)),
                BitmapEncoderId = BitmapEncoder.PngEncoderId,
            }).AsTask(cancel);
            stream.Seek(0);
            using var reader = stream.AsStreamForRead();
            using var memory = new MemoryStream();
            await reader.CopyToAsync(memory, cancel);
            pages.Add(memory.ToArray());
        }
        return pages;
    }
}
