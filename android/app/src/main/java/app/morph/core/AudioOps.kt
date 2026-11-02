package app.morph.core

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Audio through Android's own codecs: any track the phone can play is decoded to 16-bit PCM, then written as WAV
 * or AIFF, or encoded to AAC, FLAC or Opus. Loudness and silence work on that PCM, as ffmpeg's filters do on the Mac.
 */
object AudioOps {
    class Pcm(val file: File, val sampleRate: Int, val channels: Int) {
        val frames get() = file.length() / (2 * channels)
    }

    private const val TIMEOUT_US = 10_000L

    /** The first audio track, decoded to interleaved little-endian 16-bit samples in a temporary file. */
    fun decode(input: File, temp: File): Pcm {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw MorphError("${input.name} has no sound")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var float = false
            temp.outputStream().buffered(1 shl 16).use { out ->
                codec.configure(format, null, null, 0)
                codec.start()
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                var scratch = ByteArray(0)
                while (!outputDone) {
                    if (!inputDone) {
                        val index = codec.dequeueInputBuffer(TIMEOUT_US)
                        if (index >= 0) {
                            val size = extractor.readSampleData(codec.getInputBuffer(index)!!, 0)
                            if (size < 0) {
                                codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true
                            } else {
                                codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0); extractor.advance()
                            }
                        }
                    }
                    when (val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> codec.outputFormat.let {
                            sampleRate = it.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            channels = it.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            float = it.containsKey(MediaFormat.KEY_PCM_ENCODING) && it.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                        }
                        in 0..Int.MAX_VALUE -> {
                            val buffer = codec.getOutputBuffer(index)!!
                            buffer.position(info.offset); buffer.limit(info.offset + info.size)
                            if (float) {
                                val floats = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
                                val bytes = ByteBuffer.allocate(floats.remaining() * 2).order(ByteOrder.LITTLE_ENDIAN)
                                while (floats.hasRemaining()) bytes.putShort((floats.get().coerceIn(-1f, 1f) * 32767).toInt().toShort())
                                out.write(bytes.array())
                            } else {
                                if (scratch.size < info.size) scratch = ByteArray(info.size)
                                buffer.get(scratch, 0, info.size)
                                out.write(scratch, 0, info.size)
                            }
                            codec.releaseOutputBuffer(index, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                        }
                    }
                }
                codec.stop()
                codec.release()
            }
            return Pcm(temp, sampleRate, channels)
        } catch (e: MorphError) { throw e } catch (e: Exception) {
            throw MorphError("Couldn't decode the sound in ${input.name}: ${e.message}")
        } finally {
            extractor.release()
        }
    }

    fun writeWav(pcm: Pcm, out: File): File {
        val dataSize = pcm.file.length()
        if (dataSize > 0xFFFFFFFFL - 36) throw MorphError("Too long for a WAV file")
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray()); putInt((36 + dataSize).toInt()); put("WAVE".toByteArray())
            put("fmt ".toByteArray()); putInt(16); putShort(1); putShort(pcm.channels.toShort()); putInt(pcm.sampleRate)
            putInt(pcm.sampleRate * pcm.channels * 2); putShort((pcm.channels * 2).toShort()); putShort(16)
            put("data".toByteArray()); putInt(dataSize.toInt())
        }
        out.outputStream().buffered().use { s -> s.write(header.array()); pcm.file.inputStream().use { it.copyTo(s) } }
        return out
    }

    /** AIFF wants big-endian samples and its sample rate as an 80-bit float. */
    fun writeAiff(pcm: Pcm, out: File): File {
        val dataSize = pcm.file.length()
        val header = ByteBuffer.allocate(54).order(ByteOrder.BIG_ENDIAN).apply {
            put("FORM".toByteArray()); putInt((46 + dataSize).toInt()); put("AIFF".toByteArray())
            put("COMM".toByteArray()); putInt(18); putShort(pcm.channels.toShort()); putInt(pcm.frames.toInt()); putShort(16)
            put(extended(pcm.sampleRate.toDouble()))
            put("SSND".toByteArray()); putInt((8 + dataSize).toInt()); putInt(0); putInt(0)
        }
        out.outputStream().buffered().use { s ->
            s.write(header.array())
            pcm.file.inputStream().buffered().use { input ->
                val chunk = ByteArray(1 shl 16)
                while (true) {
                    val n = input.read(chunk).takeIf { it > 0 } ?: break
                    val even = n - n % 2
                    for (i in 0 until even step 2) { val t = chunk[i]; chunk[i] = chunk[i + 1]; chunk[i + 1] = t }
                    s.write(chunk, 0, even)
                }
            }
        }
        return out
    }

    private fun extended(value: Double): ByteArray {
        val bytes = ByteArray(10)
        if (value == 0.0) return bytes
        var exponent = 16383 + 31
        var mantissa = value
        while (mantissa < 2.0.pow(31)) { mantissa *= 2; exponent-- }
        while (mantissa >= 2.0.pow(32)) { mantissa /= 2; exponent++ }
        val hi = mantissa.toLong()
        bytes[0] = (exponent shr 8).toByte(); bytes[1] = exponent.toByte()
        for (i in 0 until 4) bytes[2 + i] = (hi shr (24 - 8 * i)).toByte()
        return bytes
    }

    enum class Codec(val mime: String, val ext: String) {
        AAC(MediaFormat.MIMETYPE_AUDIO_AAC, "m4a"), FLAC(MediaFormat.MIMETYPE_AUDIO_FLAC, "flac"),
        OPUS(MediaFormat.MIMETYPE_AUDIO_OPUS, "opus"), OGG(MediaFormat.MIMETYPE_AUDIO_OPUS, "ogg");

        val isAvailable: Boolean by lazy {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, true) } }
        }
    }

    /**
     * Encodes PCM with the phone's encoder: AAC into an M4A, Opus into an Ogg file, FLAC as a bare FLAC stream (the
     * encoder's first buffer is the "fLaC" header and stream info, followed by frames).
     */
    fun encode(pcm: Pcm, codec: Codec, out: File, bitrate: Int = 192_000): File {
        // Opus only runs at 48 kHz and lower rates it can resample from; Android's encoder takes these.
        val rate = if (codec == Codec.OPUS || codec == Codec.OGG) opusRate(pcm.sampleRate) else pcm.sampleRate
        val source = if (rate != pcm.sampleRate) resample(pcm, rate) else pcm
        val format = MediaFormat.createAudioFormat(codec.mime, rate, source.channels).apply {
            if (codec != Codec.FLAC) setInteger(MediaFormat.KEY_BIT_RATE, if (codec == Codec.AAC) bitrate else min(bitrate, 128_000) * source.channels / 2)
            else setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 5)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 1 shl 16)
        }
        val encoder = try { MediaCodec.createEncoderByType(codec.mime) } catch (e: Exception) {
            throw MorphError("This phone can't encode ${codec.ext.uppercase()}")
        }
        out.delete()
        val muxer = when (codec) {
            Codec.AAC -> MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            Codec.OPUS, Codec.OGG -> MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG)
            Codec.FLAC -> null
        }
        val raw = if (muxer == null) out.outputStream().buffered() else null
        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            val info = MediaCodec.BufferInfo()
            var track = -1
            var inputDone = false
            var framesIn = 0L
            val frameBytes = 2 * source.channels
            source.file.inputStream().buffered(1 shl 16).use { input ->
                var outputDone = false
                val chunk = ByteArray(8192 - 8192 % frameBytes)
                while (!outputDone) {
                    if (!inputDone) {
                        val index = encoder.dequeueInputBuffer(TIMEOUT_US)
                        if (index >= 0) {
                            val buffer = encoder.getInputBuffer(index)!!
                            val n = input.read(chunk, 0, min(chunk.size, buffer.capacity() - buffer.capacity() % frameBytes))
                            val time = framesIn * 1_000_000 / rate
                            if (n <= 0) {
                                encoder.queueInputBuffer(index, 0, 0, time, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true
                            } else {
                                buffer.put(chunk, 0, n)
                                encoder.queueInputBuffer(index, 0, n, time, 0)
                                framesIn += n / frameBytes
                            }
                        }
                    }
                    when (val index = encoder.dequeueOutputBuffer(info, TIMEOUT_US)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> if (muxer != null) { track = muxer.addTrack(encoder.outputFormat); muxer.start() }
                        in 0..Int.MAX_VALUE -> {
                            val buffer = encoder.getOutputBuffer(index)!!
                            val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (info.size > 0) {
                                buffer.position(info.offset); buffer.limit(info.offset + info.size)
                                if (muxer != null) { if (!isConfig) muxer.writeSampleData(track, buffer, info) }
                                else ByteArray(info.size).also { buffer.get(it); raw!!.write(it) }
                            }
                            encoder.releaseOutputBuffer(index, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                        }
                    }
                }
            }
            encoder.stop()
        } catch (e: MorphError) { out.delete(); throw e } catch (e: Exception) {
            out.delete(); throw MorphError("Couldn't encode ${codec.ext.uppercase()}: ${e.message}")
        } finally {
            encoder.release()
            runCatching { muxer?.stop() }
            muxer?.release()
            raw?.close()
            if (source !== pcm) source.file.delete()
        }
        return out
    }

    private fun opusRate(rate: Int) = listOf(8000, 12000, 16000, 24000, 48000).firstOrNull { it >= rate } ?: 48000

    /** Linear resampling, enough for moving 44.1 kHz audio onto Opus's 48 kHz clock. */
    private fun resample(pcm: Pcm, rate: Int): Pcm {
        val out = File(pcm.file.path + ".resampled")
        val ch = pcm.channels
        val ratio = pcm.sampleRate.toDouble() / rate
        RandomAccessFile(pcm.file, "r").use { input ->
            val frames = pcm.frames
            out.outputStream().buffered(1 shl 16).use { s ->
                val windowFrames = 1 shl 14
                var windowStart = -1L
                var window = ShortArray(0)
                fun sample(frame: Long, c: Int): Int {
                    val f = frame.coerceIn(0, frames - 1)
                    if (f < windowStart || f >= windowStart + window.size / ch) {
                        windowStart = f
                        val count = min(windowFrames.toLong(), frames - f).toInt()
                        val bytes = ByteArray(count * ch * 2)
                        input.seek(f * ch * 2); input.readFully(bytes)
                        window = ShortArray(count * ch).also { ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(it) }
                    }
                    return window[((f - windowStart) * ch + c).toInt()].toInt()
                }
                val total = (frames / ratio).toLong()
                val bytes = ByteBuffer.allocate(ch * 2).order(ByteOrder.LITTLE_ENDIAN)
                for (i in 0 until total) {
                    val position = i * ratio
                    val f = position.toLong(); val t = position - f
                    bytes.clear()
                    for (c in 0 until ch) bytes.putShort((sample(f, c) * (1 - t) + sample(f + 1, c) * t).toInt().toShort())
                    s.write(bytes.array())
                }
            }
        }
        return Pcm(out, rate, ch)
    }

    /** Runs [body] over the samples in place, a block at a time. */
    private fun transform(pcm: Pcm, body: (ShortArray, Int) -> Unit) {
        RandomAccessFile(pcm.file, "rw").use { file ->
            val bytes = ByteArray(1 shl 16)
            var position = 0L
            while (true) {
                file.seek(position)
                val n = file.read(bytes).takeIf { it > 0 } ?: break
                val samples = ShortArray(n / 2)
                ByteBuffer.wrap(bytes, 0, n).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples)
                body(samples, samples.size)
                ByteBuffer.wrap(bytes, 0, n).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(samples)
                file.seek(position); file.write(bytes, 0, n)
                position += n
            }
        }
    }

    private fun scan(pcm: Pcm, body: (ShortArray, Int) -> Unit) {
        pcm.file.inputStream().buffered(1 shl 16).use { input ->
            val bytes = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(bytes).takeIf { it > 1 } ?: break
                val even = n - n % 2
                val samples = ShortArray(even / 2)
                ByteBuffer.wrap(bytes, 0, even).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples)
                body(samples, samples.size)
            }
        }
    }

    /**
     * Gain towards −16 LUFS, the level ffmpeg's loudnorm aims for on the Mac. Loudness is estimated from the RMS of
     * the louder half of the audio, so quiet gaps don't count; the gain is held back so peaks stay under −1.5 dBFS.
     */
    fun normalize(pcm: Pcm) {
        val blockSize = pcm.sampleRate / 10 * pcm.channels
        val blocks = mutableListOf<Double>()
        var sum = 0.0; var count = 0; var peak = 0
        scan(pcm) { samples, n ->
            for (i in 0 until n) {
                val s = samples[i].toInt()
                peak = max(peak, abs(s))
                sum += s.toDouble() * s; count++
                if (count == blockSize) { blocks += sum / count; sum = 0.0; count = 0 }
            }
        }
        if (count > 0) blocks += sum / count
        if (peak == 0) throw MorphError("The audio is silent")
        val loud = blocks.sortedDescending().take(max(blocks.size / 2, 1))
        val rms = sqrt(loud.average()) / 32768
        val currentDb = 20 * log10(rms) + 3 // RMS of a sine reads 3 dB under its loudness
        val wanted = 10.0.pow((-16 - currentDb) / 20)
        val ceiling = 10.0.pow(-1.5 / 20) * 32767 / peak
        val gain = min(wanted, ceiling)
        transform(pcm) { samples, n -> for (i in 0 until n) samples[i] = (samples[i] * gain).toInt().coerceIn(-32768, 32767).toShort() }
    }

    /** Silence under −50 dBFS at the start and end is cut, keeping a tenth of a second, as on the Mac. */
    fun trimSilence(pcm: Pcm, out: File): Pcm {
        val threshold = (32768 * 10.0.pow(-50 / 20.0)).toInt()
        val ch = pcm.channels
        var first = -1L; var last = -1L; var frame = 0L
        scan(pcm) { samples, n ->
            var i = 0
            while (i + ch <= n) {
                var loud = false
                for (c in 0 until ch) if (abs(samples[i + c].toInt()) > threshold) loud = true
                if (loud) { if (first < 0) first = frame; last = frame }
                frame++; i += ch
            }
        }
        if (first < 0) throw MorphError("The audio is silent")
        val keep = pcm.sampleRate / 10L
        val start = max(first - keep, 0); val end = min(last + keep, pcm.frames - 1)
        if (start == 0L && end == pcm.frames - 1) throw MorphError("There's no silence to trim")
        RandomAccessFile(pcm.file, "r").use { input ->
            out.outputStream().buffered(1 shl 16).use { s ->
                input.seek(start * ch * 2)
                var remaining = (end - start + 1) * ch * 2
                val bytes = ByteArray(1 shl 16)
                while (remaining > 0) {
                    val n = input.read(bytes, 0, min(bytes.size.toLong(), remaining).toInt()).takeIf { it > 0 } ?: break
                    s.write(bytes, 0, n); remaining -= n
                }
            }
        }
        return Pcm(out, pcm.sampleRate, ch)
    }

    /** Decodes [input] into the output folder's scratch space, runs [body], and always cleans up the PCM. */
    inline fun <T> withPcm(input: File, o: Options, body: (Pcm) -> T): T {
        val temp = File.createTempFile("morph", ".pcm", o.outDir.parentFile ?: o.outDir)
        try { return body(decode(input, temp)) } finally { temp.delete() }
    }

    /** WAV, AIFF, FLAC, Opus or Ogg from any audio, or the soundtrack of a video. */
    fun convert(input: File, ext: String, o: Options): File = withPcm(input, o) { pcm ->
        val out = Output.file(input, ext, null, o)
        when (ext) {
            "wav" -> writeWav(pcm, out)
            "aiff" -> writeAiff(pcm, out)
            "flac" -> encode(pcm, Codec.FLAC, out)
            "opus" -> encode(pcm, Codec.OPUS, out)
            "ogg" -> encode(pcm, Codec.OGG, out)
            else -> throw MorphError("Can't write .$ext audio")
        }
    }

    /** The same format for lossless sources, otherwise AAC in an M4A. */
    private fun write(pcm: Pcm, input: File, suffix: String, o: Options): File {
        val ext = input.extension.lowercase()
        return when (ext) {
            "wav" -> writeWav(pcm, Output.file(input, "wav", suffix, o))
            "aiff", "aif" -> writeAiff(pcm, Output.file(input, "aiff", suffix, o))
            "flac" -> encode(pcm, Codec.FLAC, Output.file(input, "flac", suffix, o))
            "opus", "ogg" -> encode(pcm, if (ext == "ogg") Codec.OGG else Codec.OPUS, Output.file(input, ext, suffix, o))
            else -> encode(pcm, Codec.AAC, Output.file(input, "m4a", suffix, o))
        }
    }

    fun normalize(input: File, o: Options): File = withPcm(input, o) { pcm -> normalize(pcm); write(pcm, input, "normalized", o) }

    fun trimSilence(input: File, o: Options): File = withPcm(input, o) { pcm ->
        val trimmed = trimSilence(pcm, File(pcm.file.path + ".trimmed"))
        try { write(trimmed, input, "trimmed", o) } finally { trimmed.file.delete() }
    }
}
