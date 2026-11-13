@file:OptIn(UnstableApi::class)

package app.morph.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.media.ExifInterface
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.media3.common.MediaItem
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.multipdf.Splitter
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDResources
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.text.PDFTextStripper
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// Android port of MorphCore: same actions, same naming, originals never touched.

class MorphError(message: String) : Exception(message)

enum class FileKind {
    IMAGE, VIDEO, AUDIO, PDF, DOCUMENT, SUBTITLE, DATA, ARCHIVE, OTHER;

    companion object {
        fun of(file: File): FileKind = when (val ext = file.extension.lowercase()) {
            "jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "bmp", "avif", "svg", "tif", "tiff", in ImageFormats.rawExtensions -> IMAGE
            "mp4", "mov", "m4v", "3gp", "webm", "mkv" -> VIDEO
            "mp3", "m4a", "aac", "wav", "ogg", "flac", "opus", "amr", "aiff", "aif" -> AUDIO
            "pdf" -> PDF
            "srt", "vtt" -> SUBTITLE
            "csv", "tsv", "json" -> DATA
            "md", "markdown", "docx", "odt", "rtf", "html", "htm", "txt", "text" -> DOCUMENT
            "zip", "tar", "gz", "tgz" -> ARCHIVE
            else -> OTHER
        }
    }
}

enum class Group(val label: String) { CONVERT("Convert"), TOOL("Tools"), RECIPE("Recipes") }

enum class Compression(val label: String, val detail: String, val quality: Int, val videoHeight: Int, val videoBitrate: Int) {
    LIGHT("Light", "Barely noticeable, modest savings.", 85, 1080, 5_000_000),
    BALANCED("Balanced", "Good quality, much smaller files.", 70, 720, 2_500_000),
    STRONG("Strong", "Smallest files, visible softening.", 50, 480, 1_200_000),
}

/**
 * Knobs shared by every action. Results are written under [outDir], then published to the gallery or Downloads/Morph.
 * [targetBytes] makes Compress fit under a size, for upload forms. [colors] is the palette size when tracing an
 * image into an SVG; unset picks one from [compression]. [exactSize] makes Resize crop to exactly that size for
 * passport, visa and exam forms, with [caption] and the date printed under the photo when set.
 */
class Options(
    val compression: Compression, val outDir: File, val targetBytes: Int? = null, val colors: Int? = null,
    val exactSize: PixelSize? = null, val caption: String? = null,
)

/** An exact width × height in pixels, for forms that ask for one ("600 × 600", "413 × 531"). */
data class PixelSize(val width: Int, val height: Int) {
    val label get() = "$width × $height"
    val key get() = "${width}x$height"

    companion object {
        /** Parses "600x600", "600 × 600" or "600*600". */
        fun parse(text: String): PixelSize? {
            val parts = text.lowercase().split('x', '×', '*', ' ', ',').mapNotNull { it.trim().toIntOrNull() }
            return if (parts.size == 2 && parts.all { it in 16..8000 }) PixelSize(parts[0], parts[1]) else null
        }

        /** Sizes people are asked for most, grouped for a menu. Millimetre sizes are at 300 dpi. */
        val presets = listOf(
            "Passport and visa" to listOf(
                "US or India, 2 × 2 in" to PixelSize(600, 600),
                "Schengen, UK, 35 × 45 mm" to PixelSize(413, 531),
                "China visa, 33 × 48 mm" to PixelSize(354, 472),
            ),
            "Exams" to listOf(
                "Exam photo, 3.5 × 4.5 cm" to PixelSize(413, 531),
                "Bank exams photo" to PixelSize(200, 230),
            ),
            "Signature" to listOf(
                "Signature, small" to PixelSize(140, 60),
                "Signature, large" to PixelSize(280, 120),
            ),
            "Social and web" to listOf(
                "Square post" to PixelSize(1080, 1080),
                "Portrait post" to PixelSize(1080, 1350),
                "Story" to PixelSize(1080, 1920),
                "Full HD" to PixelSize(1920, 1080),
                "HD" to PixelSize(1280, 720),
                "Profile picture" to PixelSize(400, 400),
            ),
        )
    }
}

/** Size limits offered for Compress, for upload forms that cap file size; 0 is no limit. Sizes are decimal. */
object SizeLimit {
    val presets = listOf(20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000, 2_000_000, 5_000_000)

    fun label(bytes: Int): String = when {
        bytes <= 0 -> "No limit"
        bytes < 1_000_000 -> "${(bytes + 500) / 1000} KB"
        bytes % 1_000_000 == 0 -> "${bytes / 1_000_000} MB"
        else -> "%.1f MB".format(bytes / 1e6)
    }

    fun detail(bytes: Int) =
        if (bytes <= 0) "Compress makes the file smaller at the level above. Set a limit for upload forms that cap file size."
        else "Compress fits photos under ${label(bytes)} as JPG, at the best quality that fits, ready for upload forms."

