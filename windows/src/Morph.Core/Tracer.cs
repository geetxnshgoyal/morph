using System.Globalization;
using System.Text;

namespace Morph;

/// Turns pixels into an SVG of filled shapes, the way potrace and VTracer do: the colors are reduced to a small
/// palette, specks are folded into what surrounds them, and each color's outline is traced along the pixel edges,
/// evened out, straightened, then smoothed into curves with sharp corners kept. Colors are stacked largest first and
/// each shape also covers the colors drawn above it, so smoothing can't open hairline gaps between neighbors.
///
/// A port of Tracer.swift in MorphCore; keep them in step.
public sealed class Tracer(Tracer.Bitmap image, Tracer.Bitmap sample, Tracer.Settings settings)
{
    /// Straight (not premultiplied) RGBA, row by row from the top.
    public sealed record Bitmap(int Width, int Height, byte[] Rgba);

    public sealed class Settings
    {
        /// Palette size.
        public int Colors { get; set; }
        /// The image is traced at this many pixels squared.
        public int WorkPixel { get; init; }
        /// How far, in traced pixels, a straightened outline may stray from the evened-out pixel edges.
        public double Tolerance { get; init; }
        /// Patches smaller than this share of the image are folded into their surroundings.
        public double Speckle { get; init; }
        /// Palette colors closer than this (in RGB) are merged.
        public double Merge { get; init; }

        public static Settings For(CompressionLevel level) => level switch
        {
            CompressionLevel.Light => new() { Colors = 24, WorkPixel = 1600, Tolerance = 0.5, Speckle = 1.0 / 50_000, Merge = 6 },
            CompressionLevel.Balanced => new() { Colors = 16, WorkPixel = 1200, Tolerance = 0.75, Speckle = 1.0 / 25_000, Merge = 12 },
            _ => new() { Colors = 8, WorkPixel = 1000, Tolerance = 1.2, Speckle = 1.0 / 10_000, Merge = 20 },
        };
    }

    readonly record struct RGB(int R, int G, int B);
    readonly record struct Point(double X, double Y);

    int Width => image.Width;
    int Height => image.Height;

    public string Svg(int outWidth, int outHeight)
    {
        var palette = Palette();
        var index = Assign(image, palette);
        RemoveSpecks(index, palette);
        var n = Width * Height;

        // Largest color at the bottom. Each layer covers its own pixels and those of every layer above it.
        var population = new int[palette.Count];
        foreach (var k in index) if (k >= 0) population[k]++;
        var order = Enumerable.Range(0, palette.Count).Where(k => population[k] > 0).OrderByDescending(k => population[k]).ToList();
        var rank = Enumerable.Repeat(-1, palette.Count).ToArray();
        for (var r = 0; r < order.Count; r++) rank[order[r]] = r;
        var ranks = index.Select(k => k < 0 ? -1 : rank[k]).ToArray();
        var covered = n - index.Count(k => k < 0);

        var output = new StringBuilder($"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{outWidth}\" height=\"{outHeight}\" viewBox=\"0 0 {Width} {Height}\">\n");
        for (var layer = 0; layer < order.Count; layer++)
        {
            var c = palette[order[layer]];
            var d = covered == n ? $"M0 0h{Width}v{Height}h-{Width}z" : Outline(p => ranks[p] >= layer);
            if (d.Length > 0) output.Append($"<path fill=\"#{c.R:x2}{c.G:x2}{c.B:x2}\" d=\"{d}\"/>\n");
            covered -= population[order[layer]];
        }
        return output.Append("</svg>\n").ToString();
    }

    // MARK: Colors

    static int Distance(RGB a, RGB b)
    {
        int dr = a.R - b.R, dg = a.G - b.G, db = a.B - b.B;
        return 3 * dr * dr + 4 * dg * dg + 2 * db * db;
    }

    /// The 15-bit color of each pixel; -1 where it's under half opacity, which counts as transparent.
    static int[] Cells(Bitmap bitmap)
    {
        var rgba = bitmap.Rgba;
        var cells = new int[bitmap.Width * bitmap.Height];
        for (var p = 0; p < cells.Length; p++)
            cells[p] = rgba[p * 4 + 3] < 128 ? -1 : (rgba[p * 4] >> 3) << 10 | (rgba[p * 4 + 1] >> 3) << 5 | rgba[p * 4 + 2] >> 3;
        return cells;
    }

