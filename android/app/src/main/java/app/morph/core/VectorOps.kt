package app.morph.core

import android.graphics.Bitmap
import android.graphics.Canvas
import com.caverock.androidsvg.RenderOptions
import com.caverock.androidsvg.SVG
import com.caverock.androidsvg.SVGParseException
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * SVG in both directions. SVGs are drawn by AndroidSVG, which never goes online (it has no file resolver set, so
 * only images embedded as data: URLs are drawn). Images become SVGs by tracing them into shapes (see [Tracer]).
 */
object VectorOps {
    /** Icons are often drawn at 16-24 px, so SVGs render at least this big on the long side unless a size is set. */
    private const val MINIMUM_PIXEL = 1024
    private const val MAXIMUM_PIXEL = 8192

    fun isSvg(file: File) = file.extension.equals("svg", ignoreCase = true)

    /** A parsed SVG and its own size: its width and height, or else its viewBox. */
    class Document(private val svg: SVG, val width: Double, val height: Double) {
        /** Draws the SVG filling `width` × `height` of [canvas]. */
        fun draw(canvas: Canvas, width: Int, height: Int) {
            svg.renderToCanvas(canvas, RenderOptions().viewPort(0f, 0f, width.toFloat(), height.toFloat()))
        }
    }

    fun document(file: File): Document {
        val svg = try { file.inputStream().use { SVG.getFromInputStream(it) } } catch (e: SVGParseException) {
            throw MorphError("${file.name} isn't a readable SVG")
        }
        val box = svg.documentViewBox
        var w = svg.documentWidth.toDouble(); var h = svg.documentHeight.toDouble()
        if ((w <= 0 || h <= 0) && box != null) { w = box.width().toDouble(); h = box.height().toDouble() }
        if (w <= 0 || h <= 0) throw MorphError("${file.name} has no size")
        // Scale the drawing to whatever viewport it's rendered into.
        if (box == null) svg.setDocumentViewBox(0f, 0f, w.toFloat(), h.toFloat())
        return Document(svg, w, h)
    }

    /**
     * Renders on a transparent background, at the SVG's own size raised to [MINIMUM_PIXEL] on the long side, or
     * exactly [maxPixel]: a vector scales up as cleanly as down.
     */
    fun render(file: File, maxPixel: Int? = null): Bitmap {
        val doc = document(file)
        val longest = max(doc.width, doc.height)
        val target = maxPixel?.toDouble() ?: min(max(longest, MINIMUM_PIXEL.toDouble()), MAXIMUM_PIXEL.toDouble())
        val scale = target / longest
        val w = (doc.width * scale).roundToInt().coerceAtLeast(1); val h = (doc.height * scale).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        doc.draw(Canvas(bitmap), w, h)
        return bitmap
    }

    /**
     * Traces an image into an SVG of filled shapes. The palette size comes from [Options.colors], or else from the
     * compression level, which also sets how closely outlines follow the pixels.
     */
    fun trace(file: File, o: Options): File {
        val img = ImageOps.decode(file)
        val settings = Tracer.Settings.of(o.compression)
        o.colors?.let { settings.colors = it.coerceIn(2, 64) }
        // Big images are traced at about workPixel squared pixels; small ones are enlarged to 512 on the long side,
        // so curves come out smooth. Enlarging anything bigger only stretches pixel noise into ragged edges.
        val fit = settings.workPixel / sqrt(img.width.toDouble() * img.height)
        val scale = if (fit < 1) fit else max(1.0, min(fit, 512.0 / max(img.width, img.height)))
        val w = (img.width * scale).roundToInt().coerceAtLeast(1); val h = (img.height * scale).roundToInt().coerceAtLeast(1)
        val image = pixels(Bitmap.createScaledBitmap(img, w, h, true))
        val sample = if (scale <= 1) image else pixels(img)
        val svg = Tracer(image, sample, settings).svg(img.width, img.height)
        return Output.file(file, "svg", null, o).apply { writeText(svg) }
    }

    /** Straight (not premultiplied) RGBA bytes. */
    private fun pixels(bitmap: Bitmap): Tracer.Pixels {
        val argb = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(argb, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val rgba = ByteArray(argb.size * 4)
        for (i in argb.indices) {
            val c = argb[i]
            rgba[i * 4] = (c shr 16).toByte(); rgba[i * 4 + 1] = (c shr 8).toByte(); rgba[i * 4 + 2] = c.toByte(); rgba[i * 4 + 3] = (c ushr 24).toByte()
        }
        return Tracer.Pixels(bitmap.width, bitmap.height, rgba)
    }
}
