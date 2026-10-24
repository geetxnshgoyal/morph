using System.IO.Compression;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using PdfSharp.Drawing;
using PdfSharp.Pdf;

namespace Morph;

/// Documents go through a small shared model (headings, paragraphs, list items, code, quotes) so every reader
/// pairs with every writer; formatting inside a paragraph is not carried over.
public static partial class DocOps
{
    public static readonly IReadOnlyList<string> OutputFormats = ["pdf", "docx", "odt", "rtf", "html", "md", "txt"];

    public enum BlockKind { Heading, Paragraph, Bullet, Numbered, Code, Quote }

    public sealed record Block(BlockKind Kind, string Text, int Level = 1);

    public static string Convert(string path, string ext, Options options)
    {
        var input = FileKinds.Extension(path);
        var output = Output.For(path, ext, options);
        var title = Path.GetFileNameWithoutExtension(path);
        // Markdown to HTML keeps everything Markdig understands: emphasis, links, tables.
        if (ext == "html" && input is "md" or "markdown")
        {
            File.WriteAllText(output, HtmlPage(title, Markdig.Markdown.ToHtml(File.ReadAllText(path))));
            return output;
        }
        var blocks = Read(path);
        switch (ext)
        {
            case "txt": File.WriteAllText(output, PlainText(blocks)); break;
            case "md": File.WriteAllText(output, MarkdownText(blocks)); break;
            case "html": File.WriteAllText(output, HtmlPage(title, HtmlBody(blocks))); break;
            case "rtf": File.WriteAllText(output, Rtf(blocks), Encoding.ASCII); break;
            case "docx": WriteDocx(blocks, output); break;
            case "odt": WriteOdt(blocks, output); break;
            case "pdf": WritePdf(blocks, output); break;
            default: throw new MorphException($"Can't write .{ext} documents");
        }
        return output;
    }

    // MARK: Readers

    public static List<Block> Read(string path)
    {
        try
        {
            return FileKinds.Extension(path) switch
            {
                "md" or "markdown" => FromMarkdown(File.ReadAllText(path)),
                "html" or "htm" => FromHtml(File.ReadAllText(path)),
                "docx" => FromDocx(path),
                "odt" => FromOdt(path),
                "rtf" => FromPlain(RtfText(File.ReadAllText(path, Encoding.Latin1))),
                "pdf" => FromPlain(PdfOps.Text(path).GetAwaiter().GetResult()),
                "csv" or "tsv" or "json" or "srt" or "vtt" => [new Block(BlockKind.Code, File.ReadAllText(path).TrimEnd())],
                _ => FromPlain(File.ReadAllText(path)),
            };
        }
        catch (Exception e) when (e is not MorphException)
        {
            throw new MorphException($"Couldn't read {Path.GetFileName(path)}: {e.Message}");
        }
    }

    /// Blank lines separate paragraphs; single line breaks stay.
    static List<Block> FromPlain(string text) =>
        Regex.Split(text.Replace("\r\n", "\n").Trim(), @"\n[ \t]*\n+")
            .Where(p => p.Trim().Length > 0)
            .Select(p => new Block(BlockKind.Paragraph, p.Trim('\n')))
            .ToList();

    static List<Block> FromMarkdown(string text)
    {
        var blocks = new List<Block>();
        void Walk(ContainerBlock container, BlockKind? listKind, int depth, bool quoted)
        {
            foreach (var block in container)
            {
                switch (block)
                {
                    case HeadingBlock heading:
                        blocks.Add(new Block(BlockKind.Heading, InlineText(heading.Inline), heading.Level));
                        break;
                    case ParagraphBlock paragraph:
                        var kind = quoted ? BlockKind.Quote : listKind ?? BlockKind.Paragraph;
                        blocks.Add(new Block(kind, InlineText(paragraph.Inline), depth));
                        break;
                    case CodeBlock code:
                        blocks.Add(new Block(BlockKind.Code, string.Join("\n", code.Lines.Lines.Take(code.Lines.Count).Select(l => l.ToString()))));
                        break;
                    case ListBlock list:
                        foreach (var item in list.OfType<ListItemBlock>())
                            Walk(item, list.IsOrdered ? BlockKind.Numbered : BlockKind.Bullet, listKind is null ? 1 : depth + 1, quoted);
                        break;
                    case QuoteBlock quote:
                        Walk(quote, listKind, depth, true);
                        break;
                    case HtmlBlock html:
                        blocks.AddRange(FromHtml(string.Join("\n", html.Lines.Lines.Take(html.Lines.Count).Select(l => l.ToString()))));
                        break;
                    case ContainerBlock other:
                        Walk(other, listKind, depth, quoted);
                        break;
                }
            }
        }
        Walk(Markdig.Markdown.Parse(text), null, 1, false);
        return blocks;
    }

