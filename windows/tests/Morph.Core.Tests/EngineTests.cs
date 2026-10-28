using System.IO.Compression;
using System.Text.Json;
using ImageMagick;
using UglyToad.PdfPig;

namespace Morph.Tests;

public class SupportTests : Scratch
{
    [Fact]
    public void OutputsNeverCollide()
    {
        var source = Write("notes.txt", "hi");
        var options = new Options();
        var first = Output.For(source, "md", options);
        File.WriteAllText(first, "");
        Assert.Equal(PathOf("notes.md"), first);
        Assert.Equal(PathOf("notes 2.md"), Output.For(source, "md", options));
        Assert.Equal(PathOf("notes 3.md"), Output.For(source, "md", options));
        Assert.Equal(PathOf("notes clean.txt"), Output.For(source, "txt", options, "clean"));
    }

    [Fact]
    public void Kinds()
    {
        Assert.Equal(FileKind.Image, FileKinds.Of("a.HEIC"));
        Assert.Equal(FileKind.Archive, FileKinds.Of("a.tar.gz"));
        Assert.Equal(FileKind.Folder, FileKinds.Of(Dir));
        Assert.Equal(FileKind.Other, FileKinds.Of("a.xyz"));
    }

    [Fact]
    public void Sizes()
    {
        Assert.Equal(500_000, Options.ParseSize("500KB"));
        Assert.Equal(2_500_000, Options.ParseSize("2.5mb"));
        Assert.Equal(1234, Options.ParseSize("1234"));
        Assert.Null(Options.ParseSize("lots"));
    }

    [Fact]
    public void ActionsFitTheFiles()
    {
        var png = Picture("a.png");
        var ids = Library.ActionsFor([png]).Select(a => a.Id).ToList();
        Assert.Contains("convert.jpg", ids);
        Assert.DoesNotContain("convert.png", ids);
        Assert.Contains("tool.compress", ids);
        Assert.Contains("recipe.Web Image", ids);
        Assert.DoesNotContain("tool.merge-pdf", ids);
#if WINDOWS
        Assert.Contains("tool.ocr", ids);
#else
        // Windows-only actions stay hidden off Windows.
        Assert.DoesNotContain("tool.ocr", ids);
#endif
    }

    [Fact]
    public void SizeLimits()
    {
        Assert.Equal("No limit", SizeLimit.Label(0));
        Assert.Equal("200 KB", SizeLimit.Label(200_000));
        Assert.Equal("1 MB", SizeLimit.Label(1_000_000));
        Assert.Equal("1.5 MB", SizeLimit.Label(1_500_000));
        Assert.Equal([20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000, 2_000_000, 5_000_000], SizeLimit.Presets);
        Assert.StartsWith("Compress makes the smallest file", SizeLimit.Detail(0));
        Assert.Contains("under 100 KB as JPG", SizeLimit.Detail(100_000));
    }
}

public class ImageTests : Scratch
{
    [Theory]
    [InlineData(ImageFormat.Jpg)]
    [InlineData(ImageFormat.Webp)]
    [InlineData(ImageFormat.Avif)]
    [InlineData(ImageFormat.Tiff)]
    [InlineData(ImageFormat.Gif)]
    [InlineData(ImageFormat.Bmp)]
    [InlineData(ImageFormat.Heic)]
    public void Converts(ImageFormat format)
    {
        Assert.SkipUnless(format.IsAvailable(), $"{format} isn't writable in this ImageMagick build");
        var png = Picture("photo.png", alpha: true);
        var output = ImageOps.Convert(png, format, new Options());
        Assert.Equal(PathOf($"photo.{format.Extension()}"), output);
        using var image = new MagickImage(output);
        Assert.Equal(640u, image.Width);
    }

    [Fact]
    public void ResizesWithoutUpscaling()
    {
        var big = Picture("big.png", 3000, 2000);
        var output = ImageOps.Resize(big, new Options());
        Assert.Equal(PathOf("big 2048px.png"), output);
        Assert.Equal(2048u, new MagickImageInfo(output).Width);
        var small = Picture("small.png", 300, 200);
        Assert.Equal(PathOf("small 300px.png"), ImageOps.Resize(small, new Options()));
    }

