import Foundation

/// Turns pixels into an SVG of filled shapes, the way potrace and VTracer do: the colors are reduced to a small
/// palette, specks are folded into what surrounds them, and each color's outline is traced along the pixel edges,
/// evened out, straightened, then smoothed into curves with sharp corners kept. Colors are stacked largest first and
/// each shape also covers the colors drawn above it, so smoothing can't open hairline gaps between neighbors.
///
/// The Android and Windows engines carry line-for-line ports of this file; keep them in step.
struct Tracer {
    struct Settings {
        /// Palette size.
        var colors: Int
        /// The image is traced at this many pixels squared.
        var workPixel: Int
        /// How far, in traced pixels, a straightened outline may stray from the evened-out pixel edges.
        var tolerance: Double
        /// Patches smaller than this share of the image are folded into their surroundings.
        var speckle: Double
        /// Palette colors closer than this (in RGB) are merged.
        var merge: Double

        init(_ level: CompressionLevel) {
            switch level {
            case .light: (colors, workPixel, tolerance, speckle, merge) = (24, 1600, 0.5, 1.0 / 50_000, 6)
            case .balanced: (colors, workPixel, tolerance, speckle, merge) = (16, 1200, 0.75, 1.0 / 25_000, 12)
            case .strong: (colors, workPixel, tolerance, speckle, merge) = (8, 1000, 1.2, 1.0 / 10_000, 20)
            }
        }
    }

    /// Straight (not premultiplied) RGBA, row by row from the top.
    struct Bitmap {
        let width: Int, height: Int
        let rgba: [UInt8]
    }

    /// What gets traced, at the working size.
    let image: Bitmap
    /// The image at its own size (or `image`, if that's smaller), where the palette is chosen: enlarging smears
    /// antialiased edges over several pixels, and they're only recognizable as edges at their real width.
    let sample: Bitmap
    let settings: Settings

    private struct RGB { var r, g, b: Int }
    private struct Point { var x, y: Double }

    private var width: Int { image.width }
    private var height: Int { image.height }