    /** "300 KB", "1.5mb", "200k" or plain bytes. */
    fun parse(text: String): Int? {
        val s = text.trim().lowercase().replace(" ", "")
        val units = listOf("gb" to 1e9, "g" to 1e9, "mb" to 1e6, "m" to 1e6, "kb" to 1e3, "k" to 1e3, "b" to 1.0)
        for ((suffix, mult) in units) if (s.endsWith(suffix)) return s.dropLast(suffix.length).toDoubleOrNull()?.let { (it * mult).toInt() }
        return s.toIntOrNull()
    }
}

/** [icon] is a key the UI maps to a Material symbol, keeping the engine free of UI types. */
class Action(
    val id: String,
    val title: String,
    val icon: String,
    val group: Group,
    val kinds: Set<FileKind>,
    val combinesInputs: Boolean = false,
    val minimumInputs: Int = 1,
    /** Hidden when every input already has this extension (no "JPG → JPG"). */
    val targetExtension: String? = null,
    val run: suspend (Context, List<File>, Options) -> List<File>,
) {
    /** Edits that keep an image in its own format and work on its pixels, which an SVG doesn't have. */
    private val editsPixels get() = id in setOf("tool.compress", "tool.strip-metadata", "tool.redact-faces", "tool.redact-pii")

    fun accepts(files: List<File>): Boolean {
        if (files.size < minimumInputs) return false
        if (!files.all { FileKind.of(it) in kinds }) return false
        if (editsPixels && files.any(VectorOps::isSvg)) return false
        val ext = targetExtension ?: return true
        return !files.all { it.extension.lowercase().let { e -> e == ext || (ext == "jpg" && e == "jpeg") } }
    }
}

object Library {
    private fun one(
        id: String, title: String, icon: String, group: Group, kinds: Set<FileKind>, target: String? = null,
        body: suspend (Context, File, Options) -> File,
    ) = Action(id, title, icon, group, kinds, targetExtension = target) { ctx, files, o -> files.map { body(ctx, it, o) } }

    private fun pdfBox(context: Context) = com.tom_roush.pdfbox.android.PDFBoxResourceLoader.init(context.applicationContext)

    private val image = setOf(FileKind.IMAGE)
    private val media = setOf(FileKind.AUDIO, FileKind.VIDEO)

    private fun image(format: ImageFormat) =
        one("convert.${format.ext}", format.ext.uppercase(), "photo", Group.CONVERT, image, format.ext) { _, f, o -> ImageOps.convert(f, format, o) }

