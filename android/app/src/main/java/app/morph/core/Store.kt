package app.morph.core

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import app.morph.ui.Palette
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Copies shared or picked content into private storage so actions can work on plain files. */
object Inbox {
    fun copy(context: Context, uris: List<Uri>): List<File> {
        val dir = File(context.cacheDir, "inbox/${UUID.randomUUID()}").apply { mkdirs() }
        val used = mutableSetOf<String>()
        return uris.mapNotNull { uri ->
            var name = displayName(context, uri)
            var i = 2
            while (!used.add(name)) name = "${name.substringBeforeLast('.')} ${i++}.${name.substringAfterLast('.', "")}".trimEnd('.')
            val dest = File(dir, name)
            // One unreadable file is skipped, not allowed to cancel the rest.
            runCatching { context.contentResolver.openInputStream(uri)?.use { input -> dest.outputStream().use { input.copyTo(it) } } }
                .getOrNull() ?: return@mapNotNull null
            dest
        }
    }

    /** The original file name, with an extension guessed from the MIME type if it has none. */
    private fun displayName(context: Context, uri: Uri): String {
        val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        if (name.contains('.')) return name.replace('/', '_')
        val ext = context.contentResolver.getType(uri)?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
        return if (ext != null) "$name.$ext" else name
    }

    /** Clears imports and work files from earlier sessions. Recent ones may belong to a job still running elsewhere
     *  (the app and the share sheet each have their own), so only folders over an hour old go. */
    fun clean(context: Context) {
        val cutoff = System.currentTimeMillis() - 3_600_000
        for (name in listOf("inbox", "work")) {
            File(context.cacheDir, name).listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.deleteRecursively() }
        }
    }
}

/** A result published where the phone looks for it: photos and videos in the gallery (Pictures/Morph, Movies/Morph),
 *  everything else in Downloads/Morph. */
data class Published(val uri: Uri, val name: String, val mime: String, val size: Long) {
    val inGallery: Boolean get() = uri.path.orEmpty().let { "/images/" in it || "/video/" in it }
}

object Publisher {
    const val FOLDER = "Download/Morph"