    /// Each pixel's nearest palette color, or -1 where it's transparent.
    static int[] Assign(Bitmap bitmap, List<RGB> palette)
    {
        var nearest = Enumerable.Repeat(-2, 32768).ToArray();
        return Cells(bitmap).Select(c =>
        {
            if (c < 0) return -1;
            if (nearest[c] == -2)
            {
                var m = new RGB(c >> 10 << 3 | 4, (c >> 5 & 31) << 3 | 4, (c & 31) << 3 | 4);
                nearest[c] = palette.Count == 0 ? -1 : Enumerable.Range(0, palette.Count).MinBy(k => Distance(m, palette[k]));
            }
            return nearest[c];
        }).ToArray();
    }

    /// Median cut over a histogram of the sample, refined by k-means, with near-identical colors merged and the
    /// in-between colors of antialiased edges dropped.
    List<RGB> Palette()
    {
        int width = sample.Width, height = sample.Height, n = width * height;
        var cell = Cells(sample);
        var count = new int[32768];
        var sumR = new long[32768]; var sumG = new long[32768]; var sumB = new long[32768];
        for (var p = 0; p < n; p++)
        {
            var c = cell[p];
            if (c < 0) continue;
            count[c]++;
            sumR[c] += sample.Rgba[p * 4]; sumG[c] += sample.Rgba[p * 4 + 1]; sumB[c] += sample.Rgba[p * 4 + 2];
        }
        var cells = Enumerable.Range(0, 32768).Where(c => count[c] > 0).ToList();
        if (cells.Count == 0) return [];
        RGB Mean(int c) => new((int)(sumR[c] / count[c]), (int)(sumG[c] / count[c]), (int)(sumB[c] / count[c]));

        // Median cut: split the busiest, widest box at its median until there are enough boxes.
        (int[] Lo, int[] Hi, int Count) Shrink(int[] lo0, int[] hi0)
        {
            int[] lo = [31, 31, 31], hi = [0, 0, 0];
            var total = 0;
            for (var r = lo0[0]; r <= hi0[0]; r++)
                for (var g = lo0[1]; g <= hi0[1]; g++)
                    for (var b = lo0[2]; b <= hi0[2]; b++)
                    {
                        var c = r << 10 | g << 5 | b;
                        if (count[c] == 0) continue;
                        total += count[c];
                        lo[0] = Math.Min(lo[0], r); lo[1] = Math.Min(lo[1], g); lo[2] = Math.Min(lo[2], b);
                        hi[0] = Math.Max(hi[0], r); hi[1] = Math.Max(hi[1], g); hi[2] = Math.Max(hi[2], b);
                    }
            return (lo, hi, total);
        }
        int[] weight = [3, 4, 2];
        var boxes = new List<(int[] Lo, int[] Hi, int Count)> { Shrink([0, 0, 0], [31, 31, 31]) };
        while (boxes.Count < settings.Colors)
        {
            int best = -1; long bestScore = 0;
            for (var i = 0; i < boxes.Count; i++)
            {
                var box = boxes[i];
                var spread = Enumerable.Range(0, 3).Max(a => (box.Hi[a] - box.Lo[a]) * weight[a]);
                if (spread > 0 && (long)box.Count * spread > bestScore) { best = i; bestScore = (long)box.Count * spread; }
            }
            if (best < 0) break;
            var split = boxes[best];
            var axis = Enumerable.Range(0, 3).MaxBy(a => (split.Hi[a] - split.Lo[a]) * weight[a]);
            var slices = new int[32];
            for (var r = split.Lo[0]; r <= split.Hi[0]; r++)
                for (var g = split.Lo[1]; g <= split.Hi[1]; g++)
                    for (var b = split.Lo[2]; b <= split.Hi[2]; b++)
                        slices[axis == 0 ? r : axis == 1 ? g : b] += count[r << 10 | g << 5 | b];
            int cut = split.Lo[axis], seen = slices[cut];
            while (cut < split.Hi[axis] - 1 && seen * 2 < split.Count) { cut++; seen += slices[cut]; }
            var lowHi = (int[])split.Hi.Clone(); lowHi[axis] = cut;
            var highLo = (int[])split.Lo.Clone(); highLo[axis] = cut + 1;
            boxes[best] = Shrink(split.Lo, lowHi);
            boxes.Add(Shrink(highLo, split.Hi));
        }
        var palette = boxes.Select(box =>
        {
            long r = 0, g = 0, b = 0, w = 0;
            for (var x = box.Lo[0]; x <= box.Hi[0]; x++)
                for (var y = box.Lo[1]; y <= box.Hi[1]; y++)
                    for (var z = box.Lo[2]; z <= box.Hi[2]; z++)
                    {
                        var c = x << 10 | y << 5 | z;
                        r += sumR[c]; g += sumG[c]; b += sumB[c]; w += count[c];
                    }
            return new RGB((int)(r / w), (int)(g / w), (int)(b / w));
        }).ToList();

        // A few rounds of k-means pull each color to the middle of the pixels it stands for.
        var nearest = Enumerable.Repeat(-1, 32768).ToArray();
        void AssignCells(bool[] allowed)
        {
            foreach (var c in cells)
            {
                var m = Mean(c);
                int best = -1, bestDistance = int.MaxValue;
                for (var k = 0; k < palette.Count; k++)
                {
                    if (!allowed[k]) continue;
                    var d = Distance(m, palette[k]);
                    if (d < bestDistance) { best = k; bestDistance = d; }
                }
                nearest[c] = best;
            }
        }
        var all = Enumerable.Repeat(true, palette.Count).ToArray();
        for (var round = 0; round < 4; round++)
        {
            AssignCells(all);
            var tr = new long[palette.Count]; var tg = new long[palette.Count]; var tb = new long[palette.Count]; var tw = new long[palette.Count];
            foreach (var c in cells)
            {
                var k = nearest[c];
                tr[k] += sumR[c]; tg[k] += sumG[c]; tb[k] += sumB[c]; tw[k] += count[c];
            }
            for (var k = 0; k < palette.Count; k++)
                if (tw[k] > 0) palette[k] = new RGB((int)(tr[k] / tw[k]), (int)(tg[k] / tw[k]), (int)(tb[k] / tw[k]));
        }

        // Colors closer than `Merge` become one: a faint gradient is better as one flat color than as many
        // ragged bands.
        var weights = new long[palette.Count];
        AssignCells(all);
        foreach (var c in cells) weights[nearest[c]] += count[c];
        while (true)
        {
            int pa = 0, pb = 0;
            var closest = settings.Merge * settings.Merge;
            for (var a = 0; a < palette.Count; a++)
            {
                if (weights[a] == 0) continue;
                for (var b = a + 1; b < palette.Count; b++)
                {
                    if (weights[b] == 0) continue;
                    double dr = palette[a].R - palette[b].R, dg = palette[a].G - palette[b].G, db = palette[a].B - palette[b].B;
                    if (dr * dr + dg * dg + db * db < closest) { pa = a; pb = b; closest = dr * dr + dg * dg + db * db; }
                }
            }
            if (pa == pb) break;
            var total = weights[pa] + weights[pb];
            palette[pa] = new RGB((int)((palette[pa].R * weights[pa] + palette[pb].R * weights[pb]) / total),
                                  (int)((palette[pa].G * weights[pa] + palette[pb].G * weights[pb]) / total),
                                  (int)((palette[pa].B * weights[pa] + palette[pb].B * weights[pb]) / total));
            weights[pa] = total; weights[pb] = 0;
        }
        AssignCells(weights.Select(w => w > 0).ToArray());
        var index = cell.Select(c => c < 0 ? -1 : nearest[c]).ToArray();

        // Antialiasing leaves thin rims of in-between colors along edges. A color that is mostly rim, and whose pixels
        // mostly sit next to a solid color close to it or between two solid colors it blends, is dropped; its pixels
        // go to whichever is nearest. Thin text in a color of its own has no such neighbors, so it stays.
        var population = new int[palette.Count]; var rim = new int[palette.Count];
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
            {
                int p = y * width + x, k = index[p];
                if (k < 0) continue;
                population[k]++;
                if ((x > 0 && index[p - 1] != k) || (x < width - 1 && index[p + 1] != k)
                    || (y > 0 && index[p - width] != k) || (y < height - 1 && index[p + width] != k)) rim[k]++;
            }
        var thin = Enumerable.Range(0, palette.Count).Select(k => population[k] > 0 && rim[k] * 10 >= population[k] * 6).ToArray();
        var solid = Enumerable.Range(0, palette.Count).Where(k => population[k] > 0 && !thin[k]).ToList();
        // The colors within two pixels of each pixel of a thin color, as bits.
        var around = Enumerable.Range(0, palette.Count).Select(_ => new List<ulong>()).ToArray();
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
            {
                var k = index[y * width + x];
                if (k < 0 || !thin[k]) continue;
                ulong bits = 0;
                for (var ny = Math.Max(0, y - 2); ny <= Math.Min(height - 1, y + 2); ny++)
                    for (var nx = Math.Max(0, x - 2); nx <= Math.Min(width - 1, x + 2); nx++)
                        if (index[ny * width + nx] is var q and >= 0) bits |= 1UL << q;
                around[k].Add(bits);
            }
        bool MostlyBeside(int c, ulong colors) => around[c].Count(b => (b & colors) == colors) * 2 >= around[c].Count;
        var keep = Enumerable.Range(0, palette.Count).Select(k => population[k] > 0).ToArray();
        for (var c = 0; c < palette.Count; c++)
        {
            if (!thin[c]) continue;
            var p = palette[c];
            var blend = solid.Any(a =>
            {
                double dr = p.R - palette[a].R, dg = p.G - palette[a].G, db = p.B - palette[a].B;
                if (dr * dr + dg * dg + db * db <= 24 * 24 && MostlyBeside(c, 1UL << a)) return true;
                return solid.Any(b =>
                {
                    if (b <= a) return false;
                    double lr = palette[b].R - palette[a].R, lg = palette[b].G - palette[a].G, lb = palette[b].B - palette[a].B;
                    var length = lr * lr + lg * lg + lb * lb;
                    if (length <= 0) return false;
                    var t = (dr * lr + dg * lg + db * lb) / length;
                    double er = dr - t * lr, eg = dg - t * lg, eb = db - t * lb;
                    return t > 0.05 && t < 0.95 && er * er + eg * eg + eb * eb <= 18 * 18 && MostlyBeside(c, 1UL << a | 1UL << b);
                });
            });
            if (blend) keep[c] = false;
        }
        return Enumerable.Range(0, palette.Count).Where(k => keep[k]).Select(k => palette[k]).ToList();
    }

