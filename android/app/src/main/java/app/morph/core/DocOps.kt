package app.morph.core

import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.File
import java.nio.charset.Charset
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * Documents go through a small shared model (headings, paragraphs, list items, code, quotes) so every reader pairs
 * with every writer, as on Windows; formatting inside a paragraph is not carried over.
 */
object DocOps {
    val outputFormats = listOf("pdf", "docx", "odt", "rtf", "html", "md", "txt")

    enum class Kind { HEADING, PARAGRAPH, BULLET, NUMBERED, CODE, QUOTE }

    data class Block(val kind: Kind, val text: String, val level: Int = 1)

    fun convert(file: File, ext: String, o: Options): File {
        val blocks = read(file)
        val out = Output.file(file, ext, null, o)
        when (ext) {
            "txt" -> out.writeText(plainText(blocks))
            "md" -> out.writeText(markdownText(blocks))
            "html" -> out.writeText(htmlPage(file.nameWithoutExtension, htmlBody(blocks)))
            "rtf" -> out.writeText(rtf(blocks), Charsets.US_ASCII)
            "docx" -> writeDocx(blocks, out)
            "odt" -> writeOdt(blocks, out)
            "pdf" -> writePdf(blocks, out)
            else -> throw MorphError("Can't write .$ext documents")
        }
        return out
    }

    /** UTF-8 when it decodes cleanly, otherwise Windows-1252, which every byte is valid in. */
    fun readString(file: File): String {
        val bytes = file.readBytes()
        val decoder = Charsets.UTF_8.newDecoder()
        return try { decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString().removePrefix("﻿") }
        catch (_: java.nio.charset.CharacterCodingException) { String(bytes, Charset.forName("windows-1252")) }
    }

    // MARK: Readers

    fun read(file: File): List<Block> = try {
        when (file.extension.lowercase()) {
            "md", "markdown" -> fromMarkdown(readString(file))
            "html", "htm" -> fromHtml(readString(file))
            "docx" -> fromDocx(file)
            "odt" -> fromOdt(file)
            "rtf" -> fromPlain(rtfText(String(file.readBytes(), Charsets.ISO_8859_1)))
            "pdf" -> fromPlain(PdfOps.text(file))
            "csv", "tsv", "json", "srt", "vtt" -> listOf(Block(Kind.CODE, readString(file).trimEnd()))
            else -> fromPlain(readString(file))
        }
    } catch (e: MorphError) { throw e } catch (e: Exception) { throw MorphError("Couldn't read ${file.name}: ${e.message}") }

    /** Blank lines separate paragraphs; single line breaks stay. */
    private fun fromPlain(text: String) =
        text.replace("\r\n", "\n").trim().split(Regex("\n[ \t]*\n+")).filter { it.isNotBlank() }.map { Block(Kind.PARAGRAPH, it.trim('\n')) }