    func svg(width outWidth: Int, height outHeight: Int) -> String {
        let palette = self.palette()
        var index = Self.assign(image, to: palette)
        removeSpecks(&index, palette: palette)
        let n = width * height

        // Largest color at the bottom. Each layer covers its own pixels and those of every layer above it.
        var population = [Int](repeating: 0, count: palette.count)
        for k in index where k >= 0 { population[Int(k)] += 1 }
        let order = palette.indices.filter { population[$0] > 0 }.sorted { population[$0] > population[$1] }
        var rank = [Int](repeating: -1, count: palette.count)
        for (r, k) in order.enumerated() { rank[k] = r }
        let ranks = index.map { $0 < 0 ? -1 : rank[Int($0)] }
        var covered = n - (index.lazy.filter { $0 < 0 }.count)

        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(outWidth)\" height=\"\(outHeight)\" viewBox=\"0 0 \(width) \(height)\">\n"
        for (layer, k) in order.enumerated() {
            let c = palette[k]
            let d = covered == n ? "M0 0h\(width)v\(height)h-\(width)z" : outline { ranks[$0] >= layer }
            if !d.isEmpty { out += "<path fill=\"\(String(format: "#%02x%02x%02x", c.r, c.g, c.b))\" d=\"\(d)\"/>\n" }
            covered -= population[k]
        }
        return out + "</svg>\n"
    }

    // MARK: Colors

    private static func distance(_ a: RGB, _ b: RGB) -> Int {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return 3 * dr * dr + 4 * dg * dg + 2 * db * db
    }

    /// The 15-bit color of each pixel; -1 where it's under half opacity, which counts as transparent.
    private static func cells(_ bitmap: Bitmap) -> [Int32] {
        let rgba = bitmap.rgba
        return (0..<bitmap.width * bitmap.height).map { p in
            guard rgba[p * 4 + 3] >= 128 else { return -1 }
            return Int32((Int(rgba[p * 4]) >> 3) << 10 | (Int(rgba[p * 4 + 1]) >> 3) << 5 | Int(rgba[p * 4 + 2]) >> 3)
        }
    }

    /// Each pixel's nearest palette color, or -1 where it's transparent.
    private static func assign(_ bitmap: Bitmap, to palette: [RGB]) -> [Int32] {
        var nearest = [Int32](repeating: -2, count: 32768)
        return cells(bitmap).map { c in
            guard c >= 0 else { return -1 }
            if nearest[Int(c)] == -2 {
                let m = RGB(r: Int(c >> 10) << 3 | 4, g: Int(c >> 5 & 31) << 3 | 4, b: Int(c & 31) << 3 | 4)
                nearest[Int(c)] = Int32(palette.indices.min { distance(m, palette[$0]) < distance(m, palette[$1]) } ?? -1)
            }
            return nearest[Int(c)]
        }
    }

    /// Median cut over a histogram of the sample, refined by k-means, with near-identical colors merged and the
    /// in-between colors of antialiased edges dropped.
    private func palette() -> [RGB] {
        let width = sample.width, height = sample.height, n = width * height
        let cell = Self.cells(sample)
        var count = [Int](repeating: 0, count: 32768)
        var sum = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: 32768)
        for p in 0..<n where cell[p] >= 0 {
            let c = Int(cell[p])
            count[c] += 1
            sum[c].r += Int(sample.rgba[p * 4]); sum[c].g += Int(sample.rgba[p * 4 + 1]); sum[c].b += Int(sample.rgba[p * 4 + 2])
        }
        let cells = count.indices.filter { count[$0] > 0 }
        guard !cells.isEmpty else { return [] }
        let mean = { (c: Int) in RGB(r: sum[c].r / count[c], g: sum[c].g / count[c], b: sum[c].b / count[c]) }

        // Median cut: split the busiest, widest box at its median until there are enough boxes.
        struct Box { var lo: [Int], hi: [Int], count: Int }
        func shrink(_ box: Box) -> Box {
            var lo = [31, 31, 31], hi = [0, 0, 0], total = 0
            for r in box.lo[0]...box.hi[0] { for g in box.lo[1]...box.hi[1] { for b in box.lo[2]...box.hi[2] {
                let c = r << 10 | g << 5 | b
                guard count[c] > 0 else { continue }
                total += count[c]
                lo = [min(lo[0], r), min(lo[1], g), min(lo[2], b)]
                hi = [max(hi[0], r), max(hi[1], g), max(hi[2], b)]
            } } }
            return Box(lo: lo, hi: hi, count: total)
        }
        let weight = [3, 4, 2]
        var boxes = [shrink(Box(lo: [0, 0, 0], hi: [31, 31, 31], count: 0))]
        while boxes.count < settings.colors {
            var best = -1, bestScore = 0
            for (i, box) in boxes.enumerated() {
                let spread = (0..<3).map { (box.hi[$0] - box.lo[$0]) * weight[$0] }.max()!
                if spread > 0, box.count * spread > bestScore { best = i; bestScore = box.count * spread }
            }
            guard best >= 0 else { break }
            let box = boxes[best]
            let axis = (0..<3).max { (box.hi[$0] - box.lo[$0]) * weight[$0] < (box.hi[$1] - box.lo[$1]) * weight[$1] }!
            var slices = [Int](repeating: 0, count: 32)
            for r in box.lo[0]...box.hi[0] { for g in box.lo[1]...box.hi[1] { for b in box.lo[2]...box.hi[2] {
                slices[[r, g, b][axis]] += count[r << 10 | g << 5 | b]
            } } }
            var cut = box.lo[axis], seen = slices[cut]
            while cut < box.hi[axis] - 1, seen * 2 < box.count { cut += 1; seen += slices[cut] }
            var low = box, high = box
            low.hi[axis] = cut; high.lo[axis] = cut + 1
            boxes[best] = shrink(low)
            boxes.append(shrink(high))
        }
        var palette = boxes.map { box -> RGB in
            var total = RGB(r: 0, g: 0, b: 0), weight = 0
            for r in box.lo[0]...box.hi[0] { for g in box.lo[1]...box.hi[1] { for b in box.lo[2]...box.hi[2] {
                let c = r << 10 | g << 5 | b
                total.r += sum[c].r; total.g += sum[c].g; total.b += sum[c].b; weight += count[c]
            } } }
            return RGB(r: total.r / weight, g: total.g / weight, b: total.b / weight)
        }

        // A few rounds of k-means pull each color to the middle of the pixels it stands for.
        var nearest = [Int32](repeating: -1, count: 32768)
        func assign(_ allowed: [Bool]) {
            for c in cells {
                let m = mean(c)
                var best = -1, bestDistance = Int.max
                for (k, color) in palette.enumerated() where allowed[k] {
                    let d = Self.distance(m, color)
                    if d < bestDistance { best = k; bestDistance = d }
                }
                nearest[c] = Int32(best)
            }
        }
        let all = [Bool](repeating: true, count: palette.count)
        for _ in 0..<4 {
            assign(all)
            var totals = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: palette.count)
            var weights = [Int](repeating: 0, count: palette.count)
            for c in cells {
                let k = Int(nearest[c])
                totals[k].r += sum[c].r; totals[k].g += sum[c].g; totals[k].b += sum[c].b; weights[k] += count[c]
            }
            for k in palette.indices where weights[k] > 0 {
                palette[k] = RGB(r: totals[k].r / weights[k], g: totals[k].g / weights[k], b: totals[k].b / weights[k])
            }
        }