    /// Folds patches smaller than the speck size into the color they touch most, preferring patches that stay.
    /// Noise is close in color to what surrounds it; a dot or stroke that stands out (the dot on an i, a hairline)
    /// is kept unless it's only a pixel or two.
    void RemoveSpecks(int[] index, List<RGB> palette)
    {
        var n = Width * Height;
        var minimum = Math.Max(3, (int)(n * settings.Speckle));
        var label = Enumerable.Repeat(-1, n).ToArray();
        var size = new List<int>();
        var small = new List<(int Label, int From, int To)>();
        var pixels = new List<int>();
        var stack = new Stack<int>();
        int[] Neighbors(int p)
        {
            var x = p % Width;
            return [x > 0 ? p - 1 : -1, x < Width - 1 ? p + 1 : -1, p - Width, p + Width];
        }
        for (var start = 0; start < n; start++)
        {
            if (label[start] >= 0) continue;
            int l = size.Count, k = index[start], first = pixels.Count;
            label[start] = l;
            stack.Push(start);
            while (stack.Count > 0)
            {
                var p = stack.Pop();
                pixels.Add(p);
                foreach (var q in Neighbors(p))
                    if (q >= 0 && q < n && label[q] < 0 && index[q] == k) { label[q] = l; stack.Push(q); }
            }
            size.Add(pixels.Count - first);
            if (size[l] < minimum) small.Add((l, first, pixels.Count));
            else pixels.RemoveRange(first, pixels.Count - first);
        }
        foreach (var (l, from, to) in small)
        {
            var votes = new Dictionary<int, (int Stays, int Any)>();
            for (var i = from; i < to; i++)
                foreach (var q in Neighbors(pixels[i]))
                {
                    if (q < 0 || q >= n || label[q] == l) continue;
                    var vote = votes.GetValueOrDefault(index[q]);
                    votes[index[q]] = (vote.Stays + (size[label[q]] >= minimum ? 1 : 0), vote.Any + 1);
                }
            if (votes.Count == 0) continue;
            var winner = votes.OrderByDescending(v => v.Value.Stays).ThenByDescending(v => v.Value.Any).ThenBy(v => v.Key).First().Key;
            var own = index[pixels[from]];
            if (to - from >= 3 && (own < 0 || winner < 0 || Distance(palette[own], palette[winner]) > 64 * 64 * 9)) continue;
            for (var i = from; i < to; i++) index[pixels[i]] = winner;
        }
    }

