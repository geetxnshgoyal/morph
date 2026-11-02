package app.morph.core

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import androidx.heifwriter.HeifWriter
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Encoders Android doesn't have built in (TIFF, BMP, GIF), HEIC through the hardware encoder, and camera RAW. */
object ImageFormats {
    /** Raw files from cameras. Android draws DNG and several others itself; the rest fall back to their preview. */
    val rawExtensions = setOf("dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "pef", "srw", "x3f", "3fr", "iiq", "erf", "kdc", "mrw", "rwl")

    /** HEIC needs a hardware HEVC encoder, which most phones have but not every one. */
    val canWriteHeic: Boolean by lazy {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, true) } &&
                runCatching {
                    info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_HEVC).encoderCapabilities
                        .isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ)
                }.getOrDefault(false)
        }
    }

    fun writeHeic(bitmap: Bitmap, quality: Int, out: File): File {
        out.delete()
        try {
            HeifWriter.Builder(out.absolutePath, bitmap.width, bitmap.height, HeifWriter.INPUT_MODE_BITMAP)
                .setQuality(quality).setMaxImages(1).build().use { writer ->
                    writer.start()
                    writer.addBitmap(bitmap)
                    writer.stop(30_000)
                }
        } catch (e: Exception) {
            out.delete()
            throw MorphError("This phone can't make HEIC files: ${e.message ?: "the encoder failed"}")
        }
        return out
    }

    /** The largest JPEG preview a RAW file carries, for the formats Android can't develop itself (CR3 and others). */
    fun rawPreview(file: File, maxPixel: Int?): Bitmap {
        val bytes = file.readBytes()
        var best: IntRange? = null
        var i = 0
        while (i < bytes.size - 3) {
            // A JPEG starts with SOI followed by another marker, and ends at the EOI that closes it.
            if (bytes[i] == 0xFF.toByte() && bytes[i + 1] == 0xD8.toByte() && bytes[i + 2] == 0xFF.toByte()) {
                val end = jpegEnd(bytes, i)
                if (end != null) {
                    if (best == null || end - i > best.last - best.first) best = i..end
                    i = end
                    continue
                }
            }
            i++
        }
        val range = best ?: throw MorphError("Android can't develop ${file.extension.uppercase()} files and ${file.name} has no preview")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, range.first, range.last - range.first + 1, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        val options = BitmapFactory.Options().apply {
            inSampleSize = 1
            if (maxPixel != null) while (longest / (inSampleSize * 2) >= maxPixel) inSampleSize *= 2
        }
        val bitmap = BitmapFactory.decodeByteArray(bytes, range.first, range.last - range.first + 1, options)
            ?: throw MorphError("Couldn't read the preview in ${file.name}")
        return if (maxPixel != null && maxOf(bitmap.width, bitmap.height) > maxPixel) {
            val scale = maxPixel.toFloat() / maxOf(bitmap.width, bitmap.height)
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true)
        } else bitmap
    }

    /** Walks the JPEG's segments to its end, so a thumbnail nested in the EXIF isn't taken for the end. */
    private fun jpegEnd(b: ByteArray, start: Int): Int? {
        var p = start + 2
        while (p + 4 <= b.size) {
            if (b[p] != 0xFF.toByte()) return null
            val marker = b[p + 1].toInt() and 0xFF
            if (marker == 0xD9) return p + 1
            if (marker == 0xFF) { p++; continue }
            val length = ((b[p + 2].toInt() and 0xFF) shl 8) or (b[p + 3].toInt() and 0xFF)
            if (length < 2) return null
            p += 2 + length
            if (marker == 0xDA) {
                // Entropy-coded data runs until a marker that isn't a stuffed byte or a restart.
                while (p + 1 < b.size) {
                    if (b[p] == 0xFF.toByte()) {
                        val next = b[p + 1].toInt() and 0xFF
                        if (next == 0xD9) return p + 1
                        if (next != 0 && next !in 0xD0..0xD7) break
                    }
                    p++
                }
            }
        }
        return null
    }

    private fun Bitmap.pixels() = IntArray(width * height).also { getPixels(it, 0, width, 0, 0, width, height) }

    fun onWhite(bitmap: Bitmap): Bitmap {
        if (!bitmap.hasAlpha()) return bitmap
        return Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888).also {
            Canvas(it).apply { drawColor(Color.WHITE); drawBitmap(bitmap, 0f, 0f, null) }
        }
    }

    /** 24-bit BMP, bottom-up, which every app opens; transparency goes onto white. */
    fun writeBmp(bitmap: Bitmap, out: File): File {
        val image = onWhite(bitmap)
        val w = image.width; val h = image.height
        val rowSize = (w * 3 + 3) / 4 * 4
        val size = 54 + rowSize * h
        val header = ByteBuffer.allocate(54).order(ByteOrder.LITTLE_ENDIAN).apply {
            put('B'.code.toByte()); put('M'.code.toByte()); putInt(size); putInt(0); putInt(54)
            putInt(40); putInt(w); putInt(h); putShort(1); putShort(24); putInt(0); putInt(rowSize * h)
            putInt(2835); putInt(2835); putInt(0); putInt(0)
        }
        val pixels = image.pixels()
        out.outputStream().buffered().use { s ->
            s.write(header.array())
            val row = ByteArray(rowSize)
            for (y in h - 1 downTo 0) {
                for (x in 0 until w) {
                    val c = pixels[y * w + x]
                    row[x * 3] = c.toByte(); row[x * 3 + 1] = (c shr 8).toByte(); row[x * 3 + 2] = (c shr 16).toByte()
                }
                s.write(row)
            }
        }
        return out
    }

    /** Baseline TIFF: uncompressed 8-bit RGB, or RGBA with unassociated alpha when the image has transparency. */
    fun writeTiff(bitmap: Bitmap, out: File): File {
        val w = bitmap.width; val h = bitmap.height
        val alpha = bitmap.hasAlpha()
        val samples = if (alpha) 4 else 3
        val pixels = bitmap.pixels()
        val dataSize = w * h * samples
        val entries = if (alpha) 12 else 11
        val ifdOffset = 8
        val ifdSize = 2 + entries * 12 + 4
        val bitsOffset = ifdOffset + ifdSize
        val resolutionOffset = bitsOffset + samples * 2
        val dataOffset = resolutionOffset + 16
        val buffer = ByteBuffer.allocate(dataOffset).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put('I'.code.toByte()); buffer.put('I'.code.toByte()); buffer.putShort(42); buffer.putInt(ifdOffset)
        buffer.putShort(entries.toShort())
        fun entry(tag: Int, type: Int, count: Int, value: Int) {
            buffer.putShort(tag.toShort()); buffer.putShort(type.toShort()); buffer.putInt(count)
            if (type == 3 && count == 1) { buffer.putShort(value.toShort()); buffer.putShort(0) } else buffer.putInt(value)
        }
        entry(256, 4, 1, w)                       // width
        entry(257, 4, 1, h)                       // height
        entry(258, 3, samples, bitsOffset)        // bits per sample
        entry(259, 3, 1, 1)                       // no compression
        entry(262, 3, 1, 2)                       // RGB
        entry(273, 4, 1, dataOffset)              // strip offset
        entry(277, 3, 1, samples)                 // samples per pixel
        entry(278, 4, 1, h)                       // one strip
        entry(279, 4, 1, dataSize)                // strip byte count
        entry(282, 5, 1, resolutionOffset)        // x resolution
        entry(283, 5, 1, resolutionOffset + 8)    // y resolution
        if (alpha) entry(338, 3, 1, 2)            // extra sample: unassociated alpha
        buffer.putInt(0)
        repeat(samples) { buffer.putShort(8) }
        buffer.putInt(72); buffer.putInt(1); buffer.putInt(72); buffer.putInt(1)
        out.outputStream().buffered().use { s ->
            s.write(buffer.array())
            val row = ByteArray(w * samples)
            for (y in 0 until h) {
                for (x in 0 until w) {
                    val c = pixels[y * w + x]
                    val o = x * samples
                    row[o] = (c shr 16).toByte(); row[o + 1] = (c shr 8).toByte(); row[o + 2] = c.toByte()
                    if (alpha) row[o + 3] = (c ushr 24).toByte()
                }
                s.write(row)
            }
        }
        return out
    }

    // MARK: GIF

    /** A GIF, still or animated. Frames are paletted one at a time, with ordered dithering to keep gradients smooth. */
    class GifWriter(private val stream: OutputStream, private val width: Int, private val height: Int, private val delayMs: Int) {
        private var started = false

        fun add(frame: Bitmap) {
            val image = if (frame.width != width || frame.height != height) Bitmap.createScaledBitmap(frame, width, height, true) else frame
            val pixels = image.pixels()
            val (palette, indices, transparent) = quantize(pixels)
            val out = DataOutputStream(stream)
            if (!started) {
                out.write("GIF89a".toByteArray())
                out.writeLittleShort(width); out.writeLittleShort(height)
                out.write(0); out.write(0); out.write(0) // no global palette
                // Loop forever.
                out.write(byteArrayOf(0x21, 0xFF.toByte(), 11) + "NETSCAPE2.0".toByteArray() + byteArrayOf(3, 1, 0, 0, 0))
                started = true
            }
            out.write(byteArrayOf(0x21, 0xF9.toByte(), 4, if (transparent >= 0) 0x09 else 0x08))
            out.writeLittleShort((delayMs + 5) / 10)
            out.write(if (transparent >= 0) transparent else 0); out.write(0)
            out.write(0x2C); out.writeLittleShort(0); out.writeLittleShort(0); out.writeLittleShort(width); out.writeLittleShort(height)
            out.write(0x80 or 7) // local palette of 256
            for (i in 0 until 256) {
                val c = palette.getOrElse(i) { 0 }
                out.write((c shr 16) and 0xFF); out.write((c shr 8) and 0xFF); out.write(c and 0xFF)
            }
            lzw(indices, out)
        }

        fun finish() { stream.write(0x3B); stream.flush() }

        private fun DataOutputStream.writeLittleShort(v: Int) { write(v and 0xFF); write((v shr 8) and 0xFF) }

        /** Popularity palette over 5-bit-per-channel colours, then nearest-colour mapping with a 4×4 Bayer dither. */
        private fun quantize(pixels: IntArray): Triple<IntArray, ByteArray, Int> {
            val counts = IntArray(32768)
            var hasTransparency = false
            for (c in pixels) {
                if ((c ushr 24) < 128) { hasTransparency = true; continue }
                counts[((c shr 9) and 0x7C00) or ((c shr 6) and 0x3E0) or ((c shr 3) and 0x1F)]++
            }
            val slots = if (hasTransparency) 255 else 256
            val used = counts.indices.filter { counts[it] > 0 }.sortedByDescending { counts[it] }
            val chosen = used.take(slots)
            val palette = IntArray(256)
            chosen.forEachIndexed { i, key ->
                val r = (key shr 10) and 31; val g = (key shr 5) and 31; val b = key and 31
                palette[i] = (r shl 19 or (r shr 2 shl 16)) or (g shl 11 or (g shr 2 shl 8)) or (b shl 3 or (b shr 2))
            }
            val colors = chosen.size.coerceAtLeast(1)
            val transparent = if (hasTransparency) colors.coerceAtMost(255) else -1
            val dither = used.size > slots
            val bayer = intArrayOf(0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5)
            val cache = HashMap<Int, Int>()
            val indices = ByteArray(pixels.size)
            for (i in pixels.indices) {
                val c = pixels[i]
                if ((c ushr 24) < 128) { indices[i] = transparent.toByte(); continue }
                var r = (c shr 16) and 0xFF; var g = (c shr 8) and 0xFF; var b = c and 0xFF
                if (dither) {
                    val d = (bayer[(i / width and 3) * 4 + (i % width and 3)] - 8) * 2
                    r = (r + d).coerceIn(0, 255); g = (g + d).coerceIn(0, 255); b = (b + d).coerceIn(0, 255)
                }
                val key = (r shl 16) or (g shl 8) or b
                indices[i] = cache.getOrPut(key) {
                    var best = 0; var bestDistance = Int.MAX_VALUE
                    for (p in 0 until colors) {
                        val pc = palette[p]
                        val dr = ((pc shr 16) and 0xFF) - r; val dg = ((pc shr 8) and 0xFF) - g; val db = (pc and 0xFF) - b
                        val distance = 2 * dr * dr + 4 * dg * dg + 3 * db * db
                        if (distance < bestDistance) { bestDistance = distance; best = p }
                    }
                    best
                }.toByte()
            }
            return Triple(palette, indices, transparent)
        }

        /** GIF's variable-width LZW, packed into sub-blocks of at most 255 bytes. */
        private fun lzw(indices: ByteArray, out: DataOutputStream) {
            val minCodeSize = 8
            out.write(minCodeSize)
            val clear = 1 shl minCodeSize; val end = clear + 1
            val block = ByteArrayOutputStream()
            var bitBuffer = 0; var bitCount = 0
            var codeSize = minCodeSize + 1
            fun emit(code: Int) {
                bitBuffer = bitBuffer or (code shl bitCount); bitCount += codeSize
                while (bitCount >= 8) {
                    block.write(bitBuffer and 0xFF); bitBuffer = bitBuffer ushr 8; bitCount -= 8
                    if (block.size() == 255) { out.write(255); block.writeTo(out); block.reset() }
                }
            }
            val table = HashMap<Int, Int>()
            var next = end + 1
            emit(clear)
            var prefix = indices[0].toInt() and 0xFF
            for (i in 1 until indices.size) {
                val k = indices[i].toInt() and 0xFF
                val key = (prefix shl 8) or k
                val existing = table[key]
                if (existing != null) { prefix = existing; continue }
                emit(prefix)
                if (next < 4096) {
                    table[key] = next++
                    if (next > (1 shl codeSize) && codeSize < 12) codeSize++
                } else {
                    emit(clear); table.clear(); next = end + 1; codeSize = minCodeSize + 1
                }
                prefix = k
            }
            emit(prefix)
            emit(end)
            if (bitCount > 0) block.write(bitBuffer and 0xFF)
            if (block.size() > 0) {
                for (chunk in block.toByteArray().toList().chunked(255)) { out.write(chunk.size); out.write(chunk.toByteArray()) }
            }
            out.write(0)
        }
    }

    fun writeGif(bitmap: Bitmap, out: File): File {
        out.outputStream().buffered().use { s -> GifWriter(s, bitmap.width, bitmap.height, 0).apply { add(bitmap); finish() } }
        return out
    }
}