    [Fact]
    public void ResizesToAnExactSizeForForms()
    {
        var photo = Picture("photo.png", 900, 1200);
        var square = ImageOps.Resize(photo, new Options { ExactSize = new PixelSize(600, 600) });
        Assert.Equal(PathOf("photo 600x600.jpg"), square);
        var info = new MagickImageInfo(square);
        Assert.Equal((600u, 600u), (info.Width, info.Height));
        // With a name strip and a size limit it stays exactly the size asked for, under the limit.
        var exam = ImageOps.Resize(photo, new Options { ExactSize = new PixelSize(413, 531), Caption = "Asha Rao", TargetBytes = 50_000 });
        info = new MagickImageInfo(exam);
        Assert.Equal((413u, 531u), (info.Width, info.Height));
        Assert.True(new FileInfo(exam).Length <= 50_000);
        Assert.Equal(new PixelSize(600, 600), PixelSize.Parse("600 x 600"));
        Assert.Null(PixelSize.Parse("big"));
    }

    [Fact]
    public void CompressesUnderATarget()
    {
        var big = Picture("big.jpg", 2400, 1800, edit: i => i.AddNoise(NoiseType.Gaussian));
        var output = ImageOps.Compress(big, new Options { TargetBytes = 150_000 });
        Assert.True(new FileInfo(output).Length <= 150_000);
        Assert.Equal(PathOf("big compressed.jpg"), output);
    }

    [Fact]
    public void SizeLimitMakesAJpgAndSkipsWhatAlreadyFits()
    {
        var png = Picture("screen.png", 1600, 1200, edit: i => i.AddNoise(NoiseType.Gaussian));
        var output = ImageOps.Compress(png, new Options { TargetBytes = 100_000 });
        Assert.Equal(PathOf("screen compressed.jpg"), output);
        Assert.True(new FileInfo(output).Length <= 100_000);

        var small = Picture("small.jpg", 200, 150);
        var note = Assert.Throws<MorphNote>(() => ImageOps.Compress(small, new Options { TargetBytes = 200_000 }));
        Assert.Equal("small.jpg is already under 200 KB", note.Message);
    }

    [Fact]
    public async Task CompressKeepsTheLookAndSaysWhenAFileCantShrink()
    {
        var best = Picture("best.jpg", 1600, 1200, edit: i => i.Quality = 100);
        var compress = Library.Action("tool.compress")!;
        var result = await Runner.Run(compress, [best], new Options { Compression = CompressionLevel.Balanced });
        var output = Assert.Single(result.Outputs);
        Assert.True(new FileInfo(output).Length < new FileInfo(best).Length * 0.95);
        Assert.NotNull(result.SizeSummary);
        Assert.EndsWith("% smaller", result.SizeChange);

        var squeezed = Picture("squeezed.jpg", 1600, 1200, edit: i => i.Quality = 30);
        var again = await Runner.Run(compress, [squeezed], new Options { Compression = CompressionLevel.Light });
        Assert.True(again.Unchanged);
        Assert.Equal("squeezed.jpg is already as small as it can get without losing quality", Assert.Single(again.Notes));
    }

    [Fact]
    public void StripsJpegMetadataLosslesslyAndKeepsOrientation()
    {
        var jpg = Picture("camera.jpg", edit: image =>
        {
            var exif = new ExifProfile();
            exif.SetValue(ExifTag.Make, "Canon");
            exif.SetValue(ExifTag.Model, "EOS");
            exif.SetValue(ExifTag.DateTimeOriginal, "2024:05:01 10:00:00");
            exif.SetValue(ExifTag.GPSLatitudeRef, "N");
            exif.SetValue(ExifTag.Orientation, (ushort)6);
            image.SetProfile(exif);
            // ImageMagick writes the orientation it holds, not the profile's.
            image.Orientation = OrientationType.RightTop;
            image.Comment = "secret";
        });
        var removed = ImageOps.PrivateFields(jpg);
        Assert.Contains("GPS location", removed);
        Assert.Contains("Camera make/model", removed);

        var report = ImageOps.StripMetadata(jpg, new Options());
        Assert.True(report.Lossless);
        Assert.Empty(ImageOps.PrivateFields(report.Output));
        using var clean = new MagickImage(report.Output);
        Assert.Equal(OrientationType.RightTop, clean.Orientation);
        Assert.True(string.IsNullOrEmpty(clean.Comment));
    }

    [Fact]
    public void StripsPngText()
    {
        var png = Picture("shot.png", edit: image => image.SetAttribute("Author", "Someone"));
        Assert.Contains("PNG text", ImageOps.PrivateFields(png));
        var report = ImageOps.StripMetadata(png, new Options());
        Assert.True(report.Lossless);
        Assert.Empty(ImageOps.PrivateFields(report.Output));
    }