    // MARK: Outlines

    /// Path data for the pixels where `inside` holds: every boundary loop, evened out, straightened and smoothed.
    string Outline(Func<int, bool> inside)
    {
        var columns = Width + 1;
        // Pixel edges with the inside on their right: 1 east, 2 south, 4 west, 8 north, from each grid vertex.
        var edges = new int[columns * (Height + 1)];
        for (var y = 0; y < Height; y++)
            for (var x = 0; x < Width; x++)
            {
                var p = y * Width + x;
                if (!inside(p)) continue;
                if (y == 0 || !inside(p - Width)) edges[y * columns + x] |= 1;
                if (x == Width - 1 || !inside(p + 1)) edges[y * columns + x + 1] |= 2;
                if (y == Height - 1 || !inside(p + Width)) edges[(y + 1) * columns + x + 1] |= 4;
                if (x == 0 || !inside(p - 1)) edges[(y + 1) * columns + x] |= 8;
            }
        var path = new PathWriter();
        for (var start = 0; start < edges.Length; start++)
        {
            while (edges[start] != 0)
            {
                // Walk the loop through every grid vertex. Where two pixels touch only at a corner, turn right.
                var points = new List<Point>();
                int v = start, heading = 0;
                do
                {
                    var outgoing = edges[v];
                    var next = outgoing & -outgoing;
                    if (outgoing != next && heading != 0)
                    {
                        var right = heading == 8 ? 1 : heading << 1;
                        next = (outgoing & right) != 0 ? right : outgoing & ~right;
                    }
                    edges[v] &= ~next;
                    points.Add(new Point(v % columns, v / columns));
                    heading = next;
                    v += next switch { 1 => 1, 2 => columns, 4 => -1, _ => -columns };
                } while (v != start);
                if (Math.Abs(Area(points)) < 2) continue;
                var corners = Corners(points);
                var (polygon, polygonCorners) = Simplify(Relaxed(points, corners), corners);
                Smooth(polygon, polygonCorners, path);
            }
        }
        return path.ToString();
    }