    fun mime(name: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"

    /** Photo formats every gallery shows; SVG, TIFF and the like stay with the documents in Downloads. */
    private val galleryImages = setOf("image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/gif", "image/avif")

    /** Moves [file] (written under [root]) into the gallery or Downloads/Morph, keeping any subfolder. */
    fun publish(context: Context, file: File, root: File): Published {
        val sub = file.parentFile?.relativeTo(root)?.path.orEmpty()
        val mime = mime(file.name)
        val resolver = context.contentResolver
        fun insert(collection: Uri, folder: String): Uri? = resolver.insert(collection, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (sub.isEmpty()) folder else "$folder/$sub")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        })
        val gallery = when {
            mime in galleryImages -> runCatching { insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "Pictures/Morph") }.getOrNull()
            mime.startsWith("video/") -> runCatching { insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "Movies/Morph") }.getOrNull()
            else -> null
        }
        val uri = gallery ?: insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, FOLDER) ?: throw MorphError("Couldn't save ${file.name}")
        try {
            val stream = resolver.openOutputStream(uri) ?: throw MorphError("Couldn't save ${file.name}")
            stream.use { out -> file.inputStream().use { it.copyTo(out) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            // Don't leave a half-written, hidden entry in Downloads; the result stays in cache for the error.
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
        val size = file.length()
        file.delete()
        // MediaStore may have renamed it ("a (1).jpg") to avoid a clash.
        val saved = resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: file.name
        return Published(uri, saved, mime, size)
    }

    fun exists(context: Context, uri: Uri): Boolean =
        runCatching { context.contentResolver.query(uri, arrayOf(MediaStore.Downloads._ID), null, null, null)?.use { it.count > 0 } }
            .getOrNull() == true
}

data class HistoryEntry(
    val id: String,
    val date: Long,
    val title: String,
    val inputCount: Int,
    val outputs: List<Published>,
    val failures: List<String>,
    val deleted: Boolean = false,
)

/** Every job is logged; deleting a job removes its published results (originals are never touched). */
object History {
    private fun file(context: Context) = File(context.filesDir, "history.json")

    @Synchronized
    fun load(context: Context): List<HistoryEntry> {
        val f = file(context)
        if (!f.exists()) return emptyList()
        return runCatching {
            val array = JSONArray(f.readText())
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                val outs = o.getJSONArray("outputs")
                val fails = o.getJSONArray("failures")
                HistoryEntry(
                    id = o.getString("id"),
                    date = o.getLong("date"),
                    title = o.getString("title"),
                    inputCount = o.getInt("inputCount"),
                    outputs = (0 until outs.length()).map { j ->
                        val p = outs.getJSONObject(j)
                        Published(Uri.parse(p.getString("uri")), p.getString("name"), p.getString("mime"), p.getLong("size"))
                    },
                    failures = (0 until fails.length()).map { fails.getString(it) },
                    deleted = o.optBoolean("deleted"),
                )
            }
        }.getOrDefault(emptyList())
    }

    @Synchronized
    private fun store(context: Context, entries: List<HistoryEntry>) {
        val array = JSONArray()
        entries.takeLast(200).forEach { e ->
            array.put(JSONObject().apply {
                put("id", e.id); put("date", e.date); put("title", e.title); put("inputCount", e.inputCount)
                put("deleted", e.deleted)
                put("outputs", JSONArray().apply {
                    e.outputs.forEach { p -> put(JSONObject().put("uri", p.uri.toString()).put("name", p.name).put("mime", p.mime).put("size", p.size)) }
                })
                put("failures", JSONArray(e.failures))
            })
        }
        file(context).writeText(array.toString())
    }

    @Synchronized
    fun append(context: Context, entry: HistoryEntry) = store(context, load(context) + entry)

    @Synchronized
    fun delete(context: Context, id: String) {
        val all = load(context).map { e ->
            if (e.id != id) return@map e
            e.outputs.forEach { runCatching { context.contentResolver.delete(it.uri, null, null) } }
            e.copy(deleted = true)
        }
        store(context, all)
    }
}

class Prefs(context: Context) {
    private val prefs = context.getSharedPreferences("morph", Context.MODE_PRIVATE)

    var hasSeenWelcome: Boolean
        get() = prefs.getBoolean("hasSeenWelcome", false)
        set(value) = prefs.edit().putBoolean("hasSeenWelcome", value).apply()

    var haptics: Boolean
        get() = prefs.getBoolean("haptics", true)
        set(value) = prefs.edit().putBoolean("haptics", value).apply()

    var compression: Compression
        get() = runCatching { Compression.valueOf(prefs.getString("compression", null) ?: "") }.getOrDefault(Compression.BALANCED)
        set(value) = prefs.edit().putString("compression", value.name).apply()

    /** Exact size Resize makes for forms, as "600x600"; empty keeps the usual fit. */
    var photoSize: String
        get() = prefs.getString("photoSize", "") ?: ""
        set(value) = prefs.edit().putString("photoSize", value).apply()

    /** Printed with the date under the photo at that size; empty prints nothing. */
    var photoCaption: String
        get() = prefs.getString("photoCaption", "") ?: ""
        set(value) = prefs.edit().putString("photoCaption", value).apply()

    /** Bytes Compress must fit under; 0 is no limit. */
    var sizeLimit: Int
        get() = prefs.getInt("sizeLimit", 0)
        set(value) = prefs.edit().putInt("sizeLimit", value).apply()

    var palette: Palette
        get() = runCatching { Palette.valueOf(prefs.getString("palette", null) ?: "") }.getOrDefault(Palette.TEAL)
        set(value) = prefs.edit().putString("palette", value.name).apply()
}