    static string InlineText(ContainerInline? inline)
    {
        if (inline is null) return "";
        var text = new StringBuilder();
        void Walk(Inline node)
        {
            switch (node)
            {
                case LiteralInline literal: text.Append(literal.Content.ToString()); break;
                case CodeInline code: text.Append(code.Content); break;
                case LineBreakInline lineBreak: text.Append(lineBreak.IsHard ? "\n" : " "); break;
                case AutolinkInline link: text.Append(link.Url); break;
                case ContainerInline container: foreach (var child in container) Walk(child); break;
            }
        }
        Walk(inline);
        return text.ToString();
    }

    /// Tags, comments, doctypes and processing instructions, or the text between them.
    static readonly Regex htmlToken = new(@"<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*>|<!--.*?-->|<[!?][^>]*>|([^<]+)", RegexOptions.Singleline);
    static readonly Regex htmlSkipped = new(@"<(script|style|head|template)\b.*?</\1\s*>", RegexOptions.Singleline | RegexOptions.IgnoreCase);

    /// A forgiving reading of HTML's block structure: headings, paragraphs, list items, pre and blockquote.
    static List<Block> FromHtml(string html)
    {
        var blocks = new List<Block>();
        var buffer = new StringBuilder();
        var kind = BlockKind.Paragraph;
        var level = 1;
        var inPre = false;
        var quoteDepth = 0;
        void Flush()
        {
            var text = inPre ? buffer.ToString().Trim('\n') : Regex.Replace(buffer.ToString(), @"[ \t\r\f]*\n[ \t\r\f]*", "\n").Trim();
            if (text.Length > 0) blocks.Add(new Block(kind == BlockKind.Paragraph && quoteDepth > 0 ? BlockKind.Quote : kind, text, level));
            buffer.Clear();
            kind = BlockKind.Paragraph;
            level = 1;
        }
        foreach (Match m in htmlToken.Matches(htmlSkipped.Replace(html, "")))
        {
            if (m.Groups[3].Success)
            {
                var text = WebUtility.HtmlDecode(m.Groups[3].Value);
                buffer.Append(inPre ? text : Regex.Replace(text, @"\s+", " "));
                continue;
            }
            if (!m.Groups[2].Success) continue;
            var tag = m.Groups[2].Value.ToLowerInvariant();
            var closing = m.Groups[1].Value == "/";
            switch (tag)
            {
                case "br": buffer.Append('\n'); break;
                case "h1" or "h2" or "h3" or "h4" or "h5" or "h6":
                    Flush();
                    if (!closing) { kind = BlockKind.Heading; level = tag[1] - '0'; }
                    break;
                case "li":
                    Flush();
                    if (!closing) kind = BlockKind.Bullet;
                    break;
                case "pre":
                    Flush();
                    inPre = !closing;
                    if (!closing) kind = BlockKind.Code;
                    break;
                case "blockquote":
                    Flush();
                    quoteDepth = Math.Max(0, quoteDepth + (closing ? -1 : 1));
                    break;
                case "p" or "div" or "section" or "article" or "header" or "footer" or "ul" or "ol" or "table" or "tr" or "main" or "nav" or "hr":
                    Flush();
                    break;
                case "td" or "th":
                    if (closing) buffer.Append('\t');
                    break;
            }
        }
        Flush();
        return blocks;
    }

    static List<Block> FromDocx(string path)
    {
        using var document = WordprocessingDocument.Open(path, false);
        var main = document.MainDocumentPart ?? throw new MorphException("This DOCX has no document body");
        var styleNames = main.StyleDefinitionsPart?.Styles?.Elements<Style>()
            .Where(s => s.StyleId?.Value is not null)
            .ToDictionary(s => s.StyleId!.Value!, s => s.StyleName?.Val?.Value ?? s.StyleId!.Value!) ?? [];
        var blocks = new List<Block>();
        foreach (var paragraph in main.Document?.Body?.Descendants<Paragraph>() ?? [])
        {
            var text = new StringBuilder();
            foreach (var element in paragraph.Descendants())
            {
                switch (element)
                {
                    case Text t: text.Append(t.Text); break;
                    case TabChar: text.Append('\t'); break;
                    case Break: text.Append('\n'); break;
                }
            }
            if (text.ToString().Trim().Length == 0) continue;
            var styleId = paragraph.ParagraphProperties?.ParagraphStyleId?.Val?.Value ?? "";
            var style = (styleNames.GetValueOrDefault(styleId) ?? styleId).ToLowerInvariant().Replace(" ", "");
            var numbering = paragraph.ParagraphProperties?.NumberingProperties;
            var block = style switch
            {
                "title" => new Block(BlockKind.Heading, text.ToString(), 1),
                _ when style.StartsWith("heading") && int.TryParse(style[7..], out var n) => new Block(BlockKind.Heading, text.ToString(), Math.Clamp(n, 1, 6)),
                _ when style.Contains("quote") => new Block(BlockKind.Quote, text.ToString()),
                _ when style.Contains("code") || style.Contains("htmlpreformatted") => new Block(BlockKind.Code, text.ToString()),
                _ when numbering is not null => ListItem(text.ToString(), (numbering.NumberingLevelReference?.Val?.Value ?? 0) + 1),
                "listparagraph" => ListItem(text.ToString(), IndentLevel(paragraph)),
                _ => new Block(BlockKind.Paragraph, text.ToString()),
            };
            blocks.Add(block);
        }
        return blocks;
    }