    [Fact]
    public void ReadsQrCodes()
    {
        var writer = new ZXing.BarcodeWriterPixelData { Format = ZXing.BarcodeFormat.QR_CODE, Options = new() { Width = 300, Height = 300 } };
        var pixels = writer.Write("https://example.com/morph");
        var settings = new PixelReadSettings((uint)pixels.Width, (uint)pixels.Height, StorageType.Char, PixelMapping.BGRA);
        using (var image = new MagickImage())
        {
            image.ReadPixels(pixels.Pixels, settings);
            image.Write(PathOf("qr.png"));
        }
        Assert.Equal(["https://example.com/morph"], VisionOps.Codes(PathOf("qr.png")).GetAwaiter().GetResult());
    }

    [Fact]
    public void PixelatesBoxes()
    {
        using var image = new MagickImage(Picture("face.png"));
        VisionOps.Redact(image, [new Box(100, 100, 120, 120)], RedactStyle.Solid, 0);
        Assert.Equal(MagickColors.Black, image.GetPixels().GetPixel(150, 150).ToColor());
    }

    [Fact]
    public void FindsPersonalInfoAcrossWords()
    {
        TextLine Line(params string[] words) => new(string.Join(" ", words),
            words.Select((w, i) => (w, new Box(i * 100, 0, 90, 20))).ToList());
        var boxes = VisionOps.SensitiveBoxes([Line("call", "+1", "555", "123", "4567", "today"), Line("mail", "me@example.com"), Line("nothing", "here")]);
        Assert.Equal(2, boxes.Count);
        Assert.Equal(new Box(100, 0, 390, 20), boxes[0]);
        Assert.Equal(new Box(100, 0, 90, 20), boxes[1]);
    }
}

public class PdfTests : Scratch
{
    [Fact]
    public void ImagesMergeAndSplit()
    {
        var a = Picture("a.png");
        var b = Picture("b.jpg", 400, 800);
        var pdf = PdfOps.FromImages([a, b], new Options());
        Assert.Equal(PathOf("Images.pdf"), pdf);
        using (var document = PdfDocument.Open(pdf)) Assert.Equal(2, document.NumberOfPages);

        var merged = PdfOps.Merge([pdf, pdf], new Options());
        using (var document = PdfDocument.Open(merged)) Assert.Equal(4, document.NumberOfPages);

        var folder = PdfOps.Split(merged, new Options());
        Assert.Equal(PathOf("Merged pages"), folder);
        Assert.Equal(4, Directory.GetFiles(folder, "page *.pdf").Length);

        var compressed = PdfOps.Compress(merged, new Options { Compression = CompressionLevel.Strong });
        Assert.True(new FileInfo(compressed).Length < new FileInfo(merged).Length);
    }

    [Fact]
    public async Task TextRoundTrip()
    {
        var md = Write("doc.md", "# Title\n\nHello **there** world.\n\n- one\n- two\n");
        var pdf = DocOps.Convert(md, "pdf", new Options());
        var text = await PdfOps.Text(pdf);
        Assert.Contains("Title", text);
        Assert.Contains("Hello there world.", text);
        Assert.Contains("two", text);
    }

    [Fact]
    public void LongDocumentsPaginate()
    {
        var md = Write("long.md", string.Join("\n\n", Enumerable.Range(1, 120).Select(i => $"Paragraph {i} " + new string('x', 300))));
        var pdf = DocOps.Convert(md, "pdf", new Options());
        using var document = PdfDocument.Open(pdf);
        Assert.True(document.NumberOfPages > 5);
    }
}

public class DocumentTests : Scratch
{
    const string markdown = "# Plan\n\nSome *text* here.\n\n## Steps\n\n- first\n- second\n\n```\ncode line\n```\n\n> quoted\n";

    [Theory]
    [InlineData("docx")]
    [InlineData("odt")]
    [InlineData("rtf")]
    [InlineData("html")]
    [InlineData("txt")]
    public void RoundTripsThroughEachFormat(string ext)
    {
        var md = Write("plan.md", markdown);
        var converted = DocOps.Convert(md, ext, new Options());
        Assert.Equal(PathOf($"plan.{ext}"), converted);
        var back = DocOps.Read(converted);
        var text = string.Join("\n", back.Select(b => b.Text));
        Assert.Contains("Plan", text);
        Assert.Contains("Some text here.", text);
        Assert.Contains("second", text);
        Assert.Contains("code line", text);
        if (ext is "docx" or "odt" or "html")
        {
            Assert.Equal(new DocOps.Block(DocOps.BlockKind.Heading, "Plan", 1), back[0]);
            Assert.Contains(back, b => b.Kind == DocOps.BlockKind.Bullet && b.Text == "first");
        }
    }

