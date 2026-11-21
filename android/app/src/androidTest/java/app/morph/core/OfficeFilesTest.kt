package app.morph.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@RunWith(AndroidJUnit4::class)
class OfficeFilesTest {
    private val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "office-${UUID.randomUUID()}").apply { mkdirs() }
    private val options = Options(Compression.BALANCED, dir)

    private fun zip(name: String, vararg parts: Pair<String, String>) = File(dir, name).also { f ->
        ZipOutputStream(f.outputStream()).use { z -> parts.forEach { (entry, text) -> z.putNextEntry(ZipEntry(entry)); z.write(text.toByteArray()); z.closeEntry() } }
    }

    @Test
    fun slidesAndSheetsRead() {
        val a = "http://schemas.openxmlformats.org/drawingml/2006/main"
        val deck = zip("deck.pptx",
            "ppt/slides/slide10.xml" to """<p:sld xmlns:p="p" xmlns:a="$a"><a:p><a:r><a:t>Tenth</a:t></a:r></a:p></p:sld>""",
            "ppt/slides/slide2.xml" to """<p:sld xmlns:p="p" xmlns:a="$a"><a:p><a:r><a:t>Second</a:t></a:r><a:br/><a:r><a:t>line</a:t></a:r></a:p></p:sld>""",
            // Android's ZipFile refuses "../" entry names itself, so only a plain one is tried here.
            "ppt/media/image1.png" to "png")
        val text = DocOps.convert(deck, "txt", options).readText()
        assertTrue(text, "Slide 1" in text && "Second\nline" in text)
        assertTrue("slides out of order", text.indexOf("Second") < text.indexOf("Tenth"))
        val pictures = OfficeFiles.pictures(deck, options)
        assertEquals(listOf("image1.png"), pictures.map { it.name })
        assertEquals("deck pictures", pictures[0].parentFile!!.name)

        val m = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        val book = zip("book.xlsx",
            "xl/workbook.xml" to """<workbook xmlns="$m" xmlns:r="rel"><sheets><sheet name="People" r:id="rId1"/></sheets></workbook>""",
            "xl/_rels/workbook.xml.rels" to """<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>""",
            "xl/sharedStrings.xml" to """<sst xmlns="$m"><si><t>Name</t></si><si><r><t>Ad</t></r><r><t>a, B</t></r></si></sst>""",
            "xl/worksheets/sheet1.xml" to """<worksheet xmlns="$m"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>Age</t></is></c></row><row r="3"><c r="A3" t="s"><v>1</v></c><c r="C3"><v>36</v></c></row></sheetData></worksheet>""")
        assertEquals("Name,,Age\n,,\n\"Ada, B\",,36\n", DocOps.convertData(book, "csv", options).readText())

        val ods = zip("sheet.ods", "content.xml" to
            """<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">""" +
            """<table:table table:name="S"><table:table-row><table:table-cell table:number-columns-repeated="2"><text:p>x</text:p></table:table-cell><table:table-cell table:number-columns-repeated="16000"/></table:table-row>""" +
            """<table:table-row table:number-rows-repeated="1048000"><table:table-cell table:number-columns-repeated="16384"/></table:table-row></table:table></office:document-content>""")
        assertEquals(listOf(listOf("x", "x")), OfficeFiles.readSheets(ods)[0].second)
        dir.deleteRecursively()
    }
}
