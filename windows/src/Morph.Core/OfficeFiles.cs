using System.IO.Compression;
using System.Text;
using System.Xml.Linq;

namespace Morph;

/// Slides and spreadsheets: PowerPoint, Excel and OpenDocument read from their XML, plus Keynote, Numbers, Pages
/// and the old binary Office formats through LibreOffice when it's installed.
public static class OfficeFiles
{
    public static readonly IReadOnlySet<string> Slides = new HashSet<string> { "pptx", "ppsx", "potx", "odp" };
    public static readonly IReadOnlySet<string> Sheets = new HashSet<string> { "xlsx", "xlsm", "ods" };
    /// Need LibreOffice to open; each is turned into its modern counterpart first.
    public static readonly IReadOnlyDictionary<string, string> Legacy = new Dictionary<string, string>
    {
        ["ppt"] = "pptx", ["pps"] = "pptx", ["key"] = "pptx", ["xls"] = "xlsx", ["numbers"] = "xlsx", ["pages"] = "docx",
    };
    static readonly string[] mediaFolders = ["ppt/media/", "word/media/", "xl/media/", "Pictures/"];
    static readonly HashSet<string> withPictures = ["pptx", "ppsx", "potx", "odp", "xlsx", "xlsm", "ods", "docx", "odt"];

    // MARK: LibreOffice

    public static string? LibreOffice
    {
        get
        {
            if (OperatingSystem.IsWindows())
                foreach (var root in new[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86 })
                {
                    var exe = Path.Combine(Environment.GetFolderPath(root), @"LibreOffice\program\soffice.exe");
                    if (File.Exists(exe)) return exe;
                }
            return ExternalTool.Find("soffice");
        }
    }

    /// Whether a legacy format can be opened here (it has a FileKind only then, so no action is offered that would fail).
    public static bool CanOpen(string ext) => !Legacy.ContainsKey(ext) || LibreOffice is not null;