    [Fact]
    public void DocxOpensAsAPackage()
    {
        var docx = DocOps.Convert(Write("plan.md", markdown), "docx", new Options());
        using var zip = ZipFile.OpenRead(docx);
        Assert.NotNull(zip.GetEntry("word/document.xml"));
        Assert.NotNull(zip.GetEntry("word/styles.xml"));
    }

    [Fact]
    public void ReadsRtf()
    {
        var rtf = Write("note.rtf", @"{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0 Hello \b world\b0 .\par Caf\'e9 \u8364? done\par}");
        Assert.Equal("Hello world.\n\nCafé € done", DocOps.RtfText(File.ReadAllText(rtf)));
    }

    [Fact]
    public void Subtitles()
    {
        var srt = Write("talk.srt", "1\n00:00:01,500 --> 00:00:03,000\nHello\n\n2\n00:00:04,000 --> 00:00:05,250\nWorld\n");
        var vtt = DocOps.ConvertSubtitle(srt, "vtt", new Options());
        Assert.Equal("WEBVTT\n\n00:00:01.500 --> 00:00:03.000\nHello\n\n00:00:04.000 --> 00:00:05.250\nWorld\n", File.ReadAllText(vtt));
        var back = DocOps.ConvertSubtitle(vtt, "srt", new Options());
        Assert.Equal(File.ReadAllText(srt), File.ReadAllText(back));
    }

    [Fact]
    public void DataTables()
    {
        var csv = Write("people.csv", "name,city\n\"Lee, Ann\",Paris\nBo,\"New \"\"York\"\"\"\n");
        var json = DocOps.ConvertData(csv, "json", new Options());
        using var parsed = JsonDocument.Parse(File.ReadAllText(json));
        Assert.Equal("Lee, Ann", parsed.RootElement[0].GetProperty("name").GetString());
        Assert.Equal("New \"York\"", parsed.RootElement[1].GetProperty("city").GetString());
        var tsv = DocOps.ConvertData(json, "tsv", new Options());
        Assert.Equal("city\tname\nParis\tLee, Ann\n\"New \"\"York\"\"\"\tBo\n", File.ReadAllText(tsv));
    }
}

public class ArchiveTests : Scratch
{
    string Folder()
    {
        var folder = PathOf("Project");
        Directory.CreateDirectory(System.IO.Path.Combine(folder, "sub"));
        File.WriteAllText(System.IO.Path.Combine(folder, "a.txt"), "a");
        File.WriteAllText(System.IO.Path.Combine(folder, "sub", "b.txt"), "b");
        return folder;
    }

    [Fact]
    public async Task ZipsAndExtracts()
    {
        var zip = ArchiveOps.Zip([Folder()], new Options());
        Assert.Equal(PathOf("Project.zip"), zip);
        var extracted = await ArchiveOps.Extract(zip, new Options(), default);
        Assert.Equal(PathOf("Project 2"), extracted);
        Assert.Equal("b", File.ReadAllText(System.IO.Path.Combine(extracted, "Project", "sub", "b.txt")));
    }

    [Fact]
    public async Task TarGzRoundTrip()
    {
        var tar = await ArchiveOps.TarGz([Folder()], new Options(), default);
        Assert.Equal(PathOf("Project.tar.gz"), tar);
        var extracted = await ArchiveOps.Extract(tar, new Options(), default);
        Assert.Equal("a", File.ReadAllText(System.IO.Path.Combine(extracted, "Project", "a.txt")));
    }

    [Fact]
    public void LooseFilesSitAtTheRoot()
    {
        var a = Write("one.txt", "1");
        var b = Write("two.txt", "2");
        using var zip = ZipFile.OpenRead(ArchiveOps.Zip([a, b], new Options()));
        Assert.Equal(["one.txt", "two.txt"], zip.Entries.Select(e => e.FullName).Order());
    }
}

public class RunnerTests : Scratch
{
    [Fact]
    public async Task RecipesChainStepsAndUndoRecycles()
    {
        var big = Picture("hero.png", 3200, 2000);
        var recipe = Library.Action("recipe.Web Image")!;
        var result = await Runner.Run(recipe, [big]);
        Assert.Empty(result.Failures);
        var output = Assert.Single(result.Outputs);
        Assert.Equal(Dir, System.IO.Path.GetDirectoryName(output));
        Assert.Equal(1600u, new MagickImageInfo(output).Width);

        var entry = History.Shared.Entries.Last();
        Assert.Equal("Web Image", entry.Title);
        History.Shared.Undo(entry.Id);
        Assert.False(File.Exists(output));
        Assert.True(File.Exists(big));
        Assert.True(History.Shared.Entries.Single(e => e.Id == entry.Id).Undone);
    }

