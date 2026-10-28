package app.morph

import app.morph.ui.Palette
import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.morph.core.Action
import app.morph.core.Compression
import app.morph.core.FileKind
import app.morph.core.Group
import app.morph.core.History
import app.morph.core.PixelSize
import app.morph.core.HistoryEntry
import app.morph.core.Inbox
import app.morph.core.Library
import app.morph.core.Options
import app.morph.core.Prefs
import app.morph.core.Published
import app.morph.core.Publisher
import app.morph.core.Runner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

sealed interface Phase {
    data object Choosing : Phase
    data class Running(val action: Action, val done: Int, val total: Int) : Phase
    data class Finished(val action: Action, val outputs: List<Published>, val failures: List<String>) : Phase
}

/** One trip through the actions sheet: the files, the offered actions, and where the run is at. */
class Job(val files: List<File>) {
    val actions = Library.actionsFor(files)
    val groups = Group.entries.filter { g -> actions.any { it.group == g } }
    var group by mutableStateOf(if (actions.any { it.group == Group.CONVERT }) Group.CONVERT else Group.TOOL)
    var phase by mutableStateOf<Phase>(Phase.Choosing)

    val visible get() = actions.filter { it.group == group }

    val kind: FileKind get() = files.map { FileKind.of(it) }.toSet().singleOrNull() ?: FileKind.OTHER

    val summary: String
        get() = if (files.size == 1) files[0].name
        else "${files.size} ${if (kind == FileKind.OTHER) "file" else kind.name.lowercase()}s"
}

class MorphModel(app: Application) : AndroidViewModel(app) {
    private val prefs = Prefs(app)

    var hasSeenWelcome by mutableStateOf(prefs.hasSeenWelcome)
        private set
    var haptics by mutableStateOf(prefs.haptics)
        private set
    var compression by mutableStateOf(prefs.compression)
        private set
    var sizeLimit by mutableStateOf(prefs.sizeLimit)
        private set
    var photoSize by mutableStateOf(PixelSize.parse(prefs.photoSize))
        private set
    var photoCaption by mutableStateOf(prefs.photoCaption)
        private set
    var palette by mutableStateOf(prefs.palette)
        private set
    var recent by mutableStateOf<List<HistoryEntry>>(emptyList())
        private set
    var job by mutableStateOf<Job?>(null)
        private set
    var importing by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)

    /** Set once per finished run so the UI can buzz. */
    var lastRunSucceeded by mutableStateOf<Boolean?>(null)

    init {
        Inbox.clean(app)
        reload()
    }

    fun reload() {
        viewModelScope.launch {
            recent = withContext(Dispatchers.IO) { History.load(getApplication()).reversed().take(30) }
        }
    }

    fun finishWelcome() { hasSeenWelcome = true; prefs.hasSeenWelcome = true }
    fun replayWelcome() { hasSeenWelcome = false; prefs.hasSeenWelcome = false }
    fun updateHaptics(on: Boolean) { haptics = on; prefs.haptics = on }
    fun updateCompression(level: Compression) { compression = level; prefs.compression = level }
    fun updateSizeLimit(bytes: Int) { sizeLimit = bytes; prefs.sizeLimit = bytes }
    fun updatePhotoSize(size: PixelSize?) { photoSize = size; prefs.photoSize = size?.key.orEmpty() }
    fun updatePhotoCaption(text: String) { photoCaption = text; prefs.photoCaption = text }
    fun updatePalette(choice: Palette) { palette = choice; prefs.palette = choice }

    /** Shared, picked or "Open with" content: copy it in, then show the actions sheet. */
    fun open(uris: List<Uri>, autoRun: String? = null) {
        if (uris.isEmpty()) return
        importing = true
        viewModelScope.launch {
            val files = runCatching { withContext(Dispatchers.IO) { Inbox.copy(getApplication(), uris) } }
                .onFailure { error = "Morph couldn't read that file." }
                .getOrDefault(emptyList())
            importing = false
            if (files.isNotEmpty()) {
                val newJob = Job(files)
                job = newJob
                autoRun?.let { id -> newJob.actions.firstOrNull { it.id == id }?.let { run(it) } }
            }
        }
    }

    fun closeJob() {
        if (job?.phase is Phase.Running) return
        job = null
        reload()
    }

    fun run(action: Action) {
        val current = job ?: return
        val app = getApplication<Application>()
        current.phase = Phase.Running(action, 0, current.files.size)
        viewModelScope.launch {
            val work = File(app.cacheDir, "work/${UUID.randomUUID()}")
            val result = Runner.run(app, action, current.files, Options(compression, work, sizeLimit.takeIf { it > 0 },
                exactSize = photoSize, caption = photoCaption.takeIf { it.isNotBlank() })) { done, total ->
                viewModelScope.launch { if (current.phase is Phase.Running) current.phase = Phase.Running(action, done, total) }
            }
            val failures = result.failures.toMutableList()
            val published = withContext(Dispatchers.IO) {
                result.outputs.mapNotNull { file ->
                    runCatching { Publisher.publish(app, file, work) }.onFailure { failures += "${file.name}: couldn't save" }.getOrNull()
                }.also {
                    work.deleteRecursively()
                    History.append(app, HistoryEntry(UUID.randomUUID().toString(), System.currentTimeMillis(), action.title,
                        current.files.size, it, failures))
                }
            }
            current.phase = Phase.Finished(action, published, failures)
            lastRunSucceeded = failures.isEmpty()
        }
    }

    fun deleteResults(entry: HistoryEntry) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { History.delete(getApplication(), entry.id) }
            reload()
        }
    }
}