    /// LibreOffice's own export, saved as `output`.
    public static async Task Export(string path, string ext, string output, CancellationToken cancel = default)
    {
        var soffice = LibreOffice ?? throw new MorphException($"Opening .{FileKinds.Extension(path)} needs LibreOffice (libreoffice.org)");
        var tmp = Output.TemporaryDirectory();
        try
        {
            // Its own profile, so a LibreOffice window the user has open doesn't swallow the job.
            var profile = new Uri(Path.Combine(tmp, "profile")).AbsoluteUri;
            await ExternalTool.Run(soffice, [$"-env:UserInstallation={profile}", "--headless", "--norestore", "--convert-to", ext, "--outdir", tmp, path], cancel);
            var made = Path.Combine(tmp, Path.GetFileNameWithoutExtension(path) + "." + ext);
            if (!File.Exists(made)) throw new MorphException($"LibreOffice couldn't convert {Path.GetFileName(path)}");
            File.Move(made, output);
        }
        finally { try { Directory.Delete(tmp, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    /// Runs `body` on a legacy file's modern counterpart (made in a temporary folder, results still saved next to
    /// the original), or on the file itself.
    public static async Task<string> WithModern(string path, Options options, Func<string, Options, string> body, CancellationToken cancel = default)
    {
        if (!Legacy.TryGetValue(FileKinds.Extension(path), out var ext)) return body(path, options);
        var tmp = Output.TemporaryDirectory();
        try
        {
            var copy = Path.Combine(tmp, Path.GetFileNameWithoutExtension(path) + "." + ext);
            await Export(path, ext, copy, cancel);
            return body(copy, options with { OutputDirectory = options.OutputDirectory ?? Output.FolderOf(path) });
        }
        finally { try { Directory.Delete(tmp, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    /// Slides, sheets and old formats get LibreOffice's PDF where it's installed: the real layout, not just the text.
    public static bool PrefersLibreOfficePdf(string path)
    {
        var ext = FileKinds.Extension(path);
        return (Slides.Contains(ext) || Sheets.Contains(ext) || Legacy.ContainsKey(ext)) && LibreOffice is not null;
    }

    // MARK: Reading

    static XDocument? Part(ZipArchive zip, string name)
    {
        var entry = zip.GetEntry(name);
        if (entry is null) return null;
        using var stream = entry.Open();
        return XDocument.Load(stream);
    }

    /// Text of an element: runs, tabs and breaks, with ODF's space runs expanded.
    static string Text(XElement element)
    {
        var text = new StringBuilder();
        foreach (var node in element.DescendantNodes())
        {
            if (node is XText t && t.Parent?.Name.LocalName is "t" or "p" or "span" or "a" or "h") text.Append(t.Value);
            else if (node is XElement e)
                switch (e.Name.LocalName)
                {
                    case "br" or "line-break": text.Append('\n'); break;
                    case "tab": text.Append('\t'); break;
                    case "s" when e.Name.NamespaceName.Contains("opendocument"): text.Append(' ', (int?)e.Attribute(e.Name.Namespace + "c") ?? 1); break;
                }
        }
        return text.ToString();
    }

    /// Each slide's text under a "Slide n" heading.
    public static List<DocOps.Block> ReadSlides(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        var blocks = new List<DocOps.Block>();
        if (FileKinds.Extension(path) == "odp")
        {
            var content = Part(zip, "content.xml") ?? throw new MorphException("This presentation has no content");
            var pages = content.Descendants().Where(e => e.Name.LocalName == "page").ToList();
            for (var i = 0; i < pages.Count; i++)
            {
                blocks.Add(new DocOps.Block(DocOps.BlockKind.Heading, $"Slide {i + 1}", 1));
                foreach (var p in pages[i].Descendants().Where(e => e.Name.LocalName is "p" or "h" && e.Name.NamespaceName.Contains("text")))
                    if (Text(p) is { } t && t.Trim().Length > 0) blocks.Add(new DocOps.Block(DocOps.BlockKind.Paragraph, t));
            }
            return blocks;
        }
        var slides = zip.Entries
            .Select(e => (e.FullName, Number: e.FullName.StartsWith("ppt/slides/slide") && e.FullName.EndsWith(".xml")
                && int.TryParse(e.FullName[16..^4], out var n) ? n : -1))
            .Where(s => s.Number >= 0).OrderBy(s => s.Number).ToList();
        if (slides.Count == 0) throw new MorphException("This presentation has no slides");
        for (var i = 0; i < slides.Count; i++)
        {
            blocks.Add(new DocOps.Block(DocOps.BlockKind.Heading, $"Slide {i + 1}", 1));
            foreach (var p in Part(zip, slides[i].FullName)!.Descendants().Where(e => e.Name.LocalName == "p" && e.Name.NamespaceName.EndsWith("/main")))
                if (Text(p) is { } t && t.Trim().Length > 0) blocks.Add(new DocOps.Block(DocOps.BlockKind.Paragraph, t));
        }
        return blocks;
    }

    /// Every sheet's cells, in sheet order.
    public static List<(string Name, List<List<string>> Rows)> ReadSheets(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        if (FileKinds.Extension(path) == "ods")
            return OdsSheets(Part(zip, "content.xml") ?? throw new MorphException("This spreadsheet has no content"));
        var shared = Part(zip, "xl/sharedStrings.xml")?.Root?.Elements().Where(e => e.Name.LocalName == "si")
            .Select(si => string.Concat(si.Descendants().Where(e => e.Name.LocalName == "t" && !e.Ancestors().Any(a => a.Name.LocalName == "rPh")).Select(e => e.Value)))
            .ToList() ?? [];
        // Sheet names and order from the workbook, their files from its relationships.
        var targets = Part(zip, "xl/_rels/workbook.xml.rels")?.Root?.Elements()
            .Where(e => e.Attribute("Id") is not null && e.Attribute("Target") is not null)
            .ToDictionary(e => (string)e.Attribute("Id")!, e => (string)e.Attribute("Target")!) ?? [];
        var files = (Part(zip, "xl/workbook.xml")?.Descendants().Where(e => e.Name.LocalName == "sheet") ?? [])
            .Select(s => (Name: (string?)s.Attribute("name") ?? "Sheet", Id: s.Attributes().FirstOrDefault(a => a.Name.LocalName == "id")?.Value))
            .Where(s => s.Id is not null && targets.ContainsKey(s.Id))
            .Select(s => (s.Name, Path: targets[s.Id!] is var t && t.StartsWith('/') ? t[1..] : "xl/" + targets[s.Id!]))
            .ToList();
        if (files.Count == 0)
            files = zip.Entries.Where(e => e.FullName.StartsWith("xl/worksheets/sheet") && e.FullName.EndsWith(".xml"))
                .Select(e => (e.FullName, e.FullName)).Order().ToList();
        return files.Select(f => (f.Name, Part(zip, f.Path))).Where(f => f.Item2 is not null)
            .Select(f => (f.Name, XlsxRows(f.Item2!, shared))).ToList();
    }

    static List<List<string>> XlsxRows(XDocument sheet, List<string> shared)
    {
        var cells = new Dictionary<int, Dictionary<int, string>>();
        var row = 0;
        foreach (var r in sheet.Descendants().Where(e => e.Name.LocalName == "row"))
        {
            row = int.TryParse((string?)r.Attribute("r"), out var n) ? n : row + 1;
            var col = -1;
            foreach (var c in r.Elements().Where(e => e.Name.LocalName == "c"))
            {
                col = Column((string?)c.Attribute("r")) ?? col + 1;
                var type = (string?)c.Attribute("t") ?? "";
                var value = c.Elements().FirstOrDefault(e => e.Name.LocalName == "v")?.Value ?? "";
                var text = type switch
                {
                    "s" => int.TryParse(value, out var i) && i >= 0 && i < shared.Count ? shared[i] : "",
                    "inlineStr" => string.Concat(c.Descendants().Where(e => e.Name.LocalName == "t").Select(e => e.Value)),
                    "b" => value == "1" ? "TRUE" : "FALSE",
                    // shortcut: dates come out as Excel's day numbers (45000), not formatted dates.
                    _ => value,
                };
                if (text.Length > 0) (cells.TryGetValue(row - 1, out var line) ? line : cells[row - 1] = [])[col] = text;
            }
        }
        return Grid(cells);
    }

    static int? Column(string? reference)
    {
        var letters = new string((reference ?? "").TakeWhile(char.IsLetter).ToArray()).ToUpperInvariant();
        return letters.Length == 0 ? null : letters.Aggregate(0, (n, ch) => n * 26 + ch - 'A' + 1) - 1;
    }

    static List<(string Name, List<List<string>> Rows)> OdsSheets(XDocument content)
    {
        var sheets = new List<(string, List<List<string>>)>();
        foreach (var table in content.Descendants().Where(e => e.Name.LocalName == "table" && e.Name.NamespaceName.Contains("table")))
        {
            XName Attr(string n) => table.Name.Namespace + n;
            var cells = new Dictionary<int, Dictionary<int, string>>();
            var row = 0;
            foreach (var r in table.Descendants().Where(e => e.Name.LocalName == "table-row"))
            {
                var rowRepeat = Math.Min((int?)r.Attribute(Attr("number-rows-repeated")) ?? 1, 10_000);
                var col = 0;
                foreach (var c in r.Elements().Where(e => e.Name.LocalName is "table-cell" or "covered-table-cell"))
                {
                    var repeat = Math.Min((int?)c.Attribute(Attr("number-columns-repeated")) ?? 1, 1_000);
                    var text = string.Join("\n", c.Elements().Where(e => e.Name.LocalName == "p").Select(Text));
                    // Repeats are how ODS fills the empty rest of a sheet (a million cells); only filled ones are kept.
                    if (text.Length > 0)
                        for (var i = 0; i < repeat; i++) (cells.TryGetValue(row, out var line) ? line : cells[row] = [])[col + i] = text;
                    col += repeat;
                }
                if (cells.TryGetValue(row, out var filled))
                    for (var i = 1; i < rowRepeat; i++) cells[row + i] = new(filled);
                row += rowRepeat;
            }
            sheets.Add(((string?)table.Attribute(Attr("name")) ?? $"Sheet {sheets.Count + 1}", Grid(cells)));
        }
        return sheets;
    }

    /// Sparse cells to rows, padded to the widest row; empty rows inside the table are kept.
    static List<List<string>> Grid(Dictionary<int, Dictionary<int, string>> cells)
    {
        if (cells.Count == 0) return [];
        var width = cells.Values.Max(r => r.Keys.Max()) + 1;
        return Enumerable.Range(0, cells.Keys.Max() + 1)
            .Select(r => Enumerable.Range(0, width).Select(c => cells.GetValueOrDefault(r)?.GetValueOrDefault(c) ?? "").ToList()).ToList();
    }

    public static List<DocOps.Block> SheetsAsBlocks(List<(string Name, List<List<string>> Rows)> sheets)
    {
        var blocks = new List<DocOps.Block>();
        foreach (var (name, rows) in sheets)
        {
            if (sheets.Count > 1) blocks.Add(new DocOps.Block(DocOps.BlockKind.Heading, name, 2));
            if (rows.Count > 0) blocks.Add(new DocOps.Block(DocOps.BlockKind.Code, string.Join("\n", rows.Select(r => string.Join("\t", r)))));
        }
        return blocks;
    }

    // MARK: Pictures

    public static bool HasPictures(string path) => withPictures.Contains(FileKinds.Extension(path));

    /// Saves the pictures placed in an Office or OpenDocument file into a folder next to it.
    public static string Pictures(string path, Options options)
    {
        using var zip = ZipFile.OpenRead(path);
        var images = zip.Entries
            .Where(e => mediaFolders.Any(e.FullName.StartsWith) && e.Name.Length > 0 && FileKinds.Of(e.Name) == FileKind.Image)
            .OrderBy(e => e.FullName, StringComparer.OrdinalIgnoreCase).ToList();
        if (images.Count == 0) throw new MorphNote($"{Path.GetFileName(path)} has no pictures in it");
        var folder = Output.Folder(path, "pictures", options);
        foreach (var entry in images)
            entry.ExtractToFile(Output.Unique(folder, Path.GetFileNameWithoutExtension(entry.Name), FileKinds.Extension(entry.Name)));
        return folder;
    }
}
