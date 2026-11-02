package app.morph.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Runs every action that accepts each sample on the device. Samples go in the app's cache under "samples"
 * (adb push, then run-as cp); a report of each run is written next to them as report.txt.
 */
@RunWith(AndroidJUnit4::class)
class LibraryTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val samples = File(context.cacheDir, "samples")

    /** Failures that are the file's fault rather than the action's: a test pattern has no faces. */
    private val expected = listOf("No faces found", "No emails, phone or card numbers found", "No QR codes", "No text found",
        "already as small", "There's no silence")

    @Test
    fun everyActionRuns() = runBlocking {
        // Samples bundled in the test APK's assets (for release builds, which can't be reached with run-as).
        val assets = InstrumentationRegistry.getInstrumentation().context.assets
        assets.list("samples").orEmpty().forEach { name ->
            samples.mkdirs()
            File(samples, name).outputStream().use { out -> assets.open("samples/$name").use { it.copyTo(out) } }
        }
        val files = samples.listFiles().orEmpty().filter { it.isFile && it.name != "report.txt" }.sortedBy { it.name }
        assertTrue("No samples in ${samples.path}", files.isNotEmpty())
        val report = StringBuilder()
        var unexpected = 0
        val runs = files.map { listOf(it) } + listOf(files.filter { it.extension == "pdf" }).filter { it.size >= 2 }
        for (inputs in runs) {
            for (action in Library.actionsFor(inputs)) {
                val out = File(context.cacheDir, "out/${action.id}/${inputs.first().nameWithoutExtension}").apply { deleteRecursively(); mkdirs() }
                val result = Runner.run(context, action, inputs, Options(Compression.BALANCED, out)) { _, _ -> }
                val made = result.outputs.flatMap { if (it.isDirectory) it.walkTopDown().filter(File::isFile).toList() else listOf(it) }
                val ok = result.failures.isEmpty() && made.isNotEmpty() && made.all { it.length() > 0 }
                val excused = !ok && result.failures.isNotEmpty() && result.failures.all { f -> expected.any { it in f } }
                if (!ok && !excused) unexpected++
                report.append(if (ok) "ok   " else if (excused) "note " else "FAIL ")
                    .append(inputs.joinToString("+") { it.name }).append("  ").append(action.id).append("  ")
                    .append(made.joinToString { "${it.name} (${it.length()} B)" }).append(result.failures.joinToString(prefix = " ", separator = "; "))
                    .append('\n')
            }
        }
        File(samples, "report.txt").writeText(report.toString())
        assertTrue("$unexpected actions failed:\n$report", unexpected == 0)
    }
}