    [Fact]
    public async Task FailuresAreReportedPerFile()
    {
        var good = Picture("good.png");
        var bad = Write("bad.png", "not an image");
        var result = await Runner.Run(Library.Action("convert.jpg")!, [good, bad]);
        Assert.Single(result.Outputs);
        Assert.StartsWith("bad.png: ", Assert.Single(result.Failures));
    }

    [Fact]
    public void UserRecipesPersist()
    {
        RecipeStore.Shared.Save(new Recipe { Name = "Tiny", Steps = [new("tool.resize", MaxPixel: 64)] });
        RecipeStore.Shared.Reload();
        Assert.NotNull(Library.Action("recipe.tiny"));
        RecipeStore.Shared.Delete("Tiny");
        Assert.Null(Library.Action("recipe.Tiny"));
    }
}

/// Uses ffmpeg when it's installed (it is on the Mac this was built on); skipped otherwise.
public class MediaTests : Scratch
{
    async Task<string> Clip()
    {
        Assert.SkipWhen(ExternalTool.FFmpeg is null, "ffmpeg isn't installed");
        var path = PathOf("clip.mp4");
        await ExternalTool.FFmpegRun(["-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-metadata", "title=Secret", "-shortest", path]);
        return path;
    }

    [Fact]
    public async Task VideoConversions()
    {
        var clip = await Clip();
        var webm = await MediaOps.ConvertVideo(clip, "webm", new Options(), default);
        Assert.True(new FileInfo(webm).Length > 0);
        var gif = await MediaOps.ToGif(clip, new Options(), default);
        Assert.True(new MagickImageCollection(gif).Count > 10);
        var mp3 = await MediaOps.ConvertAudio(clip, "mp3", new Options(), default);
        Assert.InRange(await MediaOps.Duration(mp3), 1.5, 2.5);
        var frames = Assert.Single(await MediaOps.Snapshots(clip, new Options(), default));
        Assert.Equal(6, Directory.GetFiles(frames, "*.jpg").Length);
        var muted = await MediaOps.Mute(clip, new Options(), default);
        Assert.DoesNotContain("Audio", (await MediaOps.Summary(muted)).Keys);
        var compressed = await MediaOps.CompressVideo(clip, new Options(), default);
        Assert.Equal(PathOf("clip compressed.mp4"), compressed);
    }

    [Fact]
    public async Task StripsMediaMetadata()
    {
        var clip = await Clip();
        var clean = await MediaOps.StripMetadata(clip, new Options(), default);
        var tags = await ExternalTool.Run(ExternalTool.FFprobe!, ["-v", "error", "-show_entries", "format_tags", "-of", "json", clean]);
        Assert.DoesNotContain("Secret", tags);
    }
}

#if WINDOWS
/// Windows' own PDF renderer and text recognition, which only exist in the Windows build of the engine.
public class WindowsTests : Scratch
{
    [Fact]
    public async Task RendersPdfPagesToImages()
    {
        var pdf = DocOps.Convert(Write("doc.md", "# Pages\n\nOne page of text."), "pdf", new Options());
        var folder = await PdfOps.ToImages(pdf, new Options(), TestContext.Current.CancellationToken);
        var page = Assert.Single(Directory.GetFiles(folder));
        Assert.True(new MagickImageInfo(page).Width > 600);
    }

    [Fact]
    public async Task ReadsTextInPictures()
    {
        Assert.SkipUnless(Windows.Media.Ocr.OcrEngine.TryCreateFromUserProfileLanguages() is not null, "no OCR language is installed");
        var picture = Picture("sign.png", 900, 240, edit: image =>
        {
            image.Draw(new ImageMagick.Drawing.Drawables().FillColor(MagickColors.White).Rectangle(0, 0, 900, 240));
            image.Draw(new ImageMagick.Drawing.Drawables().FontPointSize(72).FillColor(MagickColors.Black).Text(40, 150, "Hello Morph"));
        });
        var text = await VisionOps.RecognizeText(new MagickImage(picture), TestContext.Current.CancellationToken);
        Assert.Contains("Morph", text);
    }
}
#endif