    val actions: List<Action> = buildList {
        // Images: the common formats, SVG and PDF come first, as on the Mac; rarer formats follow.
        val common = listOf(ImageFormat.JPG, ImageFormat.PNG, ImageFormat.HEIC, ImageFormat.WEBP)
        common.filter { it.isAvailable }.forEach { add(image(it)) }
        add(one("convert.svg", "SVG", "vector", Group.CONVERT, image, "svg") { _, f, o -> VectorOps.trace(f, o) })
        add(Action("convert.images-pdf", "PDF", "pdf", Group.CONVERT, image, combinesInputs = true) { _, files, o -> listOf(PdfOps.fromImages(files, o)) })
        ImageFormat.entries.filter { it !in common && it.isAvailable }.forEach { add(image(it)) }

        // Video
        add(one("convert.video-mp4", "MP4", "video", Group.CONVERT, setOf(FileKind.VIDEO), "mp4") { ctx, f, o -> MediaOps.transform(ctx, f, Output.file(f, "mp4", null, o)) })
        // A MOV is the same ISO media file as an MP4, with QuickTime's name; Media3 writes both.
        add(one("convert.video-mov", "MOV", "video", Group.CONVERT, setOf(FileKind.VIDEO), "mov") { ctx, f, o -> MediaOps.transform(ctx, f, Output.file(f, "mov", null, o)) })
        add(one("convert.video-gif", "GIF", "gif", Group.CONVERT, setOf(FileKind.VIDEO)) { _, f, o -> VideoOps.toGif(f, o) })

        // Audio (video inputs give their soundtrack)
        add(one("convert.audio-m4a", "M4A", "audio", Group.CONVERT, media, "m4a") { ctx, f, o -> MediaOps.transform(ctx, f, Output.file(f, "m4a", null, o), removeVideo = true) })
        for (ext in listOf("wav", "aiff")) add(one("convert.audio-$ext", ext.uppercase(), "audio", Group.CONVERT, media, ext) { _, f, o -> AudioOps.convert(f, ext, o) })
        for ((ext, codec) in listOf("flac" to AudioOps.Codec.FLAC, "ogg" to AudioOps.Codec.OGG, "opus" to AudioOps.Codec.OPUS)) {
            if (codec.isAvailable) add(one("convert.audio-$ext", ext.uppercase(), "audio", Group.CONVERT, media, ext) { _, f, o -> AudioOps.convert(f, ext, o) })
        }

        // PDF & documents
        add(Action("convert.pdf-images", "Images", "pages", Group.CONVERT, setOf(FileKind.PDF)) { _, files, o -> files.flatMap { PdfOps.toImages(it, o) } })
        add(one("convert.pdf-text", "Text", "text", Group.CONVERT, setOf(FileKind.PDF)) { ctx, f, o -> pdfBox(ctx); PdfOps.toText(f, o) })
        for (ext in DocOps.outputFormats) {
            val kinds = when (ext) {
                "pdf" -> setOf(FileKind.DOCUMENT, FileKind.DATA, FileKind.SUBTITLE)
                "docx" -> setOf(FileKind.DOCUMENT, FileKind.PDF)
                else -> setOf(FileKind.DOCUMENT)
            }
            add(one("convert.doc-$ext", ext.uppercase(), "document", Group.CONVERT, kinds, ext) { ctx, f, o -> pdfBox(ctx); DocOps.convert(f, ext, o) })
        }
        for (ext in listOf("srt", "vtt")) add(one("convert.sub-$ext", ext.uppercase(), "subtitles", Group.CONVERT, setOf(FileKind.SUBTITLE), ext) { _, f, o -> DocOps.convertSubtitle(f, ext, o) })
        for (ext in listOf("csv", "tsv", "json")) add(one("convert.data-$ext", ext.uppercase(), "table", Group.CONVERT, setOf(FileKind.DATA), ext) { _, f, o -> DocOps.convertData(f, ext, o) })

        // Tools
        add(one("tool.compress", "Compress", "compress", Group.TOOL, setOf(FileKind.IMAGE, FileKind.VIDEO, FileKind.PDF)) { ctx, f, o ->
            val target = o.targetBytes
            when {
                FileKind.of(f) == FileKind.VIDEO -> MediaOps.compress(ctx, f, o)
                FileKind.of(f) == FileKind.PDF -> { pdfBox(ctx); PdfOps.compress(f, o) }
                target != null -> ImageOps.underSize(f, target, o)
                else -> ImageOps.compress(f, o)
            }
        })
        add(one("tool.resize", "Resize", "resize", Group.TOOL, image) { _, f, o -> o.exactSize?.let { ImageOps.resizeExactly(f, it, o) } ?: ImageOps.resize(f, 2048, o) })
        add(one("tool.strip-metadata", "Remove Metadata", "strip", Group.TOOL, setOf(FileKind.IMAGE, FileKind.VIDEO, FileKind.AUDIO)) { ctx, f, o ->
            if (FileKind.of(f) == FileKind.IMAGE) ImageOps.stripMetadata(f, o) else VideoOps.stripMetadata(ctx, f, o)
        })
        add(one("tool.redact-faces", "Blur Faces", "face", Group.TOOL, image) { _, f, o -> VisionOps.redactFaces(f, o) })
        add(one("tool.redact-pii", "Hide Personal Info", "redact", Group.TOOL, image) { _, f, o -> VisionOps.redactPersonalInfo(f, o) })
        add(one("tool.ocr", "Extract Text", "text", Group.TOOL, setOf(FileKind.IMAGE, FileKind.PDF)) { ctx, f, o -> pdfBox(ctx); VisionOps.ocr(f, o) })
        add(one("tool.qr", "Read QR", "qr", Group.TOOL, setOf(FileKind.IMAGE, FileKind.PDF)) { _, f, o -> VisionOps.readCodes(f, o) })
        add(Action("tool.merge-pdf", "Merge PDFs", "merge", Group.TOOL, setOf(FileKind.PDF), combinesInputs = true, minimumInputs = 2) { ctx, files, o ->
            pdfBox(ctx); listOf(PdfOps.merge(files, o))
        })
        add(one("tool.split-pdf", "Split PDF", "split", Group.TOOL, setOf(FileKind.PDF)) { ctx, f, o -> pdfBox(ctx); PdfOps.split(f, o) })
        add(one("tool.mute", "Mute", "mute", Group.TOOL, setOf(FileKind.VIDEO)) { ctx, f, o -> MediaOps.transform(ctx, f, Output.file(f, "mp4", "muted", o), removeAudio = true) })
        add(Action("tool.snapshots", "Snapshots", "snapshot", Group.TOOL, setOf(FileKind.VIDEO)) { _, files, o -> files.flatMap { VideoOps.snapshots(it, o) } })
        add(one("tool.normalize", "Normalize Loudness", "loudness", Group.TOOL, setOf(FileKind.AUDIO)) { _, f, o -> AudioOps.normalize(f, o) })
        add(one("tool.trim-silence", "Trim Silence", "trim", Group.TOOL, setOf(FileKind.AUDIO)) { _, f, o -> AudioOps.trimSilence(f, o) })
        add(Action("tool.zip", "Zip", "zip", Group.TOOL, FileKind.entries.toSet(), combinesInputs = true) { _, files, o -> listOf(ArchiveOps.zip(files, o)) })
        add(one("tool.extract", "Extract", "unzip", Group.TOOL, setOf(FileKind.ARCHIVE)) { _, f, o -> ArchiveOps.extract(f, o) })

        // Recipes
        add(one("recipe.web", "Web Image", "recipe", Group.RECIPE, image) { _, f, o ->
            ImageOps.write(ImageOps.decode(f, 1600), ImageFormat.WEBP, 80, Output.file(f, "webp", "web", o))
        })
        add(one("recipe.1mb", "Under 1 MB", "recipe", Group.RECIPE, image) { _, f, o -> ImageOps.underSize(f, 1_000_000, o) })
        add(one("recipe.safe", "Share-Safe Photo", "recipe", Group.RECIPE, image) { _, f, o ->
            ImageOps.write(ImageOps.decode(f, 2048), ImageFormat.JPG, 85, Output.file(f, "jpg", "safe", o))
        })
    }