        // Colors closer than `merge` become one: a faint gradient is better as one flat color than as many
        // ragged bands.
        var weights = [Int](repeating: 0, count: palette.count)
        assign(all)
        for c in cells { weights[Int(nearest[c])] += count[c] }
        while true {
            var pair = (0, 0), closest = settings.merge * settings.merge
            for a in palette.indices where weights[a] > 0 {
                for b in a + 1..<palette.count where weights[b] > 0 {
                    let dr = Double(palette[a].r - palette[b].r), dg = Double(palette[a].g - palette[b].g), db = Double(palette[a].b - palette[b].b)
                    if dr * dr + dg * dg + db * db < closest { pair = (a, b); closest = dr * dr + dg * dg + db * db }
                }
            }
            guard pair.0 != pair.1 else { break }
            let (a, b) = pair, total = weights[a] + weights[b]
            palette[a] = RGB(r: (palette[a].r * weights[a] + palette[b].r * weights[b]) / total,
                             g: (palette[a].g * weights[a] + palette[b].g * weights[b]) / total,
                             b: (palette[a].b * weights[a] + palette[b].b * weights[b]) / total)
            weights[a] = total; weights[b] = 0
        }
        assign(weights.map { $0 > 0 })
        let index = cell.map { $0 < 0 ? -1 : nearest[Int($0)] }

