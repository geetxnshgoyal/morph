package app.morph.core

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Frames out of videos (GIFs and snapshots) and metadata-free copies, alongside MediaOps' transcoding. */
object VideoOps {
    private fun <T> retriever(file: File, body: (MediaMetadataRetriever) -> T): T = MediaMetadataRetriever().use { r ->
        r.setDataSource(file.absolutePath)
        body(r)
    }

    private fun MediaMetadataRetriever.durationMs() =
        extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.takeIf { it > 0 }
            ?: throw MorphError("Video has no duration or cannot be read")

    /** Up to 30 seconds at 12 frames a second, 480 px on the longest side, looping: the Mac's GIF settings. */
    fun toGif(file: File, o: Options): File = retriever(file) { r ->
        val seconds = min(r.durationMs() / 1000.0, 30.0)
        val fps = 12
        val count = max((seconds * fps).toInt(), 1)
        val first = frame(r, 0) ?: throw MorphError("Couldn't read the frames of ${file.name}")
        val scale = min(480.0 / max(first.width, first.height), 1.0)
        val w = (first.width * scale).roundToInt().coerceAtLeast(1); val h = (first.height * scale).roundToInt().coerceAtLeast(1)
        val out = Output.file(file, "gif", null, o)
        out.outputStream().buffered().use { s ->
            val gif = ImageFormats.GifWriter(s, w, h, 1000 / fps)
            for (i in 0 until count) {
                val bitmap = frame(r, i * 1_000_000L / fps) ?: continue
                gif.add(Bitmap.createScaledBitmap(bitmap, w, h, true))
                bitmap.recycle()
            }
            gif.finish()
        }
        out
    }

    private fun frame(r: MediaMetadataRetriever, us: Long): Bitmap? = r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST)

    /** Six frames spread through the video, as JPGs in a "<name> frames" folder. */
    fun snapshots(file: File, o: Options, count: Int = 6): List<File> = retriever(file) { r ->
        val seconds = r.durationMs() / 1000.0
        val folder = Output.unique(o.outDir, "${file.nameWithoutExtension} frames", "").also { it.delete(); it.mkdirs() }
        (0 until count).mapNotNull { i ->
            val t = seconds * (i + 0.5) / count
            val bitmap = frame(r, (t * 1_000_000).toLong()) ?: return@mapNotNull null
            ImageOps.write(bitmap, ImageFormat.JPG, 90, File(folder, "frame %02d (%.1fs).jpg".format(i + 1, t)))
        }.ifEmpty { throw MorphError("Couldn't read the frames of ${file.name}") }
    }

    /**
     * Copies every audio and video track into a fresh MP4 (or M4A) without re-encoding, which leaves behind the
     * location, camera and other metadata. Formats an MP4 can't hold are re-encoded to AAC instead.
     */
    suspend fun stripMetadata(context: android.content.Context, file: File, o: Options): File {
        val video = FileKind.of(file) == FileKind.VIDEO
        val out = Output.file(file, if (video) "mp4" else "m4a", "clean", o)
        try {
            remux(file, out)
        } catch (_: Exception) {
            out.delete()
            if (!video) return AudioOps.withPcm(file, o) { pcm -> AudioOps.encode(pcm, AudioOps.Codec.AAC, Output.file(file, "m4a", "clean", o)) }
            return MediaOps.transform(context, file, Output.file(file, "mp4", "clean", o))
        }
        return out
    }

    private fun remux(input: File, out: File) {
        val extractor = MediaExtractor()
        out.delete()
        val muxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            extractor.setDataSource(input.absolutePath)
            val tracks = mutableMapOf<Int, Int>()
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("audio/") && !mime.startsWith("video/")) continue
                tracks[i] = muxer.addTrack(format)
                extractor.selectTrack(i)
            }
            if (tracks.isEmpty()) throw MorphError("${input.name} has no audio or video")
            // Rotation is how the picture should be shown, not private data, so it's kept.
            retriever(input) { r -> r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() }
                ?.let { muxer.setOrientationHint(it) }
            muxer.start()
            val buffer = ByteBuffer.allocate(4 shl 20)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.set(0, size, extractor.sampleTime, if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                muxer.writeSampleData(tracks.getValue(extractor.sampleTrackIndex), buffer, info)
                extractor.advance()
            }
            muxer.stop()
        } finally {
            extractor.release()
            runCatching { muxer.release() }
        }
    }
}
