package app.morph.core

import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.File
import java.util.zip.ZipFile

/** Slides and spreadsheets: PowerPoint, Excel and OpenDocument, read from their XML as on the Mac and Windows.
 *  Keynote, Numbers and the old binary Office formats need LibreOffice, which phones don't have. */
object OfficeFiles {
    val slides = setOf("pptx", "ppsx", "potx", "odp")
    val sheets = setOf("xlsx", "xlsm", "ods")
    private val mediaFolders = listOf("ppt/media/", "word/media/", "xl/media/", "Pictures/")
    private val withPictures = slides + sheets + setOf("docx", "odt")

    private fun ZipFile.parser(name: String): XmlPullParser? = getEntry(name)?.let { entry ->
        XmlPullParserFactory.newInstance().apply { isNamespaceAware = true }.newPullParser().apply { setInput(getInputStream(entry), "UTF-8") }
    }

    /** Walks a part's elements by local name: start(name, attribute by local name), text, end(name). */
    private fun XmlPullParser.walk(start: (String, (String) -> String?) -> Unit, text: (String) -> Unit = {}, end: (String) -> Unit = {}) {
        while (next() != XmlPullParser.END_DOCUMENT) when (eventType) {
            XmlPullParser.START_TAG -> start(name) { local -> (0 until attributeCount).firstOrNull { getAttributeName(it) == local }?.let { getAttributeValue(it) } }
            XmlPullParser.TEXT -> text(getText())
            XmlPullParser.END_TAG -> end(name)
        }
    }

    // MARK: Slides

    /** Each slide's text under a "Slide n" heading. */
    fun readSlides(file: File): List<DocOps.Block> = ZipFile(file).use { zip ->
        val blocks = mutableListOf<DocOps.Block>()
        val parts = if (file.extension.lowercase() == "odp") {
            listOf(zip.parser("content.xml") ?: throw MorphError("This presentation has no content"))
        } else {
            zip.entries().asSequence().mapNotNull { e ->
                e.name.takeIf { it.startsWith("ppt/slides/slide") && it.endsWith(".xml") }?.removePrefix("ppt/slides/slide")?.removeSuffix(".xml")?.toIntOrNull()?.let { it to e.name }
            }.sortedBy { it.first }.map { zip.parser(it.second)!! }.toList().ifEmpty { throw MorphError("This presentation has no slides") }
        }
        var slide = 0
        val text = StringBuilder()
        var inText = false
        val odp = file.extension.lowercase() == "odp"
        for (p in parts) {
            if (!odp) blocks += DocOps.Block(DocOps.Kind.HEADING, "Slide ${++slide}", 1)
            p.walk(start = { name, attr ->
                when (name) {
                    "page" -> if (odp) blocks += DocOps.Block(DocOps.Kind.HEADING, "Slide ${++slide}", 1)
                    "p", "h" -> { text.clear(); inText = odp }
                    "t" -> inText = true
                    "br", "line-break" -> text.append('\n')
                    "tab" -> text.append('\t')
                    "s" -> if (odp) text.append(" ".repeat(attr("c")?.toIntOrNull() ?: 1))
                }
            }, text = { if (inText) text.append(it) }, end = { name ->
                when (name) {
                    "t" -> inText = odp
                    "p", "h" -> { if (text.isNotBlank()) blocks += DocOps.Block(DocOps.Kind.PARAGRAPH, text.toString()); inText = false }
                }
            })
        }
        blocks
    }

    // MARK: Sheets

    /** Every sheet's cells, in sheet order. */
    fun readSheets(file: File): List<Pair<String, List<List<String>>>> = ZipFile(file).use { zip ->
        if (file.extension.lowercase() == "ods") return odsSheets(zip.parser("content.xml") ?: throw MorphError("This spreadsheet has no content"))
        val shared = mutableListOf<String>()
        zip.parser("xl/sharedStrings.xml")?.let { p ->
            var current: StringBuilder? = null
            var inText = false
            var phonetic = false
            p.walk(start = { name, _ ->
                when (name) { "si" -> current = StringBuilder(); "rPh" -> phonetic = true; "t" -> inText = !phonetic }
            }, text = { if (inText) current?.append(it) }, end = { name ->
                when (name) { "si" -> { shared += current?.toString() ?: ""; current = null }; "rPh" -> phonetic = false; "t" -> inText = false }
            })
        }
        // Sheet names and order from the workbook, their files from its relationships.
        val targets = mutableMapOf<String, String>()
        zip.parser("xl/_rels/workbook.xml.rels")?.walk(start = { name, attr ->
            if (name == "Relationship") { val id = attr("Id"); val t = attr("Target"); if (id != null && t != null) targets[id] = t }
        })
        val files = mutableListOf<Pair<String, String>>()
        zip.parser("xl/workbook.xml")?.walk(start = { name, attr ->
            if (name == "sheet") targets[attr("id")]?.let { t -> files += (attr("name") ?: "Sheet") to (if (t.startsWith("/")) t.drop(1) else "xl/$t") }
        })
        if (files.isEmpty()) zip.entries().asSequence().map { it.name }.filter { it.startsWith("xl/worksheets/sheet") && it.endsWith(".xml") }.sorted().forEach { files += it to it }
        files.mapNotNull { (name, path) -> zip.parser(path)?.let { name to xlsxRows(it, shared) } }
    }