    static double Area(List<Point> points)
    {
        var a = 0.0;
        for (var i = 0; i < points.Count; i++)
        {
            var p = points[i]; var q = points[(i + 1) % points.Count];
            a += p.X * q.Y - q.X * p.Y;
        }
        return a / 2;
    }

    /// Where the outline really turns, as opposed to stepping from pixel to pixel: the direction a few pixels back
    /// and a few ahead differ by more than 55°, and both stretches are straight. Only the sharpest point counts.
    static HashSet<int> Corners(List<Point> points)
    {
        int n = points.Count, k = 4;
        var corners = new HashSet<int>();
        if (n < 4 * k) return corners;
        var turn = new double[n];
        for (var i = 0; i < n; i++)
        {
            Point p = points[i], a = points[(i + n - k) % n], b = points[(i + k) % n];
            double ux = p.X - a.X, uy = p.Y - a.Y, wx = b.X - p.X, wy = b.Y - p.Y;
            turn[i] = Math.Acos(Math.Clamp((ux * wx + uy * wy) / (Math.Sqrt(ux * ux + uy * uy) * Math.Sqrt(wx * wx + wy * wy)), -1, 1));
        }
        for (var i = 0; i < n; i++)
        {
            if (turn[i] <= 55 * Math.PI / 180) continue;
            var sharpest = Enumerable.Range(1, k).All(j => turn[i] > turn[(i + n - j) % n] && turn[i] >= turn[(i + j) % n]);
            Point a = points[(i + n - k) % n], b = points[(i + k) % n];
            var straight = Enumerable.Range(1, k - 1).All(j =>
                Distance(points[(i + n - j) % n], a, points[i]) <= 1 && Distance(points[(i + j) % n], points[i], b) <= 1);
            if (sharpest && straight) corners.Add(i);
        }
        return corners;
    }