    fun actionsFor(files: List<File>) = actions.filter { it.accepts(files) }
}

class RunResult(val outputs: List<File>, val failures: List<String>)

object Runner {
    /** Runs on a background dispatcher; [progress] reports files finished so far. */
    suspend fun run(
        context: Context, action: Action, inputs: List<File>, options: Options,
        progress: (done: Int, total: Int) -> Unit,
    ): RunResult = withContext(Dispatchers.Default) {
        options.outDir.mkdirs()
        val outputs = mutableListOf<File>()
        val failures = mutableListOf<String>()
        if (action.combinesInputs) {
            try { outputs += action.run(context, inputs, options) } catch (e: Exception) { failures += e.readable() }
            catch (e: OutOfMemoryError) { failures += "Too large to open on this phone" }
            progress(inputs.size, inputs.size)
        } else {
            inputs.forEachIndexed { i, file ->
                try { outputs += action.run(context, listOf(file), options) } catch (e: Exception) { failures += "${file.name}: ${e.readable()}" }
                catch (e: OutOfMemoryError) { failures += "${file.name}: too large to open on this phone" }
                progress(i + 1, inputs.size)
            }
        }
        RunResult(outputs, failures)
    }

    private fun Exception.readable() = message ?: javaClass.simpleName
}

// MARK: - Output naming

object Output {
    /** "<name> <suffix>.<ext>" in the output folder, numbered if taken. */
    fun file(source: File, ext: String, suffix: String?, options: Options): File {
        val base = source.nameWithoutExtension + (suffix?.let { " $it" } ?: "")
        return unique(options.outDir, base, ext)
    }

    @Synchronized
    fun unique(folder: File, base: String, ext: String): File {
        folder.mkdirs()
        fun make(name: String) = File(folder, if (ext.isEmpty()) name else "$name.$ext")
        var candidate = make(base)
        var i = 2
        while (candidate.exists()) candidate = make("$base ${i++}")
        candidate.createNewFile()
        return candidate
    }
}

// MARK: - Images

enum class ImageFormat(val ext: String) {
    JPG("jpg"), PNG("png"), HEIC("heic"), WEBP("webp"), TIFF("tiff"), GIF("gif"), BMP("bmp");

    val isAvailable get() = this != HEIC || ImageFormats.canWriteHeic
}

object ImageOps {
    /** Decodes with EXIF orientation applied; downscales (never upscales) to [maxPixel]. SVGs are drawn at that size. */
    fun decode(file: File, maxPixel: Int? = null): Bitmap = when {
        VectorOps.isSvg(file) -> VectorOps.render(file, maxPixel)
        // Android develops DNG and some other RAW files itself; for the rest, the camera's own full-size preview.
        file.extension.lowercase() in setOf("tif", "tiff") -> ImageFormats.decodeTiff(file, maxPixel)
        file.extension.lowercase() in ImageFormats.rawExtensions ->
            runCatching { decodeNative(file, maxPixel) }.getOrElse { ImageFormats.rawPreview(file, maxPixel) }
        else -> decodeNative(file, maxPixel)
    }