    /// A list item, with the "•" or "3." that Morph's own DOCX writes before the tab taken off.
    static Block ListItem(string text, int level)
    {
        if (text.StartsWith("•\t")) return new Block(BlockKind.Bullet, text[2..], level);
        var numbered = Regex.Match(text, @"^\d+[.)]\t");
        return numbered.Success ? new Block(BlockKind.Numbered, text[numbered.Length..], level) : new Block(BlockKind.Bullet, text, level);
    }

    /// List depth from the left indent, which Morph's DOCX writer sets at a quarter inch per level.
    static int IndentLevel(Paragraph paragraph) =>
        int.TryParse(paragraph.ParagraphProperties?.Indentation?.Left?.Value, out var twips) ? Math.Max(twips / 360, 1) : 1;

    static readonly XNamespace odfText = "urn:oasis:names:tc:opendocument:xmlns:text:1.0";
    static readonly XNamespace odfOffice = "urn:oasis:names:tc:opendocument:xmlns:office:1.0";
    static readonly XNamespace odfStyle = "urn:oasis:names:tc:opendocument:xmlns:style:1.0";
    static readonly XNamespace odfFo = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0";

    static List<Block> FromOdt(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        var entry = zip.GetEntry("content.xml") ?? throw new MorphException("This ODT has no content");
        using var stream = entry.Open();
        var content = XDocument.Load(stream);
        var blocks = new List<Block>();
        static string Text(XElement element)
        {
            var text = new StringBuilder();
            foreach (var node in element.Nodes())
            {
                if (node is XText t) text.Append(t.Value);
                else if (node is XElement e)
                {
                    if (e.Name == odfText + "s") text.Append(' ', (int?)e.Attribute(odfText + "c") ?? 1);
                    else if (e.Name == odfText + "tab") text.Append('\t');
                    else if (e.Name == odfText + "line-break") text.Append('\n');
                    else if (e.Name != odfText + "note") text.Append(Text(e));
                }
            }
            return text.ToString();
        }
        foreach (var element in content.Descendants().Where(e => e.Name == odfText + "h" || e.Name == odfText + "p"))
        {
            // A paragraph inside another paragraph-level element (a note, a frame) is read with its parent.
            if (element.Ancestors().Any(a => a.Name == odfText + "p" || a.Name == odfText + "h")) continue;
            var text = Text(element);
            if (text.Trim().Length == 0) continue;
            if (element.Name == odfText + "h")
                blocks.Add(new Block(BlockKind.Heading, text, (int?)element.Attribute(odfText + "outline-level") ?? 1));
            else if (element.Ancestors(odfText + "list-item").Any())
                blocks.Add(new Block(BlockKind.Bullet, text, element.Ancestors(odfText + "list").Count()));
            else
                blocks.Add(new Block(BlockKind.Paragraph, text));
        }
        return blocks;
    }