    /// Evens out the pixel steps by averaging each point with its neighbors a few times, leaving corners alone.
    static List<Point> Relaxed(List<Point> points, HashSet<int> corners)
    {
        var n = points.Count;
        var p = points.ToArray();
        for (var round = 0; round < 3; round++)
        {
            var q = (Point[])p.Clone();
            for (var i = 0; i < n; i++)
            {
                if (corners.Contains(i)) continue;
                Point a = q[(i + n - 1) % n], b = q[(i + 1) % n];
                p[i] = new Point((a.X + 2 * q[i].X + b.X) / 4, (a.Y + 2 * q[i].Y + b.Y) / 4);
            }
        }
        return [.. p];
    }

    /// Douglas-Peucker between corners. Returns the polygon with the positions of its corners.
    (List<Point>, HashSet<int>) Simplify(List<Point> points, HashSet<int> corners)
    {
        var n = points.Count;
        var anchors = corners.Order().ToList();
        if (anchors.Count < 2)
        {
            // Split the loop at the point farthest from where it starts (or from its one corner).
            var from = anchors.Count > 0 ? anchors[0] : 0;
            var far = from; var farthest = -1.0;
            for (var i = 0; i < n; i++)
            {
                var d = Math.Sqrt(Math.Pow(points[i].X - points[from].X, 2) + Math.Pow(points[i].Y - points[from].Y, 2));
                if (d > farthest) { far = i; farthest = d; }
            }
            anchors = new[] { from, far }.Distinct().Order().ToList();
        }
        var keep = new bool[n];
        var stack = new Stack<(int, int)>();
        for (var i = 0; i < anchors.Count; i++)
        {
            keep[anchors[i]] = true;
            stack.Push((anchors[i], i + 1 < anchors.Count ? anchors[i + 1] : anchors[0] + n));
        }
        while (stack.Count > 0)
        {
            var (a, b) = stack.Pop();
            if (b - a <= 1) continue;
            Point p = points[a % n], q = points[b % n];
            int at = -1; var worst = -1.0;
            for (var i = a + 1; i < b; i++)
            {
                var d = Distance(points[i % n], p, q);
                if (d > worst) { at = i; worst = d; }
            }
            if (worst > settings.Tolerance)
            {
                keep[at % n] = true;
                stack.Push((a, at)); stack.Push((at, b));
            }
        }
        var kept = Enumerable.Range(0, n).Where(i => keep[i]).ToList();
        return (kept.Select(i => points[i]).ToList(), Enumerable.Range(0, kept.Count).Where(j => corners.Contains(kept[j])).ToHashSet());
    }

    static double Distance(Point p, Point a, Point b)
    {
        double dx = b.X - a.X, dy = b.Y - a.Y, length = dx * dx + dy * dy;
        if (length <= 0) return Math.Sqrt((p.X - a.X) * (p.X - a.X) + (p.Y - a.Y) * (p.Y - a.Y));
        var t = Math.Clamp(((p.X - a.X) * dx + (p.Y - a.Y) * dy) / length, 0, 1);
        double ex = p.X - a.X - t * dx, ey = p.Y - a.Y - t * dy;
        return Math.Sqrt(ex * ex + ey * ey);
    }