    private fun decodeNative(file: File, maxPixel: Int?): Bitmap =
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val longest = max(info.size.width, info.size.height)
            if (maxPixel != null && longest > maxPixel) {
                val scale = maxPixel.toDouble() / longest
                decoder.setTargetSize(
                    (info.size.width * scale).roundToInt().coerceAtLeast(1),
                    (info.size.height * scale).roundToInt().coerceAtLeast(1),
                )
            }
        }

    fun write(bitmap: Bitmap, format: ImageFormat, quality: Int, out: File): File {
        val image = if (format == ImageFormat.JPG && bitmap.hasAlpha()) flatten(bitmap) else bitmap
        val compress = when (format) {
            ImageFormat.JPG -> Bitmap.CompressFormat.JPEG
            ImageFormat.PNG -> Bitmap.CompressFormat.PNG
            ImageFormat.WEBP -> Bitmap.CompressFormat.WEBP_LOSSY
            ImageFormat.HEIC -> return ImageFormats.writeHeic(image, quality, out)
            ImageFormat.TIFF -> return ImageFormats.writeTiff(image, out)
            ImageFormat.GIF -> return ImageFormats.writeGif(image, out)
            ImageFormat.BMP -> return ImageFormats.writeBmp(image, out)
        }
        out.outputStream().use { if (!image.compress(compress, quality, it)) throw MorphError("Couldn't encode ${format.ext.uppercase()}") }
        return out
    }

    /** JPEG has no transparency: put the image on white. */
    private fun flatten(bitmap: Bitmap): Bitmap {
        val flat = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        Canvas(flat).apply { drawColor(Color.WHITE); drawBitmap(bitmap, 0f, 0f, null) }
        return flat
    }

    fun sameFormat(file: File) = when (file.extension.lowercase()) {
        "jpg", "jpeg", "heic", "heif", "avif", in ImageFormats.rawExtensions -> ImageFormat.JPG
        "webp" -> ImageFormat.WEBP
        else -> ImageFormat.PNG
    }

    fun convert(file: File, format: ImageFormat, o: Options) =
        write(decode(file), format, 92, Output.file(file, format.ext, null, o))

    /** Lossy re-encode; lossless sources become JPG, or WebP when they have transparency. */
    fun compress(file: File, o: Options): File {
        val bitmap = decode(file)
        val format = when (file.extension.lowercase()) {
            "jpg", "jpeg" -> ImageFormat.JPG
            "webp" -> ImageFormat.WEBP
            else -> if (bitmap.hasAlpha()) ImageFormat.WEBP else ImageFormat.JPG
        }
        return write(bitmap, format, o.compression.quality, Output.file(file, format.ext, "compressed", o))
    }

    /** Named by the size actually written: smaller images are never upscaled. */
    fun resize(file: File, maxPixel: Int, o: Options): File {
        val bitmap = decode(file, maxPixel)
        val format = sameFormat(file)
        return write(bitmap, format, 90, Output.file(file, format.ext, "${max(bitmap.width, bitmap.height)}px", o))
    }

    /**
     * Exactly [size], cropped to fill, as a JPG with no metadata: what passport, visa and exam forms ask for. With a
     * caption, the name and the date the photo was taken go in a white strip at the bottom, inside the size. With a
     * size limit, the JPG is fitted under it at that size.
     */
    fun resizeExactly(file: File, size: PixelSize, o: Options): File {
        // Decode big enough that cropping never has to stretch the photo.
        val photo = decode(file, max(size.width, size.height) * 3)
        val caption = o.caption?.trim()?.takeIf { it.isNotEmpty() }
        val image = fitted(photo, size, caption, captureDate(file) ?: java.util.Date())
        val out = Output.file(file, "jpg", size.key, o)
        val target = o.targetBytes ?: return write(image, ImageFormat.JPG, 92, out)
        // The size is fixed, so only quality can give: search the best JPG that fits.
        var lo = 5; var hi = 95; var best: ByteArray? = null
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            val bytes = java.io.ByteArrayOutputStream().also { image.compress(Bitmap.CompressFormat.JPEG, mid, it) }.toByteArray()
            if (bytes.size <= target) { best = bytes; lo = mid + 1 } else hi = mid - 1
        }
        if (best == null) {
            out.delete()
            throw MorphError("${size.label} can't get under ${SizeLimit.label(target)}; pick a larger size limit")
        }
        out.writeBytes(best)
        return out
    }

    /** [photo] scaled to cover [size] and cropped, keeping more of the top (where faces are) than the bottom. */
    private fun fitted(photo: Bitmap, size: PixelSize, caption: String?, date: java.util.Date): Bitmap {
        val w = size.width.toFloat(); val h = size.height.toFloat()
        val strip = if (caption == null) 0f else max((h * 0.16f).roundToInt(), 18).toFloat()
        val out = Bitmap.createBitmap(size.width, size.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        val areaH = h - strip
        val scale = max(w / photo.width, areaH / photo.height)
        // The part of the photo that fills the area, centred across and a bit above centre down.
        val srcW = w / scale; val srcH = areaH / scale
        val left = (photo.width - srcW) / 2; val top = (photo.height - srcH) * 0.3f
        canvas.drawBitmap(photo, Rect(left.roundToInt(), top.roundToInt(), (left + srcW).roundToInt(), (top + srcH).roundToInt()),
            RectF(0f, 0f, w, areaH), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        if (caption != null) {
            val lines = listOf(caption, java.text.SimpleDateFormat("dd/MM/yyyy", java.util.Locale.US).format(date))
            var textSize = strip * 0.36f
            val paints = lines.indices.map { i ->
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK
                    typeface = if (i == 0) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                    textAlign = Paint.Align.CENTER
                }
            }
            paints.forEach { it.textSize = textSize }
            val widest = lines.indices.maxOf { paints[it].measureText(lines[it]) }
            if (widest > w * 0.92f) { textSize *= w * 0.92f / widest; paints.forEach { it.textSize = textSize } }
            val lineHeight = textSize * 1.15f
            var y = areaH + strip / 2 - lineHeight * (lines.size - 1) / 2 + textSize * 0.35f
            lines.forEachIndexed { i, line -> canvas.drawText(line, w / 2, y, paints[i]); y += lineHeight }
        }
        return out
    }

    /** When the photo was taken, from its EXIF data. */
    private fun captureDate(file: File): java.util.Date? = runCatching {
        val text = ExifInterface(file.path).getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: return null
        java.text.SimpleDateFormat("yyyy:MM:dd HH:mm:ss", java.util.Locale.US).parse(text)
    }.getOrNull()

    /** Re-encoding keeps the pixels and drops EXIF/GPS and every other metadata block. */
    fun stripMetadata(file: File, o: Options): File {
        val format = sameFormat(file)
        return write(decode(file), format, 95, Output.file(file, format.ext, "clean", o))
    }

    /** A JPEG (what upload forms accept) under [target]: searches quality, then downscales until the file fits. */
    fun underSize(file: File, target: Int, o: Options): File {
        val out = Output.file(file, "jpg", "compressed", o)
        var longest: Int? = null
        while (true) {
            val bitmap = flatten(decode(file, longest))
            var lo = 5; var hi = 95; var best: ByteArray? = null
            while (lo <= hi) {
                val mid = (lo + hi) / 2
                val bytes = java.io.ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, mid, it) }.toByteArray()
                if (bytes.size <= target) { best = bytes; lo = mid + 1 } else hi = mid - 1
            }
            best?.let { out.writeBytes(it); return out }
            longest = (max(bitmap.width, bitmap.height) * 0.8).toInt()
            if (longest < 64) break
        }
        out.delete()
        throw MorphError("Couldn't get ${file.name} under ${SizeLimit.label(target)}")
    }
}

