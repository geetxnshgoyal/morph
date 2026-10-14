using ImageMagick;
using Windows.Graphics.Imaging;
using Windows.Media.FaceAnalysis;
using Windows.Media.Ocr;
using Windows.Security.Cryptography;

namespace Morph;

/// Windows' built-in text recognition and face detection, both fully on-device.
static class WinVision
{
    /// A BGRA copy of `image`, flattened onto white and no larger than `maxSide`, with the factor it was shrunk by.
    static (SoftwareBitmap Bitmap, double Scale) Bitmap(MagickImage image, uint maxSide)
    {
        using var copy = (MagickImage)image.Clone();
        var scale = 1.0;
        if (Math.Max(copy.Width, copy.Height) > maxSide)
        {
            scale = (double)maxSide / Math.Max(copy.Width, copy.Height);
            copy.Resize(new MagickGeometry(maxSide, maxSide));
        }
        if (copy.HasAlpha)
        {
            copy.BackgroundColor = MagickColors.White;
            copy.Alpha(AlphaOption.Remove);
        }
        using var pixels = copy.GetPixelsUnsafe();
        var buffer = CryptographicBuffer.CreateFromByteArray(pixels.ToByteArray(PixelMapping.BGRA) ?? []);
        return (SoftwareBitmap.CreateCopyFromBuffer(buffer, BitmapPixelFormat.Bgra8, (int)copy.Width, (int)copy.Height, BitmapAlphaMode.Premultiplied), scale);
    }

    public static async Task<IReadOnlyList<TextLine>> Ocr(MagickImage image, CancellationToken cancel)
    {
        var engine = OcrEngine.TryCreateFromUserProfileLanguages()
            ?? throw new MorphException("Windows has no text recognition language installed. Add one in Settings → Time & language → Language & region.");
        var (bitmap, scale) = Bitmap(image, OcrEngine.MaxImageDimension);
        using (bitmap)
        {
            var result = await engine.RecognizeAsync(bitmap).AsTask(cancel);
            return result.Lines.Select(line => new TextLine(line.Text, line.Words.Select(w =>
                (w.Text, new Box(w.BoundingRect.X / scale, w.BoundingRect.Y / scale, w.BoundingRect.Width / scale, w.BoundingRect.Height / scale))).ToList())).ToList();
        }
    }

    public static async Task<IReadOnlyList<Box>> Faces(MagickImage image, CancellationToken cancel)
    {
        if (!FaceDetector.IsSupported) throw new MorphException("Face detection isn't available on this PC");
        var detector = await FaceDetector.CreateAsync().AsTask(cancel);
        var (bitmap, scale) = Bitmap(image, 1600);
        using (bitmap)
        using (var gray = SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Gray8))
        {
            var faces = await detector.DetectFacesAsync(gray).AsTask(cancel);
            return faces.Select(f => new Box(f.FaceBox.X / scale, f.FaceBox.Y / scale, f.FaceBox.Width / scale, f.FaceBox.Height / scale)).ToList();
        }
    }
}