    /// The text of an RTF document: groups that hold fonts, colours, pictures and other metadata are skipped,
    /// escapes and Unicode characters are decoded.
    public static string RtfText(string rtf)
    {
        var text = new StringBuilder();
        var skipDepth = new Stack<bool>();
        var skipping = false;
        var unicodeSkip = 1;
        var pendingSkip = 0;
        var codePage = 1252;
        var bytes = new List<byte>();
        void FlushBytes()
        {
            if (bytes.Count == 0) return;
            try { text.Append(CodePagesEncoding(codePage).GetString(bytes.ToArray())); }
            catch (ArgumentException) { text.Append(Encoding.Latin1.GetString(bytes.ToArray())); }
            bytes.Clear();
        }
        string[] destinations = ["fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "headerl", "headerr",
                                 "footerl", "footerr", "object", "listtable", "listoverridetable", "rsidtbl", "generator", "themedata",
                                 "colorschememapping", "datastore", "latentstyles", "xmlnstbl", "fldinst", "filetbl", "revtbl"];
        for (var i = 0; i < rtf.Length; i++)
        {
            var c = rtf[i];
            if (c == '{') { skipDepth.Push(skipping); continue; }
            if (c == '}') { FlushBytes(); skipping = skipDepth.Count > 0 && skipDepth.Pop(); continue; }
            if (c == '\\' && i + 1 < rtf.Length)
            {
                var next = rtf[i + 1];
                if (next is '\\' or '{' or '}')
                {
                    i++;
                    if (pendingSkip > 0) { pendingSkip--; continue; }
                    if (!skipping) { FlushBytes(); text.Append(next); }
                    continue;
                }
                if (next == '\'' && i + 3 < rtf.Length)
                {
                    var hex = rtf.Substring(i + 2, 2);
                    i += 3;
                    if (pendingSkip > 0) { pendingSkip--; continue; }
                    if (!skipping && byte.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out var b)) bytes.Add(b);
                    continue;
                }
                if (next == '*') { skipping = true; i++; continue; }
                if (next is '~' or '-' or '_')
                {
                    i++;
                    if (!skipping) { FlushBytes(); text.Append(next == '~' ? ' ' : next == '_' ? '‑' : ""); }
                    continue;
                }
                if (next is '\n' or '\r') { i++; if (!skipping) { FlushBytes(); text.Append('\n'); } continue; }
                var j = i + 1;
                while (j < rtf.Length && char.IsAsciiLetter(rtf[j])) j++;
                var word = rtf[(i + 1)..j];
                var k = j;
                if (k < rtf.Length && (rtf[k] == '-' || char.IsAsciiDigit(rtf[k]))) { k++; while (k < rtf.Length && char.IsAsciiDigit(rtf[k])) k++; }
                int? parameter = k > j && int.TryParse(rtf[j..k], out var p) ? p : null;
                if (k < rtf.Length && rtf[k] == ' ') k++;
                i = k - 1;
                if (destinations.Contains(word)) { skipping = true; continue; }
                switch (word)
                {
                    case "ansicpg": codePage = parameter ?? 1252; break;
                    case "uc": unicodeSkip = parameter ?? 1; break;
                    case "u" when parameter is int code:
                        if (!skipping) { FlushBytes(); text.Append((char)(code < 0 ? code + 65536 : code)); }
                        pendingSkip = unicodeSkip;
                        break;
                    case "par" or "line" or "sect" or "page" when !skipping: FlushBytes(); text.Append('\n'); break;
                    case "tab" when !skipping: FlushBytes(); text.Append('\t'); break;
                    case "cell" when !skipping: FlushBytes(); text.Append('\t'); break;
                    case "row" when !skipping: FlushBytes(); text.Append('\n'); break;
                    case "bullet" when !skipping: FlushBytes(); text.Append('•'); break;
                    case "emdash" when !skipping: FlushBytes(); text.Append('—'); break;
                    case "endash" when !skipping: FlushBytes(); text.Append('–'); break;
                    case "lquote" when !skipping: FlushBytes(); text.Append('‘'); break;
                    case "rquote" when !skipping: FlushBytes(); text.Append('’'); break;
                    case "ldblquote" when !skipping: FlushBytes(); text.Append('“'); break;
                    case "rdblquote" when !skipping: FlushBytes(); text.Append('”'); break;
                }
                continue;
            }
            if (c is '\r' or '\n') continue;
            if (pendingSkip > 0) { pendingSkip--; continue; }
            if (!skipping) { FlushBytes(); text.Append(c); }
        }
        FlushBytes();
        // \par ends every paragraph; make that the blank line the plain-text reader splits on.
        return Regex.Replace(text.ToString(), @"\n", "\n\n").Trim();
    }

    static Encoding CodePagesEncoding(int codePage)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        return Encoding.GetEncoding(codePage);
    }

    // MARK: Writers

    static string PlainText(List<Block> blocks)
    {
        var numbers = 0;
        return string.Join("\n\n", blocks.Select(b =>
        {
            numbers = b.Kind == BlockKind.Numbered ? numbers + 1 : 0;
            return b.Kind switch
            {
                BlockKind.Bullet => new string(' ', (b.Level - 1) * 2) + "• " + b.Text,
                BlockKind.Numbered => $"{new string(' ', (b.Level - 1) * 2)}{numbers}. {b.Text}",
                BlockKind.Quote => string.Join("\n", b.Text.Split('\n').Select(l => "    " + l)),
                _ => b.Text,
            };
        })) + "\n";
    }

    static string MarkdownText(List<Block> blocks)
    {
        var lines = new StringBuilder();
        var previous = BlockKind.Paragraph;
        foreach (var b in blocks)
        {
            var isList = b.Kind is BlockKind.Bullet or BlockKind.Numbered;
            if (lines.Length > 0) lines.Append(isList && previous == b.Kind ? "\n" : "\n\n");
            var indent = new string(' ', Math.Max(0, b.Level - 1) * 2);
            lines.Append(b.Kind switch
            {
                BlockKind.Heading => new string('#', Math.Clamp(b.Level, 1, 6)) + " " + b.Text.Replace('\n', ' '),
                BlockKind.Bullet => indent + "- " + b.Text,
                BlockKind.Numbered => indent + "1. " + b.Text,
                BlockKind.Code => "```\n" + b.Text + "\n```",
                BlockKind.Quote => string.Join("\n", b.Text.Split('\n').Select(l => "> " + l)),
                _ => b.Text.Replace("\n", "  \n"),
            });
            previous = b.Kind;
        }
        return lines.Append('\n').ToString();
    }

    static string HtmlPage(string title, string body) => $$"""
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>{{WebUtility.HtmlEncode(title)}}</title>
        <style>
        body { font: 16px/1.6 "Segoe UI", -apple-system, sans-serif; max-width: 46rem; margin: 3rem auto; padding: 0 1rem; color: #222; }
        pre { background: #f6f3f0; padding: 1rem; border-radius: 8px; overflow: auto; }
        blockquote { border-left: 3px solid #ff8f38; margin-left: 0; padding-left: 1rem; color: #555; }
        </style>
        </head>
        <body>
        {{body}}
        </body>
        </html>

        """;

    static string HtmlBody(List<Block> blocks)
    {
        var html = new StringBuilder();
        string? openList = null;
        static string Encode(string s) => WebUtility.HtmlEncode(s).Replace("\n", "<br>\n");
        foreach (var b in blocks)
        {
            var list = b.Kind switch { BlockKind.Bullet => "ul", BlockKind.Numbered => "ol", _ => null };
            if (openList != list)
            {
                if (openList is not null) html.Append($"</{openList}>\n");
                if (list is not null) html.Append($"<{list}>\n");
                openList = list;
            }
            html.Append(b.Kind switch
            {
                BlockKind.Heading => $"<h{Math.Clamp(b.Level, 1, 6)}>{Encode(b.Text)}</h{Math.Clamp(b.Level, 1, 6)}>\n",
                BlockKind.Bullet or BlockKind.Numbered => $"<li>{Encode(b.Text)}</li>\n",
                BlockKind.Code => $"<pre><code>{WebUtility.HtmlEncode(b.Text)}</code></pre>\n",
                BlockKind.Quote => $"<blockquote><p>{Encode(b.Text)}</p></blockquote>\n",
                _ => $"<p>{Encode(b.Text)}</p>\n",
            });
        }
        if (openList is not null) html.Append($"</{openList}>\n");
        return html.ToString();
    }

    static string Rtf(List<Block> blocks)
    {
        static string Escape(string s)
        {
            var text = new StringBuilder();
            foreach (var c in s)
            {
                if (c is '\\' or '{' or '}') text.Append('\\').Append(c);
                else if (c == '\n') text.Append(@"\line ");
                else if (c == '\t') text.Append(@"\tab ");
                else if (c > 127) text.Append($@"\u{(short)c}?");
                else text.Append(c);
            }
            return text.ToString();
        }
        var rtf = new StringBuilder(@"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Segoe UI;}{\f1\fmodern Consolas;}}\f0\fs22" + "\n");
        var number = 0;
        foreach (var b in blocks)
        {
            number = b.Kind == BlockKind.Numbered ? number + 1 : 0;
            rtf.Append(b.Kind switch
            {
                BlockKind.Heading => $@"{{\pard\sb240\sa120\b\fs{(b.Level switch { 1 => 40, 2 => 32, _ => 26 })} {Escape(b.Text)}\par}}",
                BlockKind.Bullet => $@"{{\pard\li{360 * b.Level}\fi-240\sa60 \bullet\tab {Escape(b.Text)}\par}}",
                BlockKind.Numbered => $@"{{\pard\li{360 * b.Level}\fi-240\sa60 {number}.\tab {Escape(b.Text)}\par}}",
                BlockKind.Code => $@"{{\pard\sa120\f1\fs19 {Escape(b.Text)}\par}}",
                BlockKind.Quote => $@"{{\pard\li720\sa120\i {Escape(b.Text)}\par}}",
                _ => $@"{{\pard\sa120 {Escape(b.Text)}\par}}",
            }).Append('\n');
        }
        return rtf.Append('}').ToString();
    }

    static void WriteDocx(List<Block> blocks, string output)
    {
        using var document = WordprocessingDocument.Create(output, WordprocessingDocumentType.Document);
        var main = document.AddMainDocumentPart();
        var styles = main.AddNewPart<StyleDefinitionsPart>();
        styles.Styles = new Styles(
            ParagraphStyle("Normal", "Normal", null, new StyleRunProperties(new RunFonts { Ascii = "Aptos", HighAnsi = "Aptos" }, new FontSize { Val = "22" }),
                new StyleParagraphProperties(new SpacingBetweenLines { After = "120", Line = "276", LineRule = LineSpacingRuleValues.Auto })),
            ParagraphStyle("Heading1", "heading 1", "Normal", new StyleRunProperties(new Bold(), new FontSize { Val = "36" }),
                new StyleParagraphProperties(new KeepNext(), new SpacingBetweenLines { Before = "360", After = "120" }, new OutlineLevel { Val = 0 })),
            ParagraphStyle("Heading2", "heading 2", "Normal", new StyleRunProperties(new Bold(), new FontSize { Val = "30" }),
                new StyleParagraphProperties(new KeepNext(), new SpacingBetweenLines { Before = "240", After = "120" }, new OutlineLevel { Val = 1 })),
            ParagraphStyle("Heading3", "heading 3", "Normal", new StyleRunProperties(new Bold(), new FontSize { Val = "26" }),
                new StyleParagraphProperties(new KeepNext(), new SpacingBetweenLines { Before = "240", After = "80" }, new OutlineLevel { Val = 2 })),
            ParagraphStyle("Quote", "Quote", "Normal", new StyleRunProperties(new Italic(), new Color { Val = "555555" }),
                new StyleParagraphProperties(new Indentation { Left = "720" })),
            ParagraphStyle("Code", "Code", "Normal", new StyleRunProperties(new RunFonts { Ascii = "Consolas", HighAnsi = "Consolas" }, new FontSize { Val = "19" }),
                new StyleParagraphProperties(new SpacingBetweenLines { After = "0" })),
            ParagraphStyle("ListParagraph", "List Paragraph", "Normal", new StyleRunProperties(),
                new StyleParagraphProperties(new SpacingBetweenLines { After = "60" })));

        var body = new Body();
        var number = 0;
        foreach (var b in blocks)
        {
            number = b.Kind == BlockKind.Numbered ? number + 1 : 0;
            var (style, prefix, indent) = b.Kind switch
            {
                BlockKind.Heading => ($"Heading{Math.Clamp(b.Level, 1, 3)}", "", 0),
                BlockKind.Bullet => ("ListParagraph", "•\t", 360 * b.Level),
                BlockKind.Numbered => ("ListParagraph", $"{number}.\t", 360 * b.Level),
                BlockKind.Code => ("Code", "", 0),
                BlockKind.Quote => ("Quote", "", 0),
                _ => ("Normal", "", 0),
            };
            var properties = new ParagraphProperties(new ParagraphStyleId { Val = style });
            if (indent > 0) properties.Append(new Indentation { Left = indent.ToString(), Hanging = "360" });
            var paragraph = new Paragraph(properties);
            var lines = (prefix + b.Text).Split('\n');
            var run = new Run();
            for (var i = 0; i < lines.Length; i++)
            {
                if (i > 0) run.Append(new Break());
                var parts = lines[i].Split('\t');
                for (var j = 0; j < parts.Length; j++)
                {
                    if (j > 0) run.Append(new TabChar());
                    run.Append(new Text(parts[j]) { Space = SpaceProcessingModeValues.Preserve });
                }
            }
            paragraph.Append(run);
            body.Append(paragraph);
        }
        main.Document = new Document(body);
        main.Document.Save();
    }

    static Style ParagraphStyle(string id, string name, string? basedOn, StyleRunProperties run, StyleParagraphProperties paragraph)
    {
        var style = new Style { Type = StyleValues.Paragraph, StyleId = id, Default = id == "Normal" ? OnOffValue.FromBoolean(true) : null };
        style.Append(new StyleName { Val = name });
        if (basedOn is not null) style.Append(new BasedOn { Val = basedOn });
        if (id.StartsWith("Heading")) style.Append(new PrimaryStyle());
        style.Append(paragraph, run);
        return style;
    }

    static void WriteOdt(List<Block> blocks, string output)
    {
        XElement Paragraph(XName name, string styleName, string text, params XAttribute[] extra)
        {
            var element = new XElement(name, new XAttribute(odfText + "style-name", styleName), extra);
            var lines = text.Split('\n');
            for (var i = 0; i < lines.Length; i++)
            {
                if (i > 0) element.Add(new XElement(odfText + "line-break"));
                foreach (var part in Regex.Split(lines[i], @"( {2,}|\t)"))
                {
                    if (part == "\t") element.Add(new XElement(odfText + "tab"));
                    else if (part.Length > 1 && part.Trim().Length == 0) element.Add(new XElement(odfText + "s", new XAttribute(odfText + "c", part.Length)));
                    else if (part.Length > 0) element.Add(new XText(part));
                }
            }
            return element;
        }
        XElement TextStyle(string name, params XAttribute[] properties) =>
            new(odfStyle + "style", new XAttribute(odfStyle + "name", name), new XAttribute(odfStyle + "family", "paragraph"),
                new XElement(odfStyle + "text-properties", properties));

        var text = new XElement(odfOffice + "text");
        XElement? list = null;
        foreach (var b in blocks)
        {
            if (b.Kind is BlockKind.Bullet or BlockKind.Numbered)
            {
                list ??= new XElement(odfText + "list");
                if (list.Parent is null) text.Add(list);
                list.Add(new XElement(odfText + "list-item", Paragraph(odfText + "p", "Standard", b.Text)));
                continue;
            }
            list = null;
            text.Add(b.Kind switch
            {
                BlockKind.Heading => Paragraph(odfText + "h", $"H{Math.Clamp(b.Level, 1, 3)}", b.Text, new XAttribute(odfText + "outline-level", b.Level)),
                BlockKind.Code => Paragraph(odfText + "p", "Code", b.Text),
                BlockKind.Quote => Paragraph(odfText + "p", "Quote", b.Text),
                _ => Paragraph(odfText + "p", "Standard", b.Text),
            });
        }
        var content = new XDocument(new XElement(odfOffice + "document-content",
            new XAttribute(XNamespace.Xmlns + "office", odfOffice), new XAttribute(XNamespace.Xmlns + "text", odfText),
            new XAttribute(XNamespace.Xmlns + "style", odfStyle), new XAttribute(XNamespace.Xmlns + "fo", odfFo),
            new XAttribute(odfOffice + "version", "1.2"),
            new XElement(odfOffice + "automatic-styles",
                TextStyle("H1", new XAttribute(odfFo + "font-size", "20pt"), new XAttribute(odfFo + "font-weight", "bold")),
                TextStyle("H2", new XAttribute(odfFo + "font-size", "16pt"), new XAttribute(odfFo + "font-weight", "bold")),
                TextStyle("H3", new XAttribute(odfFo + "font-size", "13pt"), new XAttribute(odfFo + "font-weight", "bold")),
                TextStyle("Code", new XAttribute(odfFo + "font-family", "Consolas"), new XAttribute(odfFo + "font-size", "9.5pt")),
                TextStyle("Quote", new XAttribute(odfFo + "font-style", "italic"))),
            new XElement(odfOffice + "body", text)));

        using var zip = ZipFile.Open(output, ZipArchiveMode.Create);
        // The mimetype comes first and uncompressed, so tools can sniff the file type.
        using (var writer = new StreamWriter(zip.CreateEntry("mimetype", System.IO.Compression.CompressionLevel.NoCompression).Open(), new UTF8Encoding(false)))
            writer.Write("application/vnd.oasis.opendocument.text");
        using (var writer = new StreamWriter(zip.CreateEntry("META-INF/manifest.xml").Open(), new UTF8Encoding(false)))
            writer.Write("""
                <?xml version="1.0" encoding="UTF-8"?>
                <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
                 <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.text"/>
                 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
                </manifest:manifest>
                """);
        using (var stream = zip.CreateEntry("content.xml").Open()) content.Save(stream);
    }

    /// US Letter pages with 0.75in margins, like the Mac app.
    static void WritePdf(List<Block> blocks, string output)
    {
        Fonts.Install();
        const double pageWidth = 612, pageHeight = 792, margin = 54, width = pageWidth - margin * 2;
        using var document = new PdfDocument();
        XGraphics? graphics = null;
        var y = 0.0;
        void NewPage()
        {
            graphics?.Dispose();
            var page = document.AddPage();
            page.Width = XUnit.FromPoint(pageWidth);
            page.Height = XUnit.FromPoint(pageHeight);
            graphics = XGraphics.FromPdfPage(page);
            y = margin;
        }
        NewPage();

        List<string> Wrap(string text, XFont font, double available)
        {
            var lines = new List<string>();
            foreach (var paragraphLine in text.Replace("\t", "    ").Split('\n'))
            {
                var line = "";
                foreach (var word in Regex.Split(paragraphLine, @"(?<= )"))
                {
                    var candidate = line + word;
                    if (graphics!.MeasureString(candidate.TrimEnd(), font).Width <= available || line.Length == 0 && graphics.MeasureString(word, font).Width <= available)
                    {
                        line = candidate;
                        continue;
                    }
                    if (line.Length > 0) lines.Add(line.TrimEnd());
                    line = word;
                    // A word wider than the line (a long URL) breaks wherever it has to.
                    while (graphics.MeasureString(line.TrimEnd(), font).Width > available && line.Length > 1)
                    {
                        var cut = line.Length - 1;
                        while (cut > 1 && graphics.MeasureString(line[..cut], font).Width > available) cut--;
                        lines.Add(line[..cut]);
                        line = line[cut..];
                    }
                }
                lines.Add(line.TrimEnd());
            }
            return lines;
        }

        var number = 0;
        foreach (var b in blocks)
        {
            number = b.Kind == BlockKind.Numbered ? number + 1 : 0;
            var (font, before, after, indent) = b.Kind switch
            {
                BlockKind.Heading => (new XFont(Fonts.Sans, b.Level switch { 1 => 20, 2 => 16, _ => 13 }, XFontStyleEx.Bold), 10.0, 4.0, 0.0),
                BlockKind.Code => (new XFont(Fonts.Mono, 9.5), 2.0, 8.0, 0.0),
                BlockKind.Quote => (new XFont(Fonts.Sans, 11, XFontStyleEx.Italic), 0.0, 8.0, 24.0),
                BlockKind.Bullet or BlockKind.Numbered => (new XFont(Fonts.Sans, 11), 0.0, 3.0, 18.0 * b.Level),
                _ => (new XFont(Fonts.Sans, 11), 0.0, 8.0, 0.0),
            };
            var lineHeight = font.GetHeight() * 1.2;
            if (y > margin) y += before;
            var lines = Wrap(b.Text, font, width - indent);
            for (var i = 0; i < lines.Count; i++)
            {
                if (y + lineHeight > pageHeight - margin) NewPage();
                if (i == 0 && b.Kind is BlockKind.Bullet or BlockKind.Numbered)
                    graphics!.DrawString(b.Kind == BlockKind.Bullet ? "•" : $"{number}.", font, XBrushes.Black, margin + indent - 14, y, XStringFormats.TopLeft);
                graphics!.DrawString(lines[i], font, XBrushes.Black, margin + indent, y, XStringFormats.TopLeft);
                y += lineHeight;
            }
            y += after;
        }
        graphics?.Dispose();
        document.Save(output);
    }

    // MARK: Subtitles

    static readonly Regex timing = new(@"(\d{2}:\d{2}:\d{2})[.,](\d{3})");

    public static string ConvertSubtitle(string path, string ext, Options options)
    {
        var text = File.ReadAllText(path).Replace("\r\n", "\n");
        var output = Output.For(path, ext, options);
        string Retime(string line, string separator) => timing.Replace(line, $"$1{separator}$2");
        var cues = text.Split("\n\n").Select(c => c.Trim('\n')).Where(c => c.Contains("-->")).ToList();
        string result;
        if (ext == "vtt")
        {
            result = "WEBVTT\n\n" + string.Join("\n\n", cues.Select(cue =>
                string.Join("\n", cue.Split('\n').SkipWhile(l => !l.Contains("-->")).Select(l => l.Contains("-->") ? Retime(l, ".") : l))));
        }
        else
        {
            result = string.Join("\n\n", cues.Select((cue, i) =>
            {
                var lines = cue.Split('\n').SkipWhile(l => !l.Contains("-->"))
                    .Select(l => l.Contains("-->") ? string.Join(" ", Retime(l, ",").Split(' ').Take(3)) : l);
                return $"{i + 1}\n" + string.Join("\n", lines);
            }));
        }
        File.WriteAllText(output, result + "\n");
        return output;
    }

    // MARK: Data tables

    public static List<List<string>> ParseDelimited(string text, char separator)
    {
        var rows = new List<List<string>>();
        var row = new List<string>();
        var field = new StringBuilder();
        var quoted = false;
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (quoted)
            {
                if (c == '"')
                {
                    if (i + 1 < text.Length && text[i + 1] == '"') { field.Append('"'); i++; }
                    else quoted = false;
                }
                else field.Append(c);
            }
            else if (c == '"' && field.Length == 0) quoted = true;
            else if (c == separator) { row.Add(field.ToString()); field.Clear(); }
            else if (c == '\n') { row.Add(field.ToString()); rows.Add(row); row = []; field.Clear(); }
            else if (c != '\r') field.Append(c);
        }
        if (field.Length > 0 || row.Count > 0) { row.Add(field.ToString()); rows.Add(row); }
        return rows;
    }

    static string FormatDelimited(List<List<string>> rows, string separator) =>
        string.Join("\n", rows.Select(row => string.Join(separator, row.Select(f =>
            f.Contains(separator) || f.Contains('"') || f.Contains('\n') ? "\"" + f.Replace("\"", "\"\"") + "\"" : f)))) + "\n";

    public static string ConvertData(string path, string ext, Options options)
    {
        var input = FileKinds.Extension(path);
        var text = File.ReadAllText(path);
        List<List<string>> rows;
        if (input == "json")
        {
            using var json = JsonDocument.Parse(text);
            if (json.RootElement.ValueKind != JsonValueKind.Array || json.RootElement.EnumerateArray().Any(e => e.ValueKind != JsonValueKind.Object))
                throw new MorphException("JSON must be an array of objects");
            var headers = new List<string>();
            foreach (var item in json.RootElement.EnumerateArray())
                foreach (var key in item.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal))
                    if (!headers.Contains(key)) headers.Add(key);
            rows = [headers, .. json.RootElement.EnumerateArray().Select(item => headers.Select(h =>
                item.TryGetProperty(h, out var v) ? v.ValueKind switch
                {
                    JsonValueKind.String => v.GetString() ?? "",
                    JsonValueKind.Null => "",
                    _ => v.GetRawText(),
                } : "").ToList())];
        }
        else rows = ParseDelimited(text, input == "tsv" ? '\t' : ',');

        var output = Output.For(path, ext, options);
        switch (ext)
        {
            case "json":
                if (rows.Count == 0) throw new MorphException("Empty table");
                var headers = rows[0];
                var objects = rows.Skip(1).Select(r => new SortedDictionary<string, string>(
                    headers.Select((h, i) => (h, i)).GroupBy(x => x.h).ToDictionary(g => g.Key, g => g.First().i < r.Count ? r[g.First().i] : ""),
                    StringComparer.Ordinal));
                File.WriteAllText(output, JsonSerializer.Serialize(objects, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }) + "\n");
                break;
            case "tsv": File.WriteAllText(output, FormatDelimited(rows, "\t")); break;
            default: File.WriteAllText(output, FormatDelimited(rows, ",")); break;
        }
        return output;
    }
}