    private fun xlsxRows(p: XmlPullParser, shared: List<String>): List<List<String>> {
        val cells = mutableMapOf<Int, MutableMap<Int, String>>()
        var row = 0
        var col = -1
        var type = ""
        val value = StringBuilder()
        var inValue = false
        fun column(ref: String?): Int? {
            val letters = ref?.takeWhile { it.isLetter() }?.uppercase().orEmpty()
            return if (letters.isEmpty()) null else letters.fold(0) { n, c -> n * 26 + (c - 'A' + 1) } - 1
        }
        p.walk(start = { name, attr ->
            when (name) {
                "row" -> { row = attr("r")?.toIntOrNull() ?: (row + 1); col = -1 }
                "c" -> { col = column(attr("r")) ?: (col + 1); type = attr("t") ?: ""; value.clear() }
                "v", "t" -> inValue = true
            }
        }, text = { if (inValue) value.append(it) }, end = { name ->
            when (name) {
                "v", "t" -> inValue = false
                "c" -> {
                    val text = when (type) {
                        "s" -> value.toString().toIntOrNull()?.let { shared.getOrNull(it) } ?: ""
                        "b" -> if (value.toString() == "1") "TRUE" else "FALSE"
                        // shortcut: dates come out as Excel's day numbers (45000), not formatted dates.
                        else -> value.toString()
                    }
                    if (text.isNotEmpty()) cells.getOrPut(row - 1) { mutableMapOf() }[col] = text
                }
            }
        })
        return grid(cells)
    }

    private fun odsSheets(p: XmlPullParser): List<Pair<String, List<List<String>>>> {
        val sheets = mutableListOf<Pair<String, List<List<String>>>>()
        var cells = mutableMapOf<Int, MutableMap<Int, String>>()
        var name = ""
        var row = 0
        var col = 0
        var rowRepeat = 1
        var cellRepeat = 1
        val cell = StringBuilder()
        var paragraphs = 0
        var inCell = false
        p.walk(start = { el, attr ->
            when (el) {
                "table" -> { name = attr("name") ?: "Sheet ${sheets.size + 1}"; cells = mutableMapOf(); row = 0 }
                "table-row" -> { col = 0; rowRepeat = (attr("number-rows-repeated")?.toIntOrNull() ?: 1).coerceAtMost(10_000) }
                "table-cell", "covered-table-cell" -> {
                    inCell = true; cell.clear(); paragraphs = 0
                    cellRepeat = (attr("number-columns-repeated")?.toIntOrNull() ?: 1).coerceAtMost(1_000)
                }
                "p" -> if (inCell) { if (paragraphs > 0) cell.append('\n'); paragraphs++ }
                "s" -> if (inCell) cell.append(" ".repeat(attr("c")?.toIntOrNull() ?: 1))
                "tab" -> if (inCell) cell.append('\t')
            }
        }, text = { if (inCell) cell.append(it) }, end = { el ->
            when (el) {
                "table-cell", "covered-table-cell" -> {
                    // Repeats are how ODS fills the empty rest of a sheet (a million cells); only filled ones are kept.
                    if (cell.isNotEmpty()) repeat(cellRepeat) { cells.getOrPut(row) { mutableMapOf() }[col + it] = cell.toString() }
                    col += cellRepeat; inCell = false
                }
                "table-row" -> {
                    cells[row]?.let { filled -> for (i in 1 until rowRepeat) cells[row + i] = filled.toMutableMap() }
                    row += rowRepeat
                }
                "table" -> sheets += name to grid(cells)
            }
        })
        return sheets
    }

    /** Sparse cells to rows, padded to the widest row; empty rows inside the table are kept. */
    private fun grid(cells: Map<Int, Map<Int, String>>): List<List<String>> {
        val last = cells.keys.maxOrNull() ?: return emptyList()
        val width = (cells.values.mapNotNull { it.keys.maxOrNull() }.maxOrNull() ?: -1) + 1
        return (0..last).map { r -> (0 until width).map { cells[r]?.get(it) ?: "" } }
    }

    fun sheetsAsBlocks(sheets: List<Pair<String, List<List<String>>>>): List<DocOps.Block> = sheets.flatMap { (name, rows) ->
        listOfNotNull(
            if (sheets.size > 1) DocOps.Block(DocOps.Kind.HEADING, name, 2) else null,
            if (rows.isNotEmpty()) DocOps.Block(DocOps.Kind.CODE, rows.joinToString("\n") { it.joinToString("\t") }) else null,
        )
    }

    // MARK: Pictures

    fun hasPictures(file: File) = file.extension.lowercase() in withPictures

    /** The pictures placed in an Office or OpenDocument file, saved into a "<name> pictures" folder. */
    fun pictures(file: File, o: Options): List<File> = ZipFile(file).use { zip ->
        val images = zip.entries().asSequence().filter { e ->
            !e.isDirectory && mediaFolders.any { e.name.startsWith(it) } && FileKind.of(File(e.name)) == FileKind.IMAGE
        }.sortedBy { it.name.lowercase() }.toList()
        if (images.isEmpty()) throw MorphError("${file.name} has no pictures in it")
        val folder = Output.unique(o.outDir, "${file.nameWithoutExtension} pictures", "").apply { delete(); mkdirs() }
        images.map { e ->
            // The name comes from inside the file; keep only its last part so it stays in the folder.
            val name = File(e.name.substringAfterLast('/').substringAfterLast('\\'))
            Output.unique(folder, name.nameWithoutExtension.ifBlank { "picture" }.takeUnless { it == ".." } ?: "picture", name.extension).also { out ->
                zip.getInputStream(e).use { input -> out.outputStream().use { input.copyTo(it) } }
            }
        }
    }
}
