package app.morph.core

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.tasks.await
import java.io.File
import kotlin.math.max

/** On-device ML Kit models (bundled with the app, nothing downloaded): text, faces and codes. */
object VisionOps {
    /** The image itself, or a PDF's pages rendered at 2×. */
    private fun images(file: File): List<Bitmap> =
        if (FileKind.of(file) == FileKind.PDF) PdfOps.renderPages(file, 2f) else listOf(ImageOps.decode(file, 3000))

    private suspend fun recognize(bitmap: Bitmap): Text {
        val client = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try { return client.process(InputImage.fromBitmap(bitmap, 0)).await() } finally { client.close() }
    }

    /** An image's text, or a PDF's: its own text when it has some, otherwise what OCR reads off its pages. */
    suspend fun ocr(file: File, o: Options): File {
        val text = if (FileKind.of(file) == FileKind.PDF) PdfOps.text(file).ifBlank { null } else null
        val result = text ?: images(file).map { recognize(it).text }.joinToString("\n\n").trim()
        if (result.isBlank()) throw MorphError("No text found in ${file.name}")
        return Output.file(file, "txt", null, o).apply { writeText(result) }
    }

    suspend fun readCodes(file: File, o: Options): File {
        val scanner = BarcodeScanning.getClient()
        val codes = linkedSetOf<String>()
        try {
            for (bitmap in images(file)) for (code in scanner.process(InputImage.fromBitmap(bitmap, 0)).await()) code.rawValue?.let { codes += it }
        } finally { scanner.close() }
        if (codes.isEmpty()) throw MorphError("No QR codes or barcodes found in ${file.name}")
        return Output.file(file, "txt", "codes", o).apply { writeText(codes.joinToString("\n")) }
    }

    /** Patterns treated as personal info in screenshots, the same as the Mac's. */
    private val sensitive = listOf(
        "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",      // email
        "\\+?\\d[\\d\\s().-]{7,}\\d",                   // phone
        "\\b(?:\\d[ -]?){13,19}\\b",                    // card number
        "\\b[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\b",          // IBAN
        "\\b\\d{3}-\\d{2}-\\d{4}\\b",                   // SSN
        "\\b\\d{4}\\s?\\d{4}\\s?\\d{4}\\b",             // Aadhaar
        "\\b[A-Z]{5}\\d{4}[A-Z]\\b",                    // PAN
        "(?:\\d{1,3}\\.){3}\\d{1,3}",                   // IPv4
    ).map { Regex(it, RegexOption.IGNORE_CASE) }

    suspend fun redactFaces(file: File, o: Options): File = redact(file, o, padding = 0.2f, pixelate = true, none = "No faces found in ${file.name}") { bitmap ->
        val detector = FaceDetection.getClient(FaceDetectorOptions.Builder().setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE).setMinFaceSize(0.05f).build())
        try { detector.process(InputImage.fromBitmap(bitmap, 0)).await().map { it.boundingBox } } finally { detector.close() }
    }

    /** Each matching run of text, boxed by the words it covers. */
    suspend fun redactPersonalInfo(file: File, o: Options): File =
        redact(file, o, padding = 0.08f, pixelate = false, none = "No emails, phone or card numbers found in ${file.name}") { bitmap ->
            val rects = mutableListOf<Rect>()
            for (line in recognize(bitmap).textBlocks.flatMap { it.lines }) {
                // Where each word starts in the line's text, so a match maps back to the words it covers.
                val words = line.elements
                var cursor = 0
                val starts = words.map { w -> line.text.indexOf(w.text, cursor).also { if (it >= 0) cursor = it + w.text.length } }
                for (regex in sensitive) for (match in regex.findAll(line.text)) {
                    val covered = words.indices.filter { i ->
                        val s = starts[i]; s >= 0 && s < match.range.last + 1 && s + words[i].text.length > match.range.first
                    }.mapNotNull { words[it].boundingBox }
                    if (covered.isNotEmpty()) rects += Rect(covered.minOf { it.left }, covered.minOf { it.top }, covered.maxOf { it.right }, covered.maxOf { it.bottom })
                    else line.boundingBox?.let { rects += it }
                }
            }
            rects
        }

    private suspend fun redact(
        file: File, o: Options, padding: Float, pixelate: Boolean, none: String, detect: suspend (Bitmap) -> List<Rect>,
    ): File {
        val source = ImageOps.decode(file)
        val image = source.copy(Bitmap.Config.ARGB_8888, true)
        val rects = detect(image)
        if (rects.isEmpty()) throw MorphError(none)
        val canvas = Canvas(image)
        for (r in rects) {
            val dx = (r.width() * padding).toInt(); val dy = (r.height() * padding).toInt()
            val box = Rect(r.left - dx, r.top - dy, r.right + dx, r.bottom + dy)
            if (!box.intersect(0, 0, image.width, image.height) || box.isEmpty) continue
            if (pixelate) {
                // Average down to a coarse grid (irreversible), then scale back up with hard edges.
                val piece = Bitmap.createBitmap(image, box.left, box.top, box.width(), box.height())
                val tiny = Bitmap.createScaledBitmap(piece, 8, max(8 * box.height() / box.width(), 1), true)
                canvas.drawBitmap(tiny, null, box, Paint())
            } else {
                canvas.drawRect(box, Paint().apply { color = Color.BLACK })
            }
        }
        // Metadata is dropped on purpose: a redacted photo shouldn't say where it was taken.
        val format = ImageOps.sameFormat(file)
        return ImageOps.write(image, format, 92, Output.file(file, format.ext, "redacted", o))
    }
}
