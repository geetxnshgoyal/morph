package app.morph.core

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Turns pixels into an SVG of filled shapes, the way potrace and VTracer do: the colors are reduced to a small
 * palette, specks are folded into what surrounds them, and each color's outline is traced along the pixel edges,
 * evened out, straightened, then smoothed into curves with sharp corners kept. Colors are stacked largest first and
 * each shape also covers the colors drawn above it, so smoothing can't open hairline gaps between neighbors.
 *
 * A port of Tracer.swift in MorphCore; keep them in step.
 */
class Tracer(
    /** What gets traced, at the working size. */
    private val image: Pixels,
    /** The image at its own size (or [image], if that's smaller), where the palette is chosen. */
    private val sample: Pixels,
    private val settings: Settings,
) {
    /** Straight (not premultiplied) RGBA, row by row from the top. */
    class Pixels(val width: Int, val height: Int, val rgba: ByteArray)

    class Settings(
        var colors: Int,
        /** The image is traced at this many pixels squared. */
        val workPixel: Int,
        /** How far, in traced pixels, a straightened outline may stray from the evened-out pixel edges. */
        val tolerance: Double,
        /** Patches smaller than this share of the image are folded into their surroundings. */
        val speckle: Double,
        /** Palette colors closer than this (in RGB) are merged. */
        val merge: Double,
    ) {
        companion object {
            fun of(level: Compression) = when (level) {
                Compression.LIGHT -> Settings(24, 1600, 0.5, 1.0 / 50_000, 6.0)
                Compression.BALANCED -> Settings(16, 1200, 0.75, 1.0 / 25_000, 12.0)
                Compression.STRONG -> Settings(8, 1000, 1.2, 1.0 / 10_000, 20.0)
            }
        }
    }

    private data class RGB(val r: Int, val g: Int, val b: Int)
    private data class Point(val x: Double, val y: Double)

    private val width get() = image.width
    private val height get() = image.height

    fun svg(outWidth: Int, outHeight: Int): String {
        val palette = palette()
        val index = assign(image, palette)
        removeSpecks(index, palette)
        val n = width * height

        // Largest color at the bottom. Each layer covers its own pixels and those of every layer above it.
        val population = IntArray(palette.size)
        for (k in index) if (k >= 0) population[k]++
        val order = palette.indices.filter { population[it] > 0 }.sortedByDescending { population[it] }
        val rank = IntArray(palette.size) { -1 }
        order.forEachIndexed { r, k -> rank[k] = r }
        val ranks = IntArray(n) { if (index[it] < 0) -1 else rank[index[it]] }
        var covered = n - index.count { it < 0 }

        val out = StringBuilder("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$outWidth\" height=\"$outHeight\" viewBox=\"0 0 $width $height\">\n")
        order.forEachIndexed { layer, k ->
            val c = palette[k]
            val d = if (covered == n) "M0 0h${width}v${height}h-${width}z" else outline { ranks[it] >= layer }
            if (d.isNotEmpty()) out.append("<path fill=\"#%02x%02x%02x\" d=\"%s\"/>\n".format(c.r, c.g, c.b, d))
            covered -= population[k]
        }
        return out.append("</svg>\n").toString()
    }

    // MARK: Colors

    private fun distance(a: RGB, b: RGB): Int {
        val dr = a.r - b.r; val dg = a.g - b.g; val db = a.b - b.b
        return 3 * dr * dr + 4 * dg * dg + 2 * db * db
    }

    private fun byte(p: Pixels, i: Int) = p.rgba[i].toInt() and 0xFF

    /** The 15-bit color of each pixel; -1 where it's under half opacity, which counts as transparent. */
    private fun cells(p: Pixels) = IntArray(p.width * p.height) { i ->
        if (byte(p, i * 4 + 3) < 128) -1
        else (byte(p, i * 4) shr 3 shl 10) or (byte(p, i * 4 + 1) shr 3 shl 5) or (byte(p, i * 4 + 2) shr 3)
    }

    /** Each pixel's nearest palette color, or -1 where it's transparent. */
    private fun assign(p: Pixels, palette: List<RGB>): IntArray {
        val nearest = IntArray(32768) { -2 }
        return cells(p).map { c ->
            if (c < 0) return@map -1
            if (nearest[c] == -2) {
                val m = RGB((c shr 10 shl 3) or 4, ((c shr 5) and 31 shl 3) or 4, ((c and 31) shl 3) or 4)
                nearest[c] = palette.indices.minByOrNull { distance(m, palette[it]) } ?: -1
            }
            nearest[c]
        }.toIntArray()
    }

    /**
     * Median cut over a histogram of the sample, refined by k-means, with near-identical colors merged and the
     * in-between colors of antialiased edges dropped.
     */
    private fun palette(): List<RGB> {
        val width = sample.width; val height = sample.height; val n = width * height
        val cell = cells(sample)
        val count = IntArray(32768)
        val sumR = LongArray(32768); val sumG = LongArray(32768); val sumB = LongArray(32768)
        for (p in 0 until n) {
            val c = cell[p]
            if (c < 0) continue
            count[c]++
            sumR[c] += byte(sample, p * 4).toLong(); sumG[c] += byte(sample, p * 4 + 1).toLong(); sumB[c] += byte(sample, p * 4 + 2).toLong()
        }
        val cells = count.indices.filter { count[it] > 0 }
        if (cells.isEmpty()) return emptyList()
        fun mean(c: Int) = RGB((sumR[c] / count[c]).toInt(), (sumG[c] / count[c]).toInt(), (sumB[c] / count[c]).toInt())

        // Median cut: split the busiest, widest box at its median until there are enough boxes.
        class Box(val lo: IntArray, val hi: IntArray, val count: Int)
        fun shrink(lo0: IntArray, hi0: IntArray): Box {
            val lo = intArrayOf(31, 31, 31); val hi = intArrayOf(0, 0, 0); var total = 0
            for (r in lo0[0]..hi0[0]) for (g in lo0[1]..hi0[1]) for (b in lo0[2]..hi0[2]) {
                val c = (r shl 10) or (g shl 5) or b
                if (count[c] == 0) continue
                total += count[c]
                lo[0] = min(lo[0], r); lo[1] = min(lo[1], g); lo[2] = min(lo[2], b)
                hi[0] = max(hi[0], r); hi[1] = max(hi[1], g); hi[2] = max(hi[2], b)
            }
            return Box(lo, hi, total)
        }
        val weight = intArrayOf(3, 4, 2)
        val boxes = mutableListOf(shrink(intArrayOf(0, 0, 0), intArrayOf(31, 31, 31)))
        while (boxes.size < settings.colors) {
            var best = -1; var bestScore = 0L
            boxes.forEachIndexed { i, box ->
                val spread = (0 until 3).maxOf { (box.hi[it] - box.lo[it]) * weight[it] }
                if (spread > 0 && box.count.toLong() * spread > bestScore) { best = i; bestScore = box.count.toLong() * spread }
            }
            if (best < 0) break
            val box = boxes[best]
            val axis = (0 until 3).maxBy { (box.hi[it] - box.lo[it]) * weight[it] }
            val slices = IntArray(32)
            for (r in box.lo[0]..box.hi[0]) for (g in box.lo[1]..box.hi[1]) for (b in box.lo[2]..box.hi[2]) {
                slices[intArrayOf(r, g, b)[axis]] += count[(r shl 10) or (g shl 5) or b]
            }
            var cut = box.lo[axis]; var seen = slices[cut]
            while (cut < box.hi[axis] - 1 && seen * 2 < box.count) { cut++; seen += slices[cut] }
            val lowHi = box.hi.copyOf().also { it[axis] = cut }
            val highLo = box.lo.copyOf().also { it[axis] = cut + 1 }
            boxes[best] = shrink(box.lo, lowHi)
            boxes.add(shrink(highLo, box.hi))
        }
        val palette = boxes.map { box ->
            var r = 0L; var g = 0L; var b = 0L; var w = 0L
            for (x in box.lo[0]..box.hi[0]) for (y in box.lo[1]..box.hi[1]) for (z in box.lo[2]..box.hi[2]) {
                val c = (x shl 10) or (y shl 5) or z
                r += sumR[c]; g += sumG[c]; b += sumB[c]; w += count[c]
            }
            RGB((r / w).toInt(), (g / w).toInt(), (b / w).toInt())
        }.toMutableList()

        // A few rounds of k-means pull each color to the middle of the pixels it stands for.
        val nearest = IntArray(32768) { -1 }
        fun assign(allowed: BooleanArray) {
            for (c in cells) {
                val m = mean(c)
                var best = -1; var bestDistance = Int.MAX_VALUE
                palette.forEachIndexed { k, color ->
                    if (!allowed[k]) return@forEachIndexed
                    val d = distance(m, color)
                    if (d < bestDistance) { best = k; bestDistance = d }
                }
                nearest[c] = best
            }
        }
        val all = BooleanArray(palette.size) { true }
        repeat(4) {
            assign(all)
            val tr = LongArray(palette.size); val tg = LongArray(palette.size); val tb = LongArray(palette.size); val tw = LongArray(palette.size)
            for (c in cells) {
                val k = nearest[c]
                tr[k] += sumR[c]; tg[k] += sumG[c]; tb[k] += sumB[c]; tw[k] += count[c].toLong()
            }
            for (k in palette.indices) if (tw[k] > 0) palette[k] = RGB((tr[k] / tw[k]).toInt(), (tg[k] / tw[k]).toInt(), (tb[k] / tw[k]).toInt())
        }

        // Colors closer than `merge` become one: a faint gradient is better as one flat color than as many
        // ragged bands.
        val weights = LongArray(palette.size)
        assign(all)
        for (c in cells) weights[nearest[c]] += count[c].toLong()
        while (true) {
            var pa = 0; var pb = 0; var closest = settings.merge * settings.merge
            for (a in palette.indices) {
                if (weights[a] == 0L) continue
                for (b in a + 1 until palette.size) {
                    if (weights[b] == 0L) continue
                    val dr = (palette[a].r - palette[b].r).toDouble(); val dg = (palette[a].g - palette[b].g).toDouble(); val db = (palette[a].b - palette[b].b).toDouble()
                    if (dr * dr + dg * dg + db * db < closest) { pa = a; pb = b; closest = dr * dr + dg * dg + db * db }
                }
            }
            if (pa == pb) break
            val total = weights[pa] + weights[pb]
            palette[pa] = RGB(
                ((palette[pa].r * weights[pa] + palette[pb].r * weights[pb]) / total).toInt(),
                ((palette[pa].g * weights[pa] + palette[pb].g * weights[pb]) / total).toInt(),
                ((palette[pa].b * weights[pa] + palette[pb].b * weights[pb]) / total).toInt(),
            )
            weights[pa] = total; weights[pb] = 0
        }
        assign(BooleanArray(palette.size) { weights[it] > 0 })
        val index = IntArray(n) { if (cell[it] < 0) -1 else nearest[cell[it]] }

        // Antialiasing leaves thin rims of in-between colors along edges. A color that is mostly rim, and whose pixels
        // mostly sit next to a solid color close to it or between two solid colors it blends, is dropped; its pixels
        // go to whichever is nearest. Thin text in a color of its own has no such neighbors, so it stays.
        val population = IntArray(palette.size); val rim = IntArray(palette.size)
        for (y in 0 until height) for (x in 0 until width) {
            val p = y * width + x; val k = index[p]
            if (k < 0) continue
            population[k]++
            if ((x > 0 && index[p - 1] != k) || (x < width - 1 && index[p + 1] != k)
                || (y > 0 && index[p - width] != k) || (y < height - 1 && index[p + width] != k)) rim[k]++
        }
        val thin = BooleanArray(palette.size) { population[it] > 0 && rim[it] * 10 >= population[it] * 6 }
        val solid = palette.indices.filter { population[it] > 0 && !thin[it] }
        // The colors within two pixels of each pixel of a thin color, as bits.
        val around = List(palette.size) { mutableListOf<Long>() }
        for (y in 0 until height) for (x in 0 until width) {
            val k = index[y * width + x]
            if (k < 0 || !thin[k]) continue
            var bits = 0L
            for (ny in max(0, y - 2)..min(height - 1, y + 2)) for (nx in max(0, x - 2)..min(width - 1, x + 2)) {
                val q = index[ny * width + nx]
                if (q >= 0) bits = bits or (1L shl q)
            }
            around[k].add(bits)
        }
        fun mostlyBeside(c: Int, colors: Long) = around[c].count { it and colors == colors } * 2 >= around[c].size
        val keep = BooleanArray(palette.size) { population[it] > 0 }
        for (c in palette.indices) {
            if (!thin[c]) continue
            val p = palette[c]
            val blend = solid.any { a ->
                val dr = (p.r - palette[a].r).toDouble(); val dg = (p.g - palette[a].g).toDouble(); val db = (p.b - palette[a].b).toDouble()
                if (dr * dr + dg * dg + db * db <= 24.0 * 24 && mostlyBeside(c, 1L shl a)) return@any true
                solid.any { b ->
                    if (b <= a) return@any false
                    val lr = (palette[b].r - palette[a].r).toDouble(); val lg = (palette[b].g - palette[a].g).toDouble(); val lb = (palette[b].b - palette[a].b).toDouble()
                    val length = lr * lr + lg * lg + lb * lb
                    if (length <= 0) return@any false
                    val t = (dr * lr + dg * lg + db * lb) / length
                    val er = dr - t * lr; val eg = dg - t * lg; val eb = db - t * lb
                    t > 0.05 && t < 0.95 && er * er + eg * eg + eb * eb <= 18.0 * 18 && mostlyBeside(c, (1L shl a) or (1L shl b))
                }
            }
            if (blend) keep[c] = false
        }
        return palette.indices.filter { keep[it] }.map { palette[it] }
    }

    /**
     * Folds patches smaller than the speck size into the color they touch most, preferring patches that stay.
     * Noise is close in color to what surrounds it; a dot or stroke that stands out (the dot on an i, a hairline)
     * is kept unless it's only a pixel or two.
     */
    private fun removeSpecks(index: IntArray, palette: List<RGB>) {
        val n = width * height
        val minimum = max(3, (n * settings.speckle).toInt())
        val label = IntArray(n) { -1 }
        val size = mutableListOf<Int>()
        val small = mutableListOf<Triple<Int, Int, Int>>()
        val pixels = ArrayList<Int>()
        val stack = ArrayList<Int>()
        fun neighbors(p: Int): IntArray {
            val x = p % width
            return intArrayOf(if (x > 0) p - 1 else -1, if (x < width - 1) p + 1 else -1, p - width, p + width)
        }
        for (start in 0 until n) {
            if (label[start] >= 0) continue
            val l = size.size; val k = index[start]; val first = pixels.size
            label[start] = l
            stack.add(start)
            while (stack.isNotEmpty()) {
                val p = stack.removeAt(stack.size - 1)
                pixels.add(p)
                for (q in neighbors(p)) if (q in 0 until n && label[q] < 0 && index[q] == k) { label[q] = l; stack.add(q) }
            }
            size.add(pixels.size - first)
            if (size[l] < minimum) small.add(Triple(l, first, pixels.size))
            else pixels.subList(first, pixels.size).clear()
        }
        for ((l, from, to) in small) {
            val stays = HashMap<Int, Int>(); val any = HashMap<Int, Int>()
            for (i in from until to) for (q in neighbors(pixels[i])) {
                if (q !in 0 until n || label[q] == l) continue
                if (size[label[q]] >= minimum) stays.merge(index[q], 1, Int::plus)
                any.merge(index[q], 1, Int::plus)
            }
            val winner = any.keys.maxWithOrNull(compareBy<Int>({ stays[it] ?: 0 }, { any[it] ?: 0 }, { -it })) ?: continue
            val own = index[pixels[from]]
            if (to - from >= 3 && (own < 0 || winner < 0 || distance(palette[own], palette[winner]) > 64 * 64 * 9)) continue
            for (i in from until to) index[pixels[i]] = winner
        }
    }

    // MARK: Outlines

    /** Path data for the pixels where [inside] holds: every boundary loop, evened out, straightened and smoothed. */
    private fun outline(inside: (Int) -> Boolean): String {
        val columns = width + 1
        // Pixel edges with the inside on their right: 1 east, 2 south, 4 west, 8 north, from each grid vertex.
        val edges = IntArray(columns * (height + 1))
        for (y in 0 until height) for (x in 0 until width) {
            val p = y * width + x
            if (!inside(p)) continue
            if (y == 0 || !inside(p - width)) edges[y * columns + x] = edges[y * columns + x] or 1
            if (x == width - 1 || !inside(p + 1)) edges[y * columns + x + 1] = edges[y * columns + x + 1] or 2
            if (y == height - 1 || !inside(p + width)) edges[(y + 1) * columns + x + 1] = edges[(y + 1) * columns + x + 1] or 4
            if (x == 0 || !inside(p - 1)) edges[(y + 1) * columns + x] = edges[(y + 1) * columns + x] or 8
        }
        val path = PathWriter()
        for (start in edges.indices) {
            while (edges[start] != 0) {
                // Walk the loop through every grid vertex. Where two pixels touch only at a corner, turn right.
                val points = ArrayList<Point>()
                var v = start; var heading = 0
                do {
                    val out = edges[v]
                    var next = out and -out
                    if (out != next && heading != 0) {
                        val right = if (heading == 8) 1 else heading shl 1
                        next = if (out and right != 0) right else out and right.inv()
                    }
                    edges[v] = edges[v] and next.inv()
                    points.add(Point((v % columns).toDouble(), (v / columns).toDouble()))
                    heading = next
                    v += when (next) { 1 -> 1; 2 -> columns; 4 -> -1; else -> -columns }
                } while (v != start)
                if (abs(area(points)) < 2) continue
                val corners = corners(points)
                val (polygon, polygonCorners) = simplify(relaxed(points, corners), corners)
                smooth(polygon, polygonCorners, path)
            }
        }
        return path.toString()
    }

    private fun area(points: List<Point>): Double {
        var a = 0.0
        for (i in points.indices) {
            val p = points[i]; val q = points[(i + 1) % points.size]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    /**
     * Where the outline really turns, as opposed to stepping from pixel to pixel: the direction a few pixels back
     * and a few ahead differ by more than 55°, and both stretches are straight. Only the sharpest point counts.
     */
    private fun corners(points: List<Point>): Set<Int> {
        val n = points.size; val k = 4
        if (n < 4 * k) return emptySet()
        val turn = DoubleArray(n) { i ->
            val p = points[i]; val a = points[(i + n - k) % n]; val b = points[(i + k) % n]
            val ux = p.x - a.x; val uy = p.y - a.y; val wx = b.x - p.x; val wy = b.y - p.y
            acos(((ux * wx + uy * wy) / (hypot(ux, uy) * hypot(wx, wy))).coerceIn(-1.0, 1.0))
        }
        val corners = HashSet<Int>()
        for (i in 0 until n) {
            if (turn[i] <= Math.toRadians(55.0)) continue
            val sharpest = (1..k).all { turn[i] > turn[(i + n - it) % n] && turn[i] >= turn[(i + it) % n] }
            val a = points[(i + n - k) % n]; val b = points[(i + k) % n]
            val straight = (1 until k).all {
                distance(points[(i + n - it) % n], a, points[i]) <= 1 && distance(points[(i + it) % n], points[i], b) <= 1
            }
            if (sharpest && straight) corners.add(i)
        }
        return corners
    }

    /** Evens out the pixel steps by averaging each point with its neighbors a few times, leaving corners alone. */
    private fun relaxed(points: List<Point>, corners: Set<Int>): List<Point> {
        val n = points.size
        var p = points.toMutableList()
        repeat(3) {
            val q = p.toList()
            for (i in 0 until n) {
                if (i in corners) continue
                val a = q[(i + n - 1) % n]; val b = q[(i + 1) % n]
                p[i] = Point((a.x + 2 * q[i].x + b.x) / 4, (a.y + 2 * q[i].y + b.y) / 4)
            }
        }
        return p
    }

    /** Douglas-Peucker between corners. Returns the polygon with the positions of its corners. */
    private fun simplify(points: List<Point>, corners: Set<Int>): Pair<List<Point>, Set<Int>> {
        val n = points.size
        var anchors = corners.sorted()
        if (anchors.size < 2) {
            // Split the loop at the point farthest from where it starts (or from its one corner).
            val from = anchors.firstOrNull() ?: 0
            var far = from; var farthest = -1.0
            for (i in 0 until n) {
                val d = hypot(points[i].x - points[from].x, points[i].y - points[from].y)
                if (d > farthest) { far = i; farthest = d }
            }
            anchors = setOf(from, far).sorted()
        }
        val keep = BooleanArray(n)
        val stack = ArrayList<Pair<Int, Int>>()
        anchors.forEachIndexed { i, a ->
            keep[a] = true
            stack.add(a to if (i + 1 < anchors.size) anchors[i + 1] else anchors[0] + n)
        }
        while (stack.isNotEmpty()) {
            val (a, b) = stack.removeAt(stack.size - 1)
            if (b - a <= 1) continue
            val p = points[a % n]; val q = points[b % n]
            var at = -1; var worst = -1.0
            for (i in a + 1 until b) {
                val d = distance(points[i % n], p, q)
                if (d > worst) { at = i; worst = d }
            }
            if (worst > settings.tolerance) {
                keep[at % n] = true
                stack.add(a to at); stack.add(at to b)
            }
        }
        val kept = points.indices.filter { keep[it] }
        return kept.map { points[it] } to kept.indices.filter { kept[it] in corners }.toSet()
    }

    private fun distance(p: Point, a: Point, b: Point): Double {
        val dx = b.x - a.x; val dy = b.y - a.y; val length = dx * dx + dy * dy
        if (length <= 0) return hypot(p.x - a.x, p.y - a.y)
        val t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / length).coerceIn(0.0, 1.0)
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /**
     * Potrace's smoothing: each corner of the polygon becomes a curve between points on its two sides, unless it
     * sticks out far enough from them to be a real corner. A curve reaches no further along one side than the
     * length of the other, so a long straight edge runs straight into the rounded corner at its end.
     */
    private fun smooth(v: List<Point>, corners: Set<Int>, path: PathWriter) {
        val m = v.size
        if (m < 3) return
        val length = DoubleArray(m) { hypot(v[(it + 1) % m].x - v[it].x, v[(it + 1) % m].y - v[it].y) }
        fun along(side: Int, fromStart: Boolean, d: Double): Point {
            val a = v[side]; val b = v[(side + 1) % m]; val t = if (length[side] > 0) d / length[side] else 0.5
            return if (fromStart) Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)) else Point(b.x + t * (a.x - b.x), b.y + t * (a.y - b.y))
        }
        val enter = List(m) { j -> along((j + m - 1) % m, false, min(length[(j + m - 1) % m] / 2, length[j])) }
        val leave = List(m) { j -> along(j, true, min(length[j] / 2, length[(j + m - 1) % m])) }
        path.move(leave[m - 1])
        for (j in 0 until m) {
            val a = enter[j]; val b = leave[j]; val p = v[j]
            path.line(a)
            val denominator = abs(b.x - a.x) + abs(b.y - a.y)
            val dd = if (denominator > 0) abs((p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)) / denominator else 0.0
            val alpha = if (dd > 1) (1 - 1 / dd) / 0.75 else 0.0
            if (j in corners || alpha >= 1) {
                path.line(p)
                path.line(b)
            } else {
                val s = max(alpha, 0.55)
                path.curve(Point(a.x + s * (p.x - a.x), a.y + s * (p.y - a.y)), Point(b.x + s * (p.x - b.x), b.y + s * (p.y - b.y)), b)
            }
        }
        path.close()
    }

    /** Compact path data: relative commands, one decimal, straight runs of lines joined. */
    private class PathWriter {
        private val text = StringBuilder()
        private var x = 0; private var y = 0; private var startX = 0; private var startY = 0
        private var pendingX = 0; private var pendingY = 0; private var pending = false

        private fun number(tenths: Int) {
            val magnitude = abs(tenths)
            var s = if (magnitude % 10 == 0) "${magnitude / 10}" else (if (magnitude < 10) "" else "${magnitude / 10}") + ".${magnitude % 10}"
            if (tenths < 0) s = "-$s"
            if (text.isNotEmpty() && !text.last().isLetter() && !s.startsWith("-")) text.append(' ')
            text.append(s)
        }

        private fun tenths(v: Double) = (v * 10).roundToInt()

        private fun flush() {
            if (!pending) return
            pending = false
            text.append('l')
            number(pendingX - x); number(pendingY - y)
            x = pendingX; y = pendingY
        }

        fun move(p: Point) {
            val tx = tenths(p.x); val ty = tenths(p.y)
            text.append('m')
            number(tx - x); number(ty - y)
            x = tx; y = ty; startX = x; startY = y
        }

        fun line(p: Point) {
            val tx = tenths(p.x); val ty = tenths(p.y)
            val fx = if (pending) pendingX else x; val fy = if (pending) pendingY else y
            if (tx == fx && ty == fy) return
            if (pending) {
                // Carrying straight on (within rounding) from the pending line: extend it instead.
                val cross = (pendingX - x).toLong() * (ty - pendingY) - (pendingY - y).toLong() * (tx - pendingX)
                val dot = (pendingX - x).toLong() * (tx - pendingX) + (pendingY - y).toLong() * (ty - pendingY)
                val span = hypot((tx - x).toDouble(), (ty - y).toDouble())
                if (dot > 0 && abs(cross) <= span * 0.5) { pendingX = tx; pendingY = ty; return }
                flush()
            }
            pending = true; pendingX = tx; pendingY = ty
        }

        fun curve(c1: Point, c2: Point, p: Point) {
            flush()
            text.append('c')
            for (c in listOf(c1, c2, p)) { number(tenths(c.x) - x); number(tenths(c.y) - y) }
            x = tenths(p.x); y = tenths(p.y)
        }

        fun close() {
            if (pending && (pendingX != startX || pendingY != startY)) flush()
            pending = false
            text.append('z')
            x = startX; y = startY
        }

        override fun toString() = text.toString()
    }
}