    /** Block structure only: headings, lists, fenced and indented code, quotes and paragraphs. */
    private fun fromMarkdown(text: String): List<Block> {
        val blocks = mutableListOf<Block>()
        val lines = text.replace("\r\n", "\n").split('\n')
        val paragraph = StringBuilder()
        var paragraphKind = Kind.PARAGRAPH
        fun flush() {
            if (paragraph.isNotBlank()) blocks += Block(paragraphKind, inline(paragraph.toString().trim()))
            paragraph.clear(); paragraphKind = Kind.PARAGRAPH
        }
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trimStart()
            val indent = line.length - trimmed.length
            when {
                trimmed.startsWith("```") || trimmed.startsWith("~~~") -> {
                    flush()
                    val fence = trimmed.take(3)
                    val code = mutableListOf<String>()
                    i++
                    while (i < lines.size && !lines[i].trimStart().startsWith(fence)) code += lines[i++]
                    blocks += Block(Kind.CODE, code.joinToString("\n"))
                }
                trimmed.isEmpty() -> flush()
                Regex("^#{1,6}\\s").containsMatchIn(trimmed) -> {
                    flush()
                    val level = trimmed.takeWhile { it == '#' }.length
                    blocks += Block(Kind.HEADING, inline(trimmed.drop(level).trim().trimEnd('#').trim()), level)
                }
                Regex("^[-*+]\\s").containsMatchIn(trimmed) -> { flush(); blocks += Block(Kind.BULLET, inline(trimmed.drop(2).trim()), indent / 2 + 1) }
                Regex("^\\d+[.)]\\s").containsMatchIn(trimmed) -> {
                    flush(); blocks += Block(Kind.NUMBERED, inline(trimmed.replaceFirst(Regex("^\\d+[.)]\\s+"), "")), indent / 2 + 1)
                }
                trimmed.startsWith(">") -> {
                    if (paragraphKind != Kind.QUOTE) flush()
                    paragraphKind = Kind.QUOTE
                    paragraph.append(trimmed.removePrefix(">").trim()).append('\n')
                }
                indent >= 4 && paragraph.isEmpty() -> {
                    val code = mutableListOf<String>()
                    while (i < lines.size && (lines[i].startsWith("    ") || lines[i].startsWith("\t"))) code += lines[i++].removePrefix("    ").removePrefix("\t")
                    blocks += Block(Kind.CODE, code.joinToString("\n"))
                    continue
                }
                Regex("^(-{3,}|\\*{3,}|_{3,})$").matches(trimmed) -> flush()
                else -> {
                    if (paragraphKind == Kind.QUOTE) flush()
                    // Two trailing spaces are a hard line break; otherwise lines join.
                    paragraph.append(if (line.endsWith("  ")) trimmed.trimEnd() + "\n" else "$trimmed ")
                }
            }
            i++
        }
        flush()
        return blocks
    }

    /** Markdown's inline syntax, reduced to its text: emphasis marks dropped, links kept as their text. */
    private fun inline(text: String) = text
        .replace(Regex("!?\\[([^\\]]*)]\\(([^)]*)\\)"), "$1")
        .replace(Regex("(\\*\\*|__)(.+?)\\1"), "$2")
        .replace(Regex("(?<![\\w*])[*_](.+?)[*_](?![\\w*])"), "$1")
        .replace(Regex("`([^`]*)`"), "$1")
        .replace(Regex("<(https?://[^>]+)>"), "$1")
        .trimEnd()

    private val htmlToken = Regex("<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*>|<!--.*?-->|<[!?][^>]*>|([^<]+)", RegexOption.DOT_MATCHES_ALL)
    private val htmlSkipped = Regex("<(script|style|head|template)\\b.*?</\\1\\s*>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))

    /** A forgiving reading of HTML's block structure: headings, paragraphs, list items, pre and blockquote. */
    private fun fromHtml(html: String): List<Block> {
        val blocks = mutableListOf<Block>()
        val buffer = StringBuilder()
        var kind = Kind.PARAGRAPH
        var level = 1
        var inPre = false
        var quoteDepth = 0
        fun flush() {
            val text = if (inPre) buffer.toString().trim('\n') else buffer.toString().replace(Regex("[ \t\r\u000c]*\n[ \t\r\u000c]*"), "\n").trim()
            if (text.isNotEmpty()) blocks += Block(if (kind == Kind.PARAGRAPH && quoteDepth > 0) Kind.QUOTE else kind, text, level)
            buffer.clear(); kind = Kind.PARAGRAPH; level = 1
        }
        for (m in htmlToken.findAll(htmlSkipped.replace(html, ""))) {
            m.groups[3]?.let { t ->
                val text = t.value.decodeEntities()
                buffer.append(if (inPre) text else text.replace(Regex("\\s+"), " "))
            } ?: run {
                val tag = m.groups[2]?.value?.lowercase() ?: return@run
                val closing = m.groupValues[1] == "/"
                when (tag) {
                    "br" -> buffer.append('\n')
                    "h1", "h2", "h3", "h4", "h5", "h6" -> { flush(); if (!closing) { kind = Kind.HEADING; level = tag[1] - '0' } }
                    "li" -> { flush(); if (!closing) kind = Kind.BULLET }
                    "pre" -> { flush(); inPre = !closing; if (!closing) kind = Kind.CODE }
                    "blockquote" -> { flush(); quoteDepth = (quoteDepth + if (closing) -1 else 1).coerceAtLeast(0) }
                    "p", "div", "section", "article", "header", "footer", "ul", "ol", "table", "tr", "main", "nav", "hr" -> flush()
                    "td", "th" -> if (closing) buffer.append('\t')
                }
            }
        }
        flush()
        return blocks
    }

    private val entities = mapOf("lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ", "amp" to "&",
        "mdash" to "—", "ndash" to "–", "hellip" to "…", "lsquo" to "‘", "rsquo" to "’", "ldquo" to "“", "rdquo" to "”", "copy" to "©")

    private fun String.decodeEntities() = replace(Regex("&(#x[0-9a-fA-F]+|#\\d+|[a-zA-Z]+);")) { m ->
        val name = m.groupValues[1]
        when {
            name.startsWith("#x") -> name.drop(2).toIntOrNull(16)?.let { String(Character.toChars(it)) }
            name.startsWith("#") -> name.drop(1).toIntOrNull()?.let { String(Character.toChars(it)) }
            else -> entities[name]
        } ?: m.value
    }

    private fun parser(stream: java.io.InputStream): XmlPullParser =
        XmlPullParserFactory.newInstance().apply { isNamespaceAware = true }.newPullParser().apply { setInput(stream, "UTF-8") }

    private const val W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    private fun fromDocx(file: File): List<Block> = ZipFile(file).use { zip ->
        // Style ids to names, so "Heading1" and a translated "Überschrift1" both read as headings.
        val styleNames = mutableMapOf<String, String>()
        zip.getEntry("word/styles.xml")?.let { entry ->
            val p = parser(zip.getInputStream(entry))
            var id: String? = null
            while (p.next() != XmlPullParser.END_DOCUMENT) {
                if (p.eventType != XmlPullParser.START_TAG || p.namespace != W) continue
                if (p.name == "style") id = p.getAttributeValue(W, "styleId")
                if (p.name == "name") id?.let { styleNames[it] = p.getAttributeValue(W, "val") ?: it }
            }
        }
        val entry = zip.getEntry("word/document.xml") ?: throw MorphError("This DOCX has no document body")
        val p = parser(zip.getInputStream(entry))
        val blocks = mutableListOf<Block>()
        val text = StringBuilder()
        var style = ""
        var numbering: Int? = null
        var indent = 0
        var inText = false
        while (p.next() != XmlPullParser.END_DOCUMENT) {
            when (p.eventType) {
                XmlPullParser.START_TAG -> if (p.namespace == W) when (p.name) {
                    "p" -> { text.clear(); style = ""; numbering = null; indent = 0 }
                    "pStyle" -> style = p.getAttributeValue(W, "val") ?: ""
                    "ilvl" -> numbering = p.getAttributeValue(W, "val")?.toIntOrNull()
                    "numPr" -> if (numbering == null) numbering = 0
                    "ind" -> indent = p.getAttributeValue(W, "left")?.toIntOrNull() ?: 0
                    "t" -> inText = true
                    "tab" -> text.append('\t')
                    "br", "cr" -> text.append('\n')
                }
                XmlPullParser.TEXT -> if (inText) text.append(p.text)
                XmlPullParser.END_TAG -> if (p.namespace == W) when (p.name) {
                    "t" -> inText = false
                    "p" -> {
                        val body = text.toString()
                        if (body.isBlank()) continue
                        val name = (styleNames[style] ?: style).lowercase().replace(" ", "")
                        blocks += when {
                            name == "title" -> Block(Kind.HEADING, body, 1)
                            name.startsWith("heading") && name.drop(7).toIntOrNull() != null -> Block(Kind.HEADING, body, name.drop(7).toInt().coerceIn(1, 6))
                            "quote" in name -> Block(Kind.QUOTE, body)
                            "code" in name || "htmlpreformatted" in name -> Block(Kind.CODE, body)
                            numbering != null -> listItem(body, numbering!! + 1)
                            name == "listparagraph" -> listItem(body, (indent / 360).coerceAtLeast(1))
                            else -> Block(Kind.PARAGRAPH, body)
                        }
                    }
                }
            }
        }
        blocks
    }

    /** A list item, with the "•" or "3." that Morph's own DOCX writes before the tab taken off. */
    private fun listItem(text: String, level: Int): Block {
        if (text.startsWith("•\t")) return Block(Kind.BULLET, text.drop(2), level)
        val numbered = Regex("^\\d+[.)]\t").find(text)
        return if (numbered != null) Block(Kind.NUMBERED, text.drop(numbered.value.length), level) else Block(Kind.BULLET, text, level)
    }

    private const val ODF_TEXT = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"

    private fun fromOdt(file: File): List<Block> = ZipFile(file).use { zip ->
        val entry = zip.getEntry("content.xml") ?: throw MorphError("This ODT has no content")
        val p = parser(zip.getInputStream(entry))
        val blocks = mutableListOf<Block>()
        val text = StringBuilder()
        var depth = 0 // paragraph nesting: a paragraph inside a note is read with its parent
        var heading = 0
        var lists = 0
        var listItems = 0
        var notes = 0
        while (p.next() != XmlPullParser.END_DOCUMENT) {
            val odf = p.namespace == ODF_TEXT
            when (p.eventType) {
                XmlPullParser.START_TAG -> if (odf) when (p.name) {
                    "h", "p" -> {
                        if (depth++ == 0) { text.clear(); heading = if (p.name == "h") p.getAttributeValue(ODF_TEXT, "outline-level")?.toIntOrNull() ?: 1 else 0 }
                    }
                    "s" -> if (notes == 0) text.append(" ".repeat(p.getAttributeValue(ODF_TEXT, "c")?.toIntOrNull() ?: 1))
                    "tab" -> if (notes == 0) text.append('\t')
                    "line-break" -> if (notes == 0) text.append('\n')
                    "list" -> lists++
                    "list-item" -> listItems++
                    "note" -> notes++
                }
                XmlPullParser.TEXT -> if (depth > 0 && notes == 0) text.append(p.text)
                XmlPullParser.END_TAG -> if (odf) when (p.name) {
                    "h", "p" -> if (--depth == 0 && text.isNotBlank()) blocks += when {
                        heading > 0 -> Block(Kind.HEADING, text.toString(), heading)
                        listItems > 0 -> Block(Kind.BULLET, text.toString(), lists.coerceAtLeast(1))
                        else -> Block(Kind.PARAGRAPH, text.toString())
                    }
                    "list" -> lists--
                    "list-item" -> listItems--
                    "note" -> notes--
                }
            }
        }
        blocks
    }

    private val rtfDestinations = setOf(
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "headerl", "headerr", "footerl", "footerr",
        "object", "listtable", "listoverridetable", "rsidtbl", "generator", "themedata", "colorschememapping", "datastore",
        "latentstyles", "xmlnstbl", "fldinst", "filetbl", "revtbl",
    )

    /** The text of an RTF document: font, colour, picture and other metadata groups skipped, escapes decoded. */
    fun rtfText(rtf: String): String {
        val text = StringBuilder()
        val skipStack = ArrayDeque<Boolean>()
        var skipping = false
        var unicodeSkip = 1
        var pendingSkip = 0
        var codePage = 1252
        val bytes = java.io.ByteArrayOutputStream()
        fun flushBytes() {
            if (bytes.size() == 0) return
            val charset = runCatching { Charset.forName("windows-$codePage") }.getOrDefault(Charsets.ISO_8859_1)
            text.append(String(bytes.toByteArray(), charset)); bytes.reset()
        }
        fun emit(s: String) { if (!skipping) { flushBytes(); text.append(s) } }
        var i = 0
        while (i < rtf.length) {
            val c = rtf[i]
            when {
                c == '{' -> skipStack.addLast(skipping)
                c == '}' -> { flushBytes(); skipping = skipStack.removeLastOrNull() ?: false }
                c == '\\' && i + 1 < rtf.length -> {
                    val next = rtf[i + 1]
                    when {
                        next == '\\' || next == '{' || next == '}' -> { i++; if (pendingSkip > 0) pendingSkip-- else emit(next.toString()) }
                        next == '\'' && i + 3 < rtf.length -> {
                            val hex = rtf.substring(i + 2, i + 4); i += 3
                            if (pendingSkip > 0) pendingSkip-- else if (!skipping) hex.toIntOrNull(16)?.let { bytes.write(it) }
                        }
                        next == '*' -> { skipping = true; i++ }
                        next == '~' || next == '-' || next == '_' -> { i++; emit(if (next == '~') " " else if (next == '_') "‑" else "") }
                        next == '\n' || next == '\r' -> { i++; emit("\n") }
                        else -> {
                            var j = i + 1
                            while (j < rtf.length && rtf[j].isLetter() && rtf[j].code < 128) j++
                            val word = rtf.substring(i + 1, j)
                            var k = j
                            if (k < rtf.length && (rtf[k] == '-' || rtf[k].isDigit())) { k++; while (k < rtf.length && rtf[k].isDigit()) k++ }
                            val parameter = if (k > j) rtf.substring(j, k).toIntOrNull() else null
                            if (k < rtf.length && rtf[k] == ' ') k++
                            i = k - 1
                            if (word in rtfDestinations) skipping = true
                            else when (word) {
                                "ansicpg" -> codePage = parameter ?: 1252
                                "uc" -> unicodeSkip = parameter ?: 1
                                "u" -> if (parameter != null) { emit((if (parameter < 0) parameter + 65536 else parameter).toChar().toString()); pendingSkip = unicodeSkip }
                                "par", "line", "sect", "page", "row" -> emit("\n")
                                "tab", "cell" -> emit("\t")
                                "bullet" -> emit("•")
                                "emdash" -> emit("—")
                                "endash" -> emit("–")
                                "lquote" -> emit("‘")
                                "rquote" -> emit("’")
                                "ldblquote" -> emit("“")
                                "rdblquote" -> emit("”")
                            }
                        }
                    }
                }
                c == '\r' || c == '\n' -> {}
                pendingSkip > 0 -> pendingSkip--
                !skipping -> { flushBytes(); text.append(c) }
            }
            i++
        }
        flushBytes()
        // \par ends every paragraph; make that the blank line the plain-text reader splits on.
        return text.toString().replace("\n", "\n\n").trim()
    }

    // MARK: Writers

    private fun plainText(blocks: List<Block>): String {
        var number = 0
        return blocks.joinToString("\n\n") { b ->
            number = if (b.kind == Kind.NUMBERED) number + 1 else 0
            val indent = "  ".repeat(b.level - 1)
            when (b.kind) {
                Kind.BULLET -> "$indent• ${b.text}"
                Kind.NUMBERED -> "$indent$number. ${b.text}"
                Kind.QUOTE -> b.text.lines().joinToString("\n") { "    $it" }
                else -> b.text
            }
        } + "\n"
    }

    private fun markdownText(blocks: List<Block>): String {
        val out = StringBuilder()
        var previous = Kind.PARAGRAPH
        for (b in blocks) {
            val isList = b.kind == Kind.BULLET || b.kind == Kind.NUMBERED
            if (out.isNotEmpty()) out.append(if (isList && previous == b.kind) "\n" else "\n\n")
            val indent = "  ".repeat((b.level - 1).coerceAtLeast(0))
            out.append(when (b.kind) {
                Kind.HEADING -> "#".repeat(b.level.coerceIn(1, 6)) + " " + b.text.replace('\n', ' ')
                Kind.BULLET -> "$indent- ${b.text}"
                Kind.NUMBERED -> "${indent}1. ${b.text}"
                Kind.CODE -> "```\n${b.text}\n```"
                Kind.QUOTE -> b.text.lines().joinToString("\n") { "> $it" }
                Kind.PARAGRAPH -> b.text.replace("\n", "  \n")
            })
            previous = b.kind
        }
        return out.append('\n').toString()
    }

    private fun String.html() = replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    private fun htmlPage(title: String, body: String) = """
        |<!doctype html>
        |<html>
        |<head>
        |<meta charset="utf-8">
        |<title>${title.html()}</title>
        |<style>
        |body { font: 16px/1.6 Roboto, -apple-system, "Segoe UI", sans-serif; max-width: 46rem; margin: 3rem auto; padding: 0 1rem; color: #222; }
        |pre { background: #f6f3f0; padding: 1rem; border-radius: 8px; overflow: auto; }
        |blockquote { border-left: 3px solid #0f766e; margin-left: 0; padding-left: 1rem; color: #555; }
        |</style>
        |</head>
        |<body>
        |$body</body>
        |</html>
        |""".trimMargin()

    private fun htmlBody(blocks: List<Block>): String {
        val html = StringBuilder()
        var openList: String? = null
        fun encode(s: String) = s.html().replace("\n", "<br>\n")
        for (b in blocks) {
            val list = when (b.kind) { Kind.BULLET -> "ul"; Kind.NUMBERED -> "ol"; else -> null }
            if (openList != list) {
                openList?.let { html.append("</$it>\n") }
                list?.let { html.append("<$it>\n") }
                openList = list
            }
            val h = b.level.coerceIn(1, 6)
            html.append(when (b.kind) {
                Kind.HEADING -> "<h$h>${encode(b.text)}</h$h>\n"
                Kind.BULLET, Kind.NUMBERED -> "<li>${encode(b.text)}</li>\n"
                Kind.CODE -> "<pre><code>${b.text.html()}</code></pre>\n"
                Kind.QUOTE -> "<blockquote><p>${encode(b.text)}</p></blockquote>\n"
                Kind.PARAGRAPH -> "<p>${encode(b.text)}</p>\n"
            })
        }
        openList?.let { html.append("</$it>\n") }
        return html.toString()
    }

    private fun rtf(blocks: List<Block>): String {
        fun escape(s: String) = buildString {
            for (c in s) when {
                c == '\\' || c == '{' || c == '}' -> append('\\').append(c)
                c == '\n' -> append("\\line ")
                c == '\t' -> append("\\tab ")
                c.code > 127 -> append("\\u${c.code.toShort()}?")
                else -> append(c)
            }
        }
        val out = StringBuilder("{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fswiss Helvetica;}{\\f1\\fmodern Courier;}}\\f0\\fs22\n")
        var number = 0
        for (b in blocks) {
            number = if (b.kind == Kind.NUMBERED) number + 1 else 0
            out.append(when (b.kind) {
                Kind.HEADING -> "{\\pard\\sb240\\sa120\\b\\fs${when (b.level) { 1 -> 40; 2 -> 32; else -> 26 }} ${escape(b.text)}\\par}"
                Kind.BULLET -> "{\\pard\\li${360 * b.level}\\fi-240\\sa60 \\bullet\\tab ${escape(b.text)}\\par}"
                Kind.NUMBERED -> "{\\pard\\li${360 * b.level}\\fi-240\\sa60 $number.\\tab ${escape(b.text)}\\par}"
                Kind.CODE -> "{\\pard\\sa120\\f1\\fs19 ${escape(b.text)}\\par}"
                Kind.QUOTE -> "{\\pard\\li720\\sa120\\i ${escape(b.text)}\\par}"
                Kind.PARAGRAPH -> "{\\pard\\sa120 ${escape(b.text)}\\par}"
            }).append('\n')
        }
        return out.append('}').toString()
    }

    private fun String.xml() = replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
        .filter { it == '\t' || it == '\n' || it.code >= 0x20 }

    private fun writeZip(out: File, entries: List<Pair<String, String>>) {
        ZipOutputStream(out.outputStream().buffered()).use { zip ->
            for ((index, entry) in entries.withIndex()) {
                val bytes = entry.second.toByteArray()
                val zipEntry = ZipEntry(entry.first)
                // ODF wants its mimetype first and stored, so tools can sniff the type.
                if (index == 0 && entry.first == "mimetype") {
                    zipEntry.method = ZipEntry.STORED
                    zipEntry.size = bytes.size.toLong()
                    zipEntry.crc = CRC32().apply { update(bytes) }.value
                }
                zip.putNextEntry(zipEntry)
                zip.write(bytes)
                zip.closeEntry()
            }
        }
    }

    private fun writeDocx(blocks: List<Block>, out: File) {
        fun style(id: String, name: String, run: String, paragraph: String) =
            """<w:style w:type="paragraph" w:styleId="$id"${if (id == "Normal") " w:default=\"1\"" else ""}><w:name w:val="$name"/>""" +
                (if (id != "Normal") """<w:basedOn w:val="Normal"/>""" else "") + (if (id.startsWith("Heading")) "<w:qFormat/>" else "") +
                "<w:pPr>$paragraph</w:pPr><w:rPr>$run</w:rPr></w:style>"
        val styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="$W">""" +
            style("Normal", "Normal", """<w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:sz w:val="22"/>""", """<w:spacing w:after="120" w:line="276" w:lineRule="auto"/>""") +
            style("Heading1", "heading 1", """<w:b/><w:sz w:val="36"/>""", """<w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/>""") +
            style("Heading2", "heading 2", """<w:b/><w:sz w:val="30"/>""", """<w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="1"/>""") +
            style("Heading3", "heading 3", """<w:b/><w:sz w:val="26"/>""", """<w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="2"/>""") +
            style("Quote", "Quote", """<w:i/><w:color w:val="555555"/>""", """<w:ind w:left="720"/>""") +
            style("Code", "Code", """<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="19"/>""", """<w:spacing w:after="0"/>""") +
            style("ListParagraph", "List Paragraph", "", """<w:spacing w:after="60"/>""") + "</w:styles>"
        val body = StringBuilder()
        var number = 0
        for (b in blocks) {
            number = if (b.kind == Kind.NUMBERED) number + 1 else 0
            val (style, prefix, indent) = when (b.kind) {
                Kind.HEADING -> Triple("Heading${b.level.coerceIn(1, 3)}", "", 0)
                Kind.BULLET -> Triple("ListParagraph", "•\t", 360 * b.level)
                Kind.NUMBERED -> Triple("ListParagraph", "$number.\t", 360 * b.level)
                Kind.CODE -> Triple("Code", "", 0)
                Kind.QUOTE -> Triple("Quote", "", 0)
                Kind.PARAGRAPH -> Triple("Normal", "", 0)
            }
            body.append("""<w:p><w:pPr><w:pStyle w:val="$style"/>""")
            if (indent > 0) body.append("""<w:ind w:left="$indent" w:hanging="360"/>""")
            body.append("</w:pPr><w:r>")
            (prefix + b.text).split('\n').forEachIndexed { i, line ->
                if (i > 0) body.append("<w:br/>")
                line.split('\t').forEachIndexed { j, part ->
                    if (j > 0) body.append("<w:tab/>")
                    body.append("""<w:t xml:space="preserve">${part.xml()}</w:t>""")
                }
            }
            body.append("</w:r></w:p>")
        }
        writeZip(out, listOf(
            "[Content_Types].xml" to """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>""",
            "_rels/.rels" to """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>""",
            "word/_rels/document.xml.rels" to """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>""",
            "word/styles.xml" to styles,
            "word/document.xml" to """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="$W"><w:body>$body<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>""",
        ))
    }

    private fun writeOdt(blocks: List<Block>, out: File) {
        fun paragraph(tag: String, style: String, text: String, extra: String = "") = buildString {
            append("<text:$tag text:style-name=\"$style\"$extra>")
            text.split('\n').forEachIndexed { i, line ->
                if (i > 0) append("<text:line-break/>")
                for (part in Regex("( {2,}|\t)|[^ \t]+| ").findAll(line).map { it.value }) when {
                    part == "\t" -> append("<text:tab/>")
                    part.length > 1 && part.isBlank() -> append("<text:s text:c=\"${part.length}\"/>")
                    else -> append(part.xml())
                }
            }
            append("</text:$tag>")
        }
        fun textStyle(name: String, props: String) =
            """<style:style style:name="$name" style:family="paragraph"><style:text-properties $props/></style:style>"""
        val body = StringBuilder()
        var inList = false
        for (b in blocks) {
            val isList = b.kind == Kind.BULLET || b.kind == Kind.NUMBERED
            if (isList != inList) { body.append(if (isList) "<text:list>" else "</text:list>"); inList = isList }
            body.append(when (b.kind) {
                Kind.BULLET, Kind.NUMBERED -> "<text:list-item>${paragraph("p", "Standard", b.text)}</text:list-item>"
                Kind.HEADING -> paragraph("h", "H${b.level.coerceIn(1, 3)}", b.text, " text:outline-level=\"${b.level}\"")
                Kind.CODE -> paragraph("p", "Code", b.text)
                Kind.QUOTE -> paragraph("p", "Quote", b.text)
                Kind.PARAGRAPH -> paragraph("p", "Standard", b.text)
            })
        }
        if (inList) body.append("</text:list>")
        val content = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="$ODF_TEXT" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" office:version="1.2"><office:automatic-styles>""" +
            textStyle("H1", "fo:font-size=\"20pt\" fo:font-weight=\"bold\"") + textStyle("H2", "fo:font-size=\"16pt\" fo:font-weight=\"bold\"") +
            textStyle("H3", "fo:font-size=\"13pt\" fo:font-weight=\"bold\"") + textStyle("Code", "fo:font-family=\"monospace\" fo:font-size=\"9.5pt\"") +
            textStyle("Quote", "fo:font-style=\"italic\"") + "</office:automatic-styles><office:body><office:text>$body</office:text></office:body></office:document-content>"
        writeZip(out, listOf(
            "mimetype" to "application/vnd.oasis.opendocument.text",
            "META-INF/manifest.xml" to """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
 <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.text"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
</manifest:manifest>""",
            "content.xml" to content,
        ))
    }

    /** US Letter pages with 0.75 in margins, like the Mac and Windows apps. */
    private fun writePdf(blocks: List<Block>, out: File) {
        val pageWidth = 612; val pageHeight = 792; val margin = 54f; val width = pageWidth - margin * 2
        val doc = PdfDocument()
        try {
            var pageNumber = 0
            var page: PdfDocument.Page? = null
            var y = 0f
            fun newPage() {
                page?.let { doc.finishPage(it) }
                page = doc.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, ++pageNumber).create())
                y = margin
            }
            newPage()
            var number = 0
            for (b in blocks) {
                number = if (b.kind == Kind.NUMBERED) number + 1 else 0
                val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.BLACK }
                var before = 0f; var after = 8f; var indent = 0f
                when (b.kind) {
                    Kind.HEADING -> { paint.textSize = when (b.level) { 1 -> 20f; 2 -> 16f; else -> 13f }; paint.typeface = Typeface.DEFAULT_BOLD; before = 10f; after = 4f }
                    Kind.CODE -> { paint.textSize = 9.5f; paint.typeface = Typeface.MONOSPACE; before = 2f }
                    Kind.QUOTE -> { paint.textSize = 11f; paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.ITALIC); indent = 24f }
                    Kind.BULLET, Kind.NUMBERED -> { paint.textSize = 11f; after = 3f; indent = 18f * b.level }
                    Kind.PARAGRAPH -> paint.textSize = 11f
                }
                if (y > margin) y += before
                val layout = StaticLayout.Builder.obtain(b.text.replace("\t", "    "), 0, b.text.replace("\t", "    ").length, paint, (width - indent).toInt())
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(0f, 1.2f).build()
                for (line in 0 until layout.lineCount) {
                    val lineHeight = (layout.getLineBottom(line) - layout.getLineTop(line)).toFloat()
                    if (y + lineHeight > pageHeight - margin) newPage()
                    val canvas = page!!.canvas
                    val baseline = y + (layout.getLineBaseline(line) - layout.getLineTop(line))
                    if (line == 0 && (b.kind == Kind.BULLET || b.kind == Kind.NUMBERED))
                        canvas.drawText(if (b.kind == Kind.BULLET) "•" else "$number.", margin + indent - 14, baseline, paint)
                    val start = layout.getLineStart(line); val end = layout.getLineEnd(line)
                    canvas.drawText(layout.text, start, end, margin + indent, baseline, paint)
                    y += lineHeight
                }
                y += after
            }
            page?.let { doc.finishPage(it) }
            out.outputStream().use { doc.writeTo(it) }
        } finally {
            doc.close()
        }
    }

    // MARK: Subtitles

    private val timing = Regex("(\\d{2}:\\d{2}:\\d{2})[.,](\\d{3})")

    fun convertSubtitle(file: File, ext: String, o: Options): File {
        val text = readString(file).replace("\r\n", "\n").replace('\r', '\n')
        val out = Output.file(file, ext, null, o)
        fun retime(line: String, sep: String) = timing.replace(line, "$1$sep$2")
        val cues = text.split("\n\n").map { it.trim('\n') }.filter { "-->" in it }
        val result = if (ext == "vtt") {
            "WEBVTT\n\n" + cues.joinToString("\n\n") { cue ->
                cue.split('\n').dropWhile { "-->" !in it }.joinToString("\n") { if ("-->" in it) retime(it, ".") else it }
            }
        } else {
            cues.mapIndexed { i, cue ->
                val lines = cue.split('\n').dropWhile { "-->" !in it }
                    .map { if ("-->" in it) retime(it, ",").split(' ').take(3).joinToString(" ") else it }
                "${i + 1}\n" + lines.joinToString("\n")
            }.joinToString("\n\n")
        }
        out.writeText(result + "\n")
        return out
    }

    // MARK: Data tables

    fun parseDelimited(text: String, separator: Char): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var quoted = false
        val s = text.replace("\r\n", "\n").replace('\r', '\n')
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                quoted -> if (c == '"') { if (i + 1 < s.length && s[i + 1] == '"') { field.append('"'); i++ } else quoted = false } else field.append(c)
                c == '"' && field.isEmpty() -> quoted = true
                c == separator -> { row += field.toString(); field.clear() }
                c == '\n' -> { row += field.toString(); rows += row; row = mutableListOf(); field.clear() }
                else -> field.append(c)
            }
            i++
        }
        if (field.isNotEmpty() || row.isNotEmpty()) { row += field.toString(); rows += row }
        return rows
    }

    private fun formatDelimited(rows: List<List<String>>, separator: String) = rows.joinToString("\n") { row ->
        row.joinToString(separator) { f -> if (separator in f || '"' in f || '\n' in f) "\"" + f.replace("\"", "\"\"") + "\"" else f }
    } + "\n"

    fun convertData(file: File, ext: String, o: Options): File {
        val input = file.extension.lowercase()
        val text = readString(file)
        val rows: List<List<String>> = if (input == "json") {
            val array = runCatching { JSONArray(text) }.getOrNull() ?: throw MorphError("JSON must be an array of objects")
            val objects = (0 until array.length()).map { array.opt(it) as? JSONObject ?: throw MorphError("JSON must be an array of objects") }
            val headers = mutableListOf<String>()
            for (obj in objects) for (key in obj.keys().asSequence().sorted()) if (key !in headers) headers += key
            listOf(headers) + objects.map { obj -> headers.map { h -> if (!obj.has(h) || obj.isNull(h)) "" else obj.get(h).toString() } }
        } else parseDelimited(text, if (input == "tsv") '\t' else ',')
        val out = Output.file(file, ext, null, o)
        when (ext) {
            "json" -> {
                val headers = rows.firstOrNull() ?: throw MorphError("Empty table")
                val array = JSONArray()
                for (r in rows.drop(1)) {
                    val obj = JSONObject()
                    headers.forEachIndexed { i, h -> if (!obj.has(h)) obj.put(h, r.getOrElse(i) { "" }) }
                    array.put(sortedObject(obj))
                }
                out.writeText(array.toString(2).replace("\\/", "/") + "\n")
            }
            "tsv" -> out.writeText(formatDelimited(rows, "\t"))
            else -> out.writeText(formatDelimited(rows, ","))
        }
        return out
    }

    /** org.json keeps insertion order, so sorting keys means rebuilding the object. */
    private fun sortedObject(obj: JSONObject) = JSONObject().also { sorted -> obj.keys().asSequence().sorted().forEach { sorted.put(it, obj.get(it)) } }
}