// MARK: - PDF

object PdfOps {
    /** One page per image, at most A4-ish size in points. SVGs stay vectors. */
    fun fromImages(files: List<File>, o: Options): File {
        val doc = PdfDocument()
        try {
            files.forEachIndexed { i, file ->
                if (VectorOps.isSvg(file)) {
                    val svg = VectorOps.document(file)
                    val scale = 842.0 / max(svg.width, svg.height)
                    val w = (svg.width * scale).roundToInt(); val h = (svg.height * scale).roundToInt()
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(w, h, i + 1).create())
                    svg.draw(page.canvas, w, h)
                    doc.finishPage(page)
                    return@forEachIndexed
                }
                val bitmap = ImageOps.decode(file, 2400)
                val scale = 842.0 / max(bitmap.width, bitmap.height)
                val w = (bitmap.width * scale).roundToInt(); val h = (bitmap.height * scale).roundToInt()
                val page = doc.startPage(PdfDocument.PageInfo.Builder(w, h, i + 1).create())
                page.canvas.drawBitmap(bitmap, null, Rect(0, 0, w, h), Paint(Paint.FILTER_BITMAP_FLAG))
                doc.finishPage(page)
            }
            val name = if (files.size == 1) files[0].nameWithoutExtension else "Images"
            val out = Output.unique(o.outDir, name, "pdf")
            out.outputStream().use { doc.writeTo(it) }
            return out
        } finally {
            doc.close()
        }
    }

    /** Pages drawn at [scale] × 72 dpi on white, for OCR and code reading. */
    fun renderPages(file: File, scale: Float): List<Bitmap> =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { pdf ->
                (0 until pdf.pageCount).map { i ->
                    pdf.openPage(i).use { page ->
                        Bitmap.createBitmap((page.width * scale).toInt(), (page.height * scale).toInt(), Bitmap.Config.ARGB_8888).also {
                            it.eraseColor(Color.WHITE)
                            page.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        }
                    }
                }
            }
        }

    private fun open(file: File): PDDocument = try { PDDocument.load(file) } catch (e: Exception) {
        throw MorphError("Couldn't open ${file.name}: ${e.message}")
    }

    /** The text a PDF carries, page by page; scanned pages have none. */
    fun text(file: File): String = open(file).use { doc -> PDFTextStripper().getText(doc).trim() }

    /** Embedded text where there is some, OCR for scanned pages, as on the Mac. */
    suspend fun toText(file: File, o: Options): File {
        val text = text(file)
        if (text.isNotBlank()) return Output.file(file, "txt", null, o).apply { writeText(text) }
        return VisionOps.ocr(file, o)
    }

    fun merge(files: List<File>, o: Options): File {
        val out = Output.unique(o.outDir, "Merged", "pdf")
        val merger = PDFMergerUtility().apply { destinationFileName = out.absolutePath; files.forEach { addSource(it) } }
        try { merger.mergeDocuments(MemoryUsageSetting.setupTempFileOnly()) } catch (e: Exception) {
            out.delete(); throw MorphError("Couldn't merge the PDFs: ${e.message}")
        }
        return out
    }

    /** One PDF per page in a "<name> pages" folder. */
    fun split(file: File, o: Options): File {
        val folder = Output.unique(o.outDir, "${file.nameWithoutExtension} pages", "").also { it.delete(); it.mkdirs() }
        open(file).use { doc ->
            Splitter().split(doc).forEachIndexed { i, page -> page.use { it.save(File(folder, "page %03d.pdf".format(i + 1))) } }
        }
        return folder
    }

    /**
     * Photos inside the PDF re-encoded as JPEG and scaled to screen size (at most 1600 px), like the Mac's
     * "optimize images for screen". Text and drawings stay vectors; images with transparency are left alone.
     */
    fun compress(file: File, o: Options): File {
        val out = Output.file(file, "pdf", "compressed", o)
        open(file).use { doc ->
            val seen = HashMap<PDImageXObject, PDImageXObject>()
            fun shrink(resources: PDResources?) {
                resources ?: return
                for (name in resources.xObjectNames.toList()) {
                    when (val x = runCatching { resources.getXObject(name) }.getOrNull()) {
                        is PDImageXObject -> {
                            if (x.softMask != null || x.isStencil || x.width * x.height < 40_000) continue
                            val replacement = seen.getOrPut(x) {
                                val bitmap = runCatching { x.image }.getOrNull() ?: return@getOrPut x
                                val longest = max(bitmap.width, bitmap.height)
                                val scaled = if (longest > 1600) Bitmap.createScaledBitmap(bitmap, bitmap.width * 1600 / longest, bitmap.height * 1600 / longest, true) else bitmap
                                JPEGFactory.createFromImage(doc, scaled, o.compression.quality / 100f)
                            }
                            if (replacement !== x) resources.put(name, replacement)
                        }
                        is PDFormXObject -> shrink(x.resources)
                        else -> {}
                    }
                }
            }
            for (page in doc.pages) shrink(page.resources)
            doc.save(out)
        }
        if (out.length() >= file.length() * 0.95) { out.delete(); throw MorphError("${file.name} is already as small as it can get without losing quality") }
        return out
    }

    /** Each page as a PNG at 2× (144 dpi), in a "<name> pages" folder. */
    fun toImages(file: File, o: Options): List<File> {
        val folder = Output.unique(o.outDir, "${file.nameWithoutExtension} pages", "").also { it.delete(); it.mkdirs() }
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { pdf ->
                return (0 until pdf.pageCount).map { i ->
                    pdf.openPage(i).use { page ->
                        val bitmap = Bitmap.createBitmap(page.width * 2, page.height * 2, Bitmap.Config.ARGB_8888)
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        ImageOps.write(bitmap, ImageFormat.PNG, 100, File(folder, "page-${i + 1}.png"))
                    }
                }
            }
        }
    }
}