        // Antialiasing leaves thin rims of in-between colors along edges. A color that is mostly rim, and whose pixels
        // mostly sit next to a solid color close to it or between two solid colors it blends, is dropped; its pixels
        // go to whichever is nearest. Thin text in a color of its own has no such neighbors, so it stays.
        var population = [Int](repeating: 0, count: palette.count), rim = population
        for y in 0..<height {
            for x in 0..<width {
                let p = y * width + x, k = Int(index[p])
                guard k >= 0 else { continue }
                population[k] += 1
                if (x > 0 && index[p - 1] != index[p]) || (x < width - 1 && index[p + 1] != index[p])
                    || (y > 0 && index[p - width] != index[p]) || (y < height - 1 && index[p + width] != index[p]) {
                    rim[k] += 1
                }
            }
        }
        let thin = palette.indices.map { population[$0] > 0 && rim[$0] * 10 >= population[$0] * 6 }
        let solid = palette.indices.filter { population[$0] > 0 && !thin[$0] }
        // The colors within two pixels of each pixel of a thin color, as bits.
        var around = [[UInt64]](repeating: [], count: palette.count)
        for y in 0..<height {
            for x in 0..<width {
                let k = Int(index[y * width + x])
                guard k >= 0, thin[k] else { continue }
                var bits: UInt64 = 0
                for ny in max(0, y - 2)...min(height - 1, y + 2) {
                    for nx in max(0, x - 2)...min(width - 1, x + 2) where index[ny * width + nx] >= 0 {
                        bits |= 1 << UInt64(index[ny * width + nx])
                    }
                }
                around[k].append(bits)
            }
        }
        func mostlyBeside(_ c: Int, _ colors: UInt64) -> Bool {
            around[c].lazy.filter { $0 & colors == colors }.count * 2 >= around[c].count
        }
        var keep = palette.indices.map { population[$0] > 0 }
        for c in palette.indices where thin[c] {
            let p = palette[c]
            let blend = solid.contains { a in
                let dr = Double(p.r - palette[a].r), dg = Double(p.g - palette[a].g), db = Double(p.b - palette[a].b)
                if dr * dr + dg * dg + db * db <= 24 * 24, mostlyBeside(c, 1 << UInt64(a)) { return true }
                return solid.contains { b in
                    guard b > a else { return false }
                    let lr = Double(palette[b].r - palette[a].r), lg = Double(palette[b].g - palette[a].g), lb = Double(palette[b].b - palette[a].b)
                    let length = lr * lr + lg * lg + lb * lb
                    guard length > 0 else { return false }
                    let t = (dr * lr + dg * lg + db * lb) / length
                    let er = dr - t * lr, eg = dg - t * lg, eb = db - t * lb
                    return t > 0.05 && t < 0.95 && er * er + eg * eg + eb * eb <= 18 * 18
                        && mostlyBeside(c, 1 << UInt64(a) | 1 << UInt64(b))
                }
            }
            if blend { keep[c] = false }
        }
        return palette.indices.filter { keep[$0] }.map { palette[$0] }
    }

    /// Folds patches smaller than the speck size into the color they touch most, preferring patches that stay.
    /// Noise is close in color to what surrounds it; a dot or stroke that stands out (the dot on an i, a hairline)
    /// is kept unless it's only a pixel or two.
    private func removeSpecks(_ index: inout [Int32], palette: [RGB]) {
        let n = width * height
        let minimum = max(3, Int(Double(n) * settings.speckle))
        var label = [Int32](repeating: -1, count: n)
        var size: [Int] = []
        var small: [(label: Int, pixels: Range<Int>)] = []
        var pixels: [Int] = [], stack: [Int] = []
        for start in 0..<n where label[start] < 0 {
            let l = size.count, k = index[start], first = pixels.count
            label[start] = Int32(l)
            stack.append(start)
            while let p = stack.popLast() {
                pixels.append(p)
                let x = p % width
                for q in [x > 0 ? p - 1 : -1, x < width - 1 ? p + 1 : -1, p - width, p + width]
                    where q >= 0 && q < n && label[q] < 0 && index[q] == k {
                    label[q] = Int32(l)
                    stack.append(q)
                }
            }
            size.append(pixels.count - first)
            if size[l] < minimum { small.append((l, first..<pixels.count)) } else { pixels.removeSubrange(first...) }
        }
        for (l, range) in small {
            var votes: [Int32: (stays: Int, any: Int)] = [:]
            for i in range {
                let p = pixels[i], x = p % width
                for q in [x > 0 ? p - 1 : -1, x < width - 1 ? p + 1 : -1, p - width, p + width]
                    where q >= 0 && q < n && label[q] != Int32(l) {
                    let stays = size[Int(label[q])] >= minimum ? 1 : 0
                    votes[index[q], default: (0, 0)].stays += stays
                    votes[index[q], default: (0, 0)].any += 1
                }
            }
            guard let winner = votes.max(by: { ($0.value.stays, $0.value.any, $1.key) < ($1.value.stays, $1.value.any, $0.key) }) else { continue }
            let own = index[pixels[range.lowerBound]]
            if range.count >= 3, own < 0 || winner.key < 0 || Self.distance(palette[Int(own)], palette[Int(winner.key)]) > 64 * 64 * 9 { continue }
            for i in range { index[pixels[i]] = winner.key }
        }
    }

    // MARK: Outlines

    /// Path data for the pixels where `inside` holds: every boundary loop, evened out, straightened and smoothed.
    private func outline(_ inside: (Int) -> Bool) -> String {
        let columns = width + 1
        // Pixel edges with the inside on their right: 1 east, 2 south, 4 west, 8 north, from each grid vertex.
        var edges = [UInt8](repeating: 0, count: columns * (height + 1))
        for y in 0..<height {
            for x in 0..<width where inside(y * width + x) {
                let p = y * width + x
                if y == 0 || !inside(p - width) { edges[y * columns + x] |= 1 }
                if x == width - 1 || !inside(p + 1) { edges[y * columns + x + 1] |= 2 }
                if y == height - 1 || !inside(p + width) { edges[(y + 1) * columns + x + 1] |= 4 }
                if x == 0 || !inside(p - 1) { edges[(y + 1) * columns + x] |= 8 }
            }
        }
        var path = PathWriter()
        let step = [1: (1, 0), 2: (0, 1), 4: (-1, 0), 8: (0, -1)]
        for start in edges.indices {
            while edges[start] != 0 {
                // Walk the loop through every grid vertex. Where two pixels touch only at a corner, turn right: they stay apart.
                var points: [Point] = []
                var v = start, heading = 0
                repeat {
                    let out = edges[v]
                    var next = Int(out & (~out + 1))
                    if out != UInt8(next), heading != 0 {
                        let right = heading == 8 ? 1 : heading << 1
                        next = Int(out) & right != 0 ? right : Int(out) & ~right
                    }
                    edges[v] &= ~UInt8(next)
                    points.append(Point(x: Double(v % columns), y: Double(v / columns)))
                    heading = next
                    v += step[next]!.0 + step[next]!.1 * columns
                } while v != start
                guard abs(area(points)) >= 2 else { continue }
                let corners = self.corners(of: points)
                let polygon = simplify(relaxed(points, keeping: corners), corners: corners)
                smooth(polygon.points, corners: polygon.corners, into: &path)
            }
        }
        return path.text
    }

    private func area(_ points: [Point]) -> Double {
        var a = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    /// Where the outline really turns, as opposed to stepping from pixel to pixel: the direction a few pixels back
    /// and a few ahead differ by more than 55°, and both stretches are straight (a nick in a ragged edge isn't a
    /// corner). Only the sharpest point of each turn counts.
    private func corners(of points: [Point]) -> Set<Int> {
        let n = points.count, k = 4
        guard n >= 4 * k else { return [] }
        let turn = (0..<n).map { i -> Double in
            let p = points[i], a = points[(i + n - k) % n], b = points[(i + k) % n]
            let ux = p.x - a.x, uy = p.y - a.y, wx = b.x - p.x, wy = b.y - p.y
            let cosine = (ux * wx + uy * wy) / (hypot(ux, uy) * hypot(wx, wy))
            return acos(max(-1, min(1, cosine)))
        }
        var corners = Set<Int>()
        for i in 0..<n where turn[i] > 55 * .pi / 180 {
            let sharpest = (1...k).allSatisfy { turn[i] > turn[(i + n - $0) % n] && turn[i] >= turn[(i + $0) % n] }
            let a = points[(i + n - k) % n], b = points[(i + k) % n]
            let straight = (1..<k).allSatisfy {
                Self.distance(points[(i + n - $0) % n], from: a, to: points[i]) <= 1
                    && Self.distance(points[(i + $0) % n], from: points[i], to: b) <= 1
            }
            if sharpest, straight { corners.insert(i) }
        }
        return corners
    }

    /// Evens out the pixel steps (and one-pixel nicks the palette leaves) by averaging each point with its
    /// neighbors a few times, leaving corners where they are.
    private func relaxed(_ points: [Point], keeping corners: Set<Int>) -> [Point] {
        let n = points.count
        var p = points
        for _ in 0..<3 {
            let q = p
            for i in 0..<n where !corners.contains(i) {
                let a = q[(i + n - 1) % n], b = q[(i + 1) % n]
                p[i] = Point(x: (a.x + 2 * q[i].x + b.x) / 4, y: (a.y + 2 * q[i].y + b.y) / 4)
            }
        }
        return p
    }

    /// Douglas-Peucker between corners: drops points within `tolerance` of the line through their neighbors,
    /// which turns the outline into a polygon. Returns it with the positions of its corners.
    private func simplify(_ points: [Point], corners: Set<Int>) -> (points: [Point], corners: Set<Int>) {
        let n = points.count
        var anchors = corners.sorted()
        if anchors.count < 2 {
            // Split the loop at the point farthest from where it starts (or from its one corner).
            let from = anchors.first ?? 0
            var far = from, farthest = -1.0
            for i in 0..<n {
                let d = hypot(points[i].x - points[from].x, points[i].y - points[from].y)
                if d > farthest { far = i; farthest = d }
            }
            anchors = Array(Set([from, far])).sorted()
        }
        var keep = [Bool](repeating: false, count: n)
        var stack: [(Int, Int)] = []
        for (i, a) in anchors.enumerated() {
            keep[a] = true
            stack.append((a, i + 1 < anchors.count ? anchors[i + 1] : anchors[0] + n))
        }
        while let (a, b) = stack.popLast() {
            guard b - a > 1 else { continue }
            let p = points[a % n], q = points[b % n]
            var at = -1, worst = -1.0
            for i in a + 1..<b {
                let d = Self.distance(points[i % n], from: p, to: q)
                if d > worst { at = i; worst = d }
            }
            if worst > settings.tolerance {
                keep[at % n] = true
                stack.append((a, at)); stack.append((at, b))
            }
        }
        let kept = points.indices.filter { keep[$0] }
        return (kept.map { points[$0] }, Set(kept.indices.filter { corners.contains(kept[$0]) }))
    }

    private static func distance(_ p: Point, from a: Point, to b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /// Potrace's smoothing: each corner of the polygon becomes a curve between points on its two sides, unless it
    /// sticks out far enough from them to be a real corner. The points are the sides' midpoints, except that a curve
    /// reaches no further along one side than the length of the other, so a long straight edge runs straight into
    /// the rounded corner at its end instead of bending into it from halfway.
    private func smooth(_ v: [Point], corners: Set<Int>, into path: inout PathWriter) {
        let m = v.count
        guard m >= 3 else { return }
        let length = (0..<m).map { hypot(v[($0 + 1) % m].x - v[$0].x, v[($0 + 1) % m].y - v[$0].y) }
        func along(_ side: Int, from start: Bool, _ d: Double) -> Point {
            let a = v[side], b = v[(side + 1) % m], t = length[side] > 0 ? d / length[side] : 0.5
            return start ? Point(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)) : Point(x: b.x + t * (a.x - b.x), y: b.y + t * (a.y - b.y))
        }
        // Where the curve around each vertex starts (on the side before it) and ends (on the side after it).
        let enter = (0..<m).map { j in along((j + m - 1) % m, from: false, min(length[(j + m - 1) % m] / 2, length[j])) }
        let leave = (0..<m).map { j in along(j, from: true, min(length[j] / 2, length[(j + m - 1) % m])) }
        path.move(leave[m - 1])
        for j in 0..<m {
            let a = enter[j], b = leave[j], p = v[j]
            path.line(a)
            let denominator = abs(b.x - a.x) + abs(b.y - a.y)
            let dd = denominator > 0 ? abs((p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)) / denominator : 0
            let alpha = dd > 1 ? (1 - 1 / dd) / 0.75 : 0
            if corners.contains(j) || alpha >= 1 {
                path.line(p)
                path.line(b)
            } else {
                let alpha = max(alpha, 0.55)
                path.curve(Point(x: a.x + alpha * (p.x - a.x), y: a.y + alpha * (p.y - a.y)),
                           Point(x: b.x + alpha * (p.x - b.x), y: b.y + alpha * (p.y - b.y)), b)
            }
        }
        path.close()
    }

    /// Compact path data: relative commands, one decimal, no spaces before minus signs. Lines that carry straight
    /// on are joined into one, and none is drawn back to where the shape started.
    private struct PathWriter {
        var text = ""
        private var x = 0, y = 0, startX = 0, startY = 0
        /// A line not yet written, in tenths, in case the next one carries straight on from it.
        private var pending: (x: Int, y: Int)?

        private mutating func number(_ tenths: Int) {
            let magnitude = abs(tenths)
            var s = magnitude % 10 == 0 ? "\(magnitude / 10)" : (magnitude < 10 ? "" : "\(magnitude / 10)") + ".\(magnitude % 10)"
            if tenths < 0 { s = "-" + s }
            if let last = text.last, !last.isLetter, !s.hasPrefix("-") { text += " " }
            text += s
        }

        private static func tenths(_ p: Point) -> (x: Int, y: Int) { (Int((p.x * 10).rounded()), Int((p.y * 10).rounded())) }

        private mutating func flush() {
            guard let p = pending else { return }
            pending = nil
            text += "l"
            number(p.x - x); number(p.y - y)
            x = p.x; y = p.y
        }

        mutating func move(_ p: Point) {
            let t = Self.tenths(p)
            text += "m"
            number(t.x - x); number(t.y - y)
            x = t.x; y = t.y
            startX = x; startY = y
        }

        mutating func line(_ p: Point) {
            let t = Self.tenths(p)
            let from = pending ?? (x, y)
            guard t != from else { return }
            if let mid = pending {
                // Carrying straight on (within rounding) from the pending line: extend it instead.
                let cross = (mid.x - x) * (t.y - mid.y) - (mid.y - y) * (t.x - mid.x)
                let dot = (mid.x - x) * (t.x - mid.x) + (mid.y - y) * (t.y - mid.y)
                let span = hypot(Double(t.x - x), Double(t.y - y))
                if dot > 0, Double(abs(cross)) <= span * 0.5 { pending = t; return }
                flush()
            }
            pending = t
        }

        mutating func curve(_ c1: Point, _ c2: Point, _ p: Point) {
            flush()
            text += "c"
            // Control points are relative to the curve's start too.
            for c in [c1, c2] {
                let t = Self.tenths(c)
                number(t.x - x); number(t.y - y)
            }
            let t = Self.tenths(p)
            number(t.x - x); number(t.y - y)
            x = t.x; y = t.y
        }

        mutating func close() {
            if let p = pending, p != (startX, startY) { flush() }
            pending = nil
            text += "z"
            x = startX; y = startY
        }
    }
}
