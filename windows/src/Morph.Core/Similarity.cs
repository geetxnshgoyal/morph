using ImageMagick;

namespace Morph;

/// How alike two images look: mean SSIM (structural similarity) of their luminance, where 1 means identical.
/// Measured at full resolution on up to 16 tiles spread across the frame, so compression artifacts aren't
/// hidden by downscaling and big photos stay quick to check.
sealed class Similarity
{
    readonly List<(int X, int Y, int Width, int Height)> tiles;
    readonly List<byte[]> reference;

    public Similarity(MagickImage image)
    {
        tiles = Tiles((int)image.Width, (int)image.Height);
        reference = tiles.Select(t => Luma(image, t)).ToList();
    }

    public double Score(MagickImage candidate)
    {
        var total = 0.0;
        for (var i = 0; i < tiles.Count; i++)
            total += Ssim(reference[i], Luma(candidate, tiles[i]), tiles[i].Width, tiles[i].Height);
        return total / Math.Max(tiles.Count, 1);
    }

    /// A 4×4 grid of 256-pixel tiles, or the whole image if it's small.
    static List<(int, int, int, int)> Tiles(int width, int height)
    {
        const int side = 256;
        if (width <= side * 2 && height <= side * 2) return [(0, 0, width, height)];
        int w = Math.Min(side, width), h = Math.Min(side, height);
        var rects = new List<(int, int, int, int)>();
        for (var row = 0; row < 4; row++)
            for (var column = 0; column < 4; column++)
                rects.Add(((width - w) * column / 3, (height - h) * row / 3, w, h));
        return rects;
    }

    /// Grey levels of a tile, with any transparency composited over white.
    static byte[] Luma(MagickImage image, (int X, int Y, int Width, int Height) tile)
    {
        var (x, y, w, h) = tile;
        using var pixels = image.GetPixelsUnsafe();
        var rgba = pixels.ToByteArray(x, y, (uint)w, (uint)h, PixelMapping.RGBA) ?? [];
        var luma = new byte[w * h];
        for (var i = 0; i < luma.Length && i * 4 + 3 < rgba.Length; i++)
        {
            var grey = (rgba[i * 4] * 299 + rgba[i * 4 + 1] * 587 + rgba[i * 4 + 2] * 114) / 1000.0;
            var alpha = rgba[i * 4 + 3] / 255.0;
            luma[i] = (byte)Math.Round(grey * alpha + 255 * (1 - alpha));
        }
        return luma;
    }

    /// Mean SSIM over 8×8 windows stepping 4 pixels at a time, with window sums from summed-area tables.
    static double Ssim(byte[] a, byte[] b, int width, int height)
    {
        const int window = 8;
        if (width < window || height < window) return a.AsSpan().SequenceEqual(b) ? 1 : 0;
        var stride = width + 1;
        // Tables for a, b, a², b² and a·b, interleaved: entry (x, y) holds the sums above and left of it.
        var t = new double[stride * (height + 1) * 5];
        for (var y = 0; y < height; y++)
        {
            double s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0;
            for (var x = 0; x < width; x++)
            {
                double va = a[y * width + x], vb = b[y * width + x];
                s0 += va; s1 += vb; s2 += va * va; s3 += vb * vb; s4 += va * vb;
                int here = ((y + 1) * stride + x + 1) * 5, above = (y * stride + x + 1) * 5;
                t[here] = t[above] + s0;
                t[here + 1] = t[above + 1] + s1;
                t[here + 2] = t[above + 2] + s2;
                t[here + 3] = t[above + 3] + s3;
                t[here + 4] = t[above + 4] + s4;
            }
        }
        double Box(int k, int x, int y) =>
            t[((y + window) * stride + x + window) * 5 + k] - t[(y * stride + x + window) * 5 + k]
            - t[((y + window) * stride + x) * 5 + k] + t[(y * stride + x) * 5 + k];

        const double n = window * window, c1 = 6.5025, c2 = 58.5225;   // (0.01·255)², (0.03·255)²
        double total = 0;
        var count = 0;
        for (var y = 0; y <= height - window; y += 4)
        {
            for (var x = 0; x <= width - window; x += 4)
            {
                double meanA = Box(0, x, y) / n, meanB = Box(1, x, y) / n;
                var varA = (Box(2, x, y) - n * meanA * meanA) / (n - 1);
                var varB = (Box(3, x, y) - n * meanB * meanB) / (n - 1);
                var cov = (Box(4, x, y) - n * meanA * meanB) / (n - 1);
                total += (2 * meanA * meanB + c1) * (2 * cov + c2) / ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2));
                count++;
            }
        }
        return total / count;
    }
}