// MARK: - Video & audio

object MediaOps {
    /**
     * Downscales only videos taller than the level's height; never upscales. With a size limit, picks the bitrate
     * (and a height to suit it) from the video's length so the file lands under the limit.
     */
    suspend fun compress(context: Context, file: File, o: Options): File {
        val height = videoHeight(file)
        o.targetBytes?.let { target ->
            val seconds = durationSeconds(file) ?: throw MorphError("Couldn't read how long ${file.name} is")
            // Leave room for 128 kbps audio and the container.
            val bitrate = (target * 8 / seconds * 0.9 - 128_000).toInt().coerceAtLeast(150_000)
            val maxHeight = (if (bitrate < 600_000) 480 else if (bitrate < 1_500_000) 720 else 1080).takeIf { height == null || height > it }
            val out = transform(context, file, Output.file(file, "mp4", "compressed", o), maxHeight = maxHeight, bitrate = bitrate)
            if (out.length() > target) { out.delete(); throw MorphError("Couldn't get ${file.name} under ${SizeLimit.label(target)}") }
            return out
        }
        val target = o.compression.videoHeight.takeIf { height == null || height > it }
        return transform(context, file, Output.file(file, "mp4", "compressed", o), maxHeight = target, bitrate = o.compression.videoBitrate)
    }

    private fun durationSeconds(file: File): Double? = MediaMetadataRetriever().use { r ->
        r.setDataSource(file.absolutePath)
        r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.takeIf { it > 0 }?.div(1000.0)
    }

    private fun videoHeight(file: File): Int? = MediaMetadataRetriever().use { r ->
        r.setDataSource(file.absolutePath)
        val w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
        val h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
        val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        if (rotation % 180 != 0) w else h
    }

    /** Media3 Transformer: H.264/AAC in an MP4 container (audio-only output is an M4A). */
    suspend fun transform(
        context: Context, input: File, output: File,
        removeAudio: Boolean = false, removeVideo: Boolean = false, maxHeight: Int? = null, bitrate: Int? = null,
    ): File = withContext(Dispatchers.Main) {
        output.delete()
        suspendCancellableCoroutine { cont ->
            val builder = Transformer.Builder(context).setAudioMimeType(MimeTypes.AUDIO_AAC)
            if (!removeVideo) builder.setVideoMimeType(MimeTypes.VIDEO_H264)
            if (bitrate != null) {
                builder.setEncoderFactory(
                    DefaultEncoderFactory.Builder(context)
                        .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
                        .build(),
                )
            }
            val transformer = builder.addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) = cont.resume(output)
                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    output.delete()
                    cont.resumeWithException(MorphError(exportException.message ?: "Couldn't process ${input.name}"))
                }
            }).build()
            val effects = if (maxHeight != null) Effects(emptyList(), listOf(Presentation.createForHeight(maxHeight))) else Effects.EMPTY
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input)))
                .setRemoveAudio(removeAudio)
                .setRemoveVideo(removeVideo)
                .setEffects(effects)
                .build()
            transformer.start(item, output.absolutePath)
            cont.invokeOnCancellation { transformer.cancel() }
        }
    }
}