    /// Potrace's smoothing: each corner of the polygon becomes a curve between points on its two sides, unless it
    /// sticks out far enough from them to be a real corner. A curve reaches no further along one side than the
    /// length of the other, so a long straight edge runs straight into the rounded corner at its end.
    static void Smooth(List<Point> v, HashSet<int> corners, PathWriter path)
    {
        var m = v.Count;
        if (m < 3) return;
        var length = Enumerable.Range(0, m).Select(i => Math.Sqrt(Math.Pow(v[(i + 1) % m].X - v[i].X, 2) + Math.Pow(v[(i + 1) % m].Y - v[i].Y, 2))).ToArray();
        Point Along(int side, bool fromStart, double d)
        {
            Point a = v[side], b = v[(side + 1) % m];
            var t = length[side] > 0 ? d / length[side] : 0.5;
            return fromStart ? new Point(a.X + t * (b.X - a.X), a.Y + t * (b.Y - a.Y)) : new Point(b.X + t * (a.X - b.X), b.Y + t * (a.Y - b.Y));
        }
        var enter = Enumerable.Range(0, m).Select(j => Along((j + m - 1) % m, false, Math.Min(length[(j + m - 1) % m] / 2, length[j]))).ToArray();
        var leave = Enumerable.Range(0, m).Select(j => Along(j, true, Math.Min(length[j] / 2, length[(j + m - 1) % m]))).ToArray();
        path.Move(leave[m - 1]);
        for (var j = 0; j < m; j++)
        {
            Point a = enter[j], b = leave[j], p = v[j];
            path.Line(a);
            var denominator = Math.Abs(b.X - a.X) + Math.Abs(b.Y - a.Y);
            var dd = denominator > 0 ? Math.Abs((p.X - a.X) * (b.Y - a.Y) - (p.Y - a.Y) * (b.X - a.X)) / denominator : 0;
            var alpha = dd > 1 ? (1 - 1 / dd) / 0.75 : 0;
            if (corners.Contains(j) || alpha >= 1)
            {
                path.Line(p);
                path.Line(b);
            }
            else
            {
                var s = Math.Max(alpha, 0.55);
                path.Curve(new Point(a.X + s * (p.X - a.X), a.Y + s * (p.Y - a.Y)), new Point(b.X + s * (p.X - b.X), b.Y + s * (p.Y - b.Y)), b);
            }
        }
        path.Close();
    }

    /// Compact path data: relative commands, one decimal, straight runs of lines joined.
    sealed class PathWriter
    {
        readonly StringBuilder text = new();
        int x, y, startX, startY;
        (int X, int Y)? pending;

        void Number(int tenths)
        {
            var magnitude = Math.Abs(tenths);
            var s = magnitude % 10 == 0 ? (magnitude / 10).ToString(CultureInfo.InvariantCulture)
                : (magnitude < 10 ? "" : (magnitude / 10).ToString(CultureInfo.InvariantCulture)) + "." + magnitude % 10;
            if (tenths < 0) s = "-" + s;
            if (text.Length > 0 && !char.IsLetter(text[^1]) && !s.StartsWith('-')) text.Append(' ');
            text.Append(s);
        }

        static (int X, int Y) Tenths(Point p) => ((int)Math.Round(p.X * 10, MidpointRounding.AwayFromZero), (int)Math.Round(p.Y * 10, MidpointRounding.AwayFromZero));

        void Flush()
        {
            if (pending is not { } p) return;
            pending = null;
            text.Append('l');
            Number(p.X - x); Number(p.Y - y);
            (x, y) = p;
        }

        public void Move(Point p)
        {
            var t = Tenths(p);
            text.Append('m');
            Number(t.X - x); Number(t.Y - y);
            (x, y) = t;
            (startX, startY) = (x, y);
        }

        public void Line(Point p)
        {
            var t = Tenths(p);
            var from = pending ?? (x, y);
            if (t == from) return;
            if (pending is { } mid)
            {
                // Carrying straight on (within rounding) from the pending line: extend it instead.
                long cross = (long)(mid.X - x) * (t.Y - mid.Y) - (long)(mid.Y - y) * (t.X - mid.X);
                long dot = (long)(mid.X - x) * (t.X - mid.X) + (long)(mid.Y - y) * (t.Y - mid.Y);
                var span = Math.Sqrt(Math.Pow(t.X - x, 2) + Math.Pow(t.Y - y, 2));
                if (dot > 0 && Math.Abs(cross) <= span * 0.5) { pending = t; return; }
                Flush();
            }
            pending = t;
        }

        public void Curve(Point c1, Point c2, Point p)
        {
            Flush();
            text.Append('c');
            foreach (var c in new[] { c1, c2, p })
            {
                var t = Tenths(c);
                Number(t.X - x); Number(t.Y - y);
            }
            (x, y) = Tenths(p);
        }

        public void Close()
        {
            if (pending is { } p && p != (startX, startY)) Flush();
            pending = null;
            text.Append('z');
            (x, y) = (startX, startY);
        }

        public override string ToString() => text.ToString();
    }
}