// MARK: - Archives

object ArchiveOps {
    fun zip(files: List<File>, o: Options): File {
        val out = Output.unique(o.outDir, if (files.size == 1) files[0].nameWithoutExtension else "Archive", "zip")
        ZipOutputStream(out.outputStream().buffered()).use { zip ->
            val used = mutableSetOf<String>()
            for (file in files) {
                var name = file.name
                var i = 2
                while (!used.add(name)) name = "${file.nameWithoutExtension} ${i++}.${file.extension}"
                zip.putNextEntry(ZipEntry(name))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        return out
    }

    /**
     * Unpacks a zip, tar, tar.gz or gz into a folder named after it. Entries that would land outside the folder
     * ("../" paths) are skipped.
     */
    fun extract(file: File, o: Options): File {
        val name = file.name.lowercase()
        val base = file.name.removeSuffix(".gz").removeSuffix(".GZ").substringBeforeLast(".tar").let { if (it == file.name) file.nameWithoutExtension else it }
        val folder = Output.unique(o.outDir, base, "").also { it.delete(); it.mkdirs() }
        val root = folder.canonicalFile
        fun target(entry: String): File? = File(folder, entry).canonicalFile.takeIf { it.path.startsWith(root.path + File.separator) }
        try {
            when {
                name.endsWith(".zip") -> java.util.zip.ZipInputStream(file.inputStream().buffered()).use { zip ->
                    generateSequence { zip.nextEntry }.forEach { entry ->
                        val out = target(entry.name) ?: return@forEach
                        if (entry.isDirectory) out.mkdirs() else { out.parentFile?.mkdirs(); out.outputStream().use { zip.copyTo(it) } }
                    }
                }
                name.endsWith(".tar") || name.endsWith(".tar.gz") || name.endsWith(".tgz") -> {
                    val raw = file.inputStream().buffered()
                    val stream = if (name.endsWith(".tar")) raw else java.util.zip.GZIPInputStream(raw)
                    stream.use { untar(it, ::target) }
                }
                name.endsWith(".gz") -> java.util.zip.GZIPInputStream(file.inputStream().buffered()).use { gz ->
                    File(folder, file.name.dropLast(3)).outputStream().use { gz.copyTo(it) }
                }
                else -> throw MorphError("Android can't open .${file.extension} archives")
            }
        } catch (e: MorphError) { folder.deleteRecursively(); throw e } catch (e: Exception) {
            folder.deleteRecursively(); throw MorphError("Couldn't extract ${file.name}: ${e.message}")
        }
        return folder
    }

    /** POSIX and GNU tar: 512-byte headers, ustar prefixes and GNU long names. */
    private fun untar(input: java.io.InputStream, target: (String) -> File?) {
        val header = ByteArray(512)
        var longName: String? = null
        fun readFully(buffer: ByteArray): Boolean {
            var read = 0
            while (read < buffer.size) { val n = input.read(buffer, read, buffer.size - read); if (n < 0) return false; read += n }
            return true
        }
        fun field(offset: Int, length: Int) = String(header, offset, length, Charsets.UTF_8).substringBefore('\u0000').trim()
        while (readFully(header)) {
            if (header.all { it == 0.toByte() }) break
            val size = field(124, 12).ifEmpty { "0" }.toLong(8)
            val type = header[156].toInt().toChar()
            val prefix = if (String(header, 257, 5, Charsets.US_ASCII) == "ustar") field(345, 155) else ""
            val entry = longName ?: listOf(prefix, field(0, 100)).filter { it.isNotEmpty() }.joinToString("/")
            longName = null
            val padded = (size + 511) / 512 * 512
            when (type) {
                'L' -> { val bytes = ByteArray(padded.toInt()); readFully(bytes); longName = String(bytes, 0, size.toInt(), Charsets.UTF_8).trimEnd('\u0000'); continue }
                '5' -> target(entry)?.mkdirs()
                '0', '\u0000', '7' -> {
                    val out = target(entry)
                    if (out != null) {
                        out.parentFile?.mkdirs()
                        out.outputStream().use { s ->
                            var remaining = size
                            val buffer = ByteArray(8192)
                            while (remaining > 0) {
                                val n = input.read(buffer, 0, min(buffer.size.toLong(), remaining).toInt())
                                if (n <= 0) throw MorphError("The archive is cut short")
                                s.write(buffer, 0, n); remaining -= n
                            }
                        }
                        input.skipFully(padded - size)
                        continue
                    }
                }
            }
            input.skipFully(padded)
        }
    }

    private fun java.io.InputStream.skipFully(count: Long) {
        var left = count
        while (left > 0) { val n = skip(left); if (n <= 0) { if (read() < 0) return; left-- } else left -= n }
    }
}
