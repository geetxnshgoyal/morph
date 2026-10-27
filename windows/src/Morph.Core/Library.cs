namespace Morph;

/// `File` holds everyday actions on the files themselves (share, copy, move…), which the app supplies;
/// the engine's own library has none.
public enum ActionGroup { Convert, Tool, Recipe, File }

public delegate Task<IReadOnlyList<string>> ActionBody(IReadOnlyList<string> inputs, Options options, CancellationToken cancel);

public sealed class MorphAction
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    /// An SF Symbols-style name shared with the Mac app; each UI maps it to its own icon.
    public required string Symbol { get; init; }
    public required ActionGroup Group { get; init; }
    public required IReadOnlySet<FileKind> Kinds { get; init; }
    /// Called once with every input (merge, zip) rather than once per file.
    public bool CombinesInputs { get; init; }
    public int MinimumInputs { get; init; } = 1;
    /// Hidden when every input already has this extension (no "PNG → PNG").
    public string? TargetExtension { get; init; }
    public Requirement Requires { get; init; }
    /// Extra needs for some kinds only, e.g. stripping a video's metadata needs ffmpeg while a photo's doesn't.
    public IReadOnlyDictionary<FileKind, Requirement>? KindRequires { get; init; }
    public required ActionBody Run { get; init; }

    public bool IsAvailable => Platform.Satisfies(Requires);

    /// Whether "171 KB → 139 KB" is worth showing after this action: true for actions that remake the same
    /// content, false for ones that extract something else (text, codes, snapshots).
    public bool ReportsSize => Group == ActionGroup.Recipe || Id is "tool.compress" or "tool.resize" or "tool.strip-metadata"
        || (Group == ActionGroup.Convert && Id is not ("convert.pdf-text" or "convert.pdf-images"));

    /// Edits that keep an image in its own format and work on its pixels, which an SVG doesn't have.
    bool EditsPixels => Id is "tool.compress" or "tool.strip-metadata" or "tool.redact-faces" or "tool.redact-pii";

    public bool Accepts(IReadOnlyList<string> paths)
    {
        if (paths.Count < MinimumInputs || !IsAvailable) return false;
        if (EditsPixels && paths.Any(VectorOps.IsSvg)) return false;
        foreach (var path in paths)
        {
            var kind = FileKinds.Of(path);
            if (!Kinds.Contains(kind)) return false;
            if (KindRequires is not null && KindRequires.TryGetValue(kind, out var need) && !Platform.Satisfies(need)) return false;
        }
        return TargetExtension is null || !paths.All(p => FileKinds.Extension(p) == TargetExtension);
    }
}

public static class Library
{
    static readonly IReadOnlySet<FileKind> image = Set(FileKind.Image), video = Set(FileKind.Video), pdf = Set(FileKind.Pdf);

    static IReadOnlySet<FileKind> Set(params FileKind[] kinds) => kinds.ToHashSet();

    /// An action that runs once per input.
    static MorphAction One(string id, string title, string symbol, ActionGroup group, IReadOnlySet<FileKind> kinds,
                           Func<string, Options, CancellationToken, Task<string>> body, string? target = null,
                           Requirement requires = Requirement.None, IReadOnlyDictionary<FileKind, Requirement>? kindRequires = null) => new()
    {
        Id = id, Title = title, Symbol = symbol, Group = group, Kinds = kinds, TargetExtension = target,
        Requires = requires, KindRequires = kindRequires,
        Run = async (inputs, options, cancel) =>
        {
            var outputs = new List<string>();
            foreach (var input in inputs) outputs.Add(await body(input, options, cancel));
            return outputs;
        },
    };

    /// An action that takes every input at once and makes one output.
    static MorphAction All(string id, string title, string symbol, ActionGroup group, IReadOnlySet<FileKind> kinds,
                           Func<IReadOnlyList<string>, Options, CancellationToken, Task<string>> body, int minimum = 1) => new()
    {
        Id = id, Title = title, Symbol = symbol, Group = group, Kinds = kinds, CombinesInputs = true, MinimumInputs = minimum,
        Run = async (inputs, options, cancel) => [await body(inputs, options, cancel)],
    };

    static Func<string, Options, CancellationToken, Task<string>> Sync(Func<string, Options, string> body) =>
        (input, options, cancel) => Task.Run(() => body(input, options), cancel);

    static readonly Lazy<IReadOnlyList<MorphAction>> actions = new(Build);

    public static IReadOnlyList<MorphAction> Actions => actions.Value;

    static List<MorphAction> Build()
    {
        var list = new List<MorphAction>();
        var convert = ActionGroup.Convert;
        var tool = ActionGroup.Tool;

        // Images: the common formats, SVG and PDF come first so they share the wheel's first page; rarer formats follow.
        ImageFormat[] common = [ImageFormat.Jpg, ImageFormat.Png, ImageFormat.Heic, ImageFormat.Webp];
        MorphAction Image(ImageFormat f) => One($"convert.{f.Extension()}", f.Extension().ToUpperInvariant(), "photo", convert, image,
            Sync((p, o) => ImageOps.Convert(p, f, o)), target: f.Extension());
        foreach (var format in common.Where(f => f.IsAvailable())) list.Add(Image(format));
        list.Add(One("convert.svg", "SVG", "scribble.variable", convert, image, Sync(VectorOps.Trace), target: "svg"));
        list.Add(All("convert.images-pdf", "PDF", "doc.richtext", convert, image, (p, o, c) => Task.Run(() => PdfOps.FromImages(p, o), c)));
        foreach (var format in Enum.GetValues<ImageFormat>().Where(f => !common.Contains(f) && f.IsAvailable())) list.Add(Image(format));

        // Video
        list.Add(One("convert.video-mp4", "MP4", "film", convert, video, (p, o, c) => MediaOps.ConvertVideo(p, "mp4", o, c), "mp4", Requirement.Media));
        foreach (var ext in new[] { "mov", "webm", "mkv" })
            list.Add(One($"convert.video-{ext}", ext.ToUpperInvariant(), "film", convert, video, (p, o, c) => MediaOps.ConvertVideo(p, ext, o, c), ext, Requirement.FFmpeg));
        list.Add(One("convert.video-gif", "GIF", "sparkles.rectangle.stack", convert, video, MediaOps.ToGif, requires: Requirement.Media));

        // Audio (video inputs give up their soundtrack)
        var audioOrVideo = Set(FileKind.Audio, FileKind.Video);
        foreach (var (ext, requires) in new[] { ("m4a", Requirement.Media), ("wav", Requirement.Media), ("aiff", Requirement.FFmpeg),
                                                ("mp3", Requirement.Media), ("flac", Requirement.Media), ("ogg", Requirement.FFmpeg), ("opus", Requirement.FFmpeg) })
            list.Add(One($"convert.audio-{ext}", ext.ToUpperInvariant(), "waveform", convert, audioOrVideo, (p, o, c) => MediaOps.ConvertAudio(p, ext, o, c), ext, requires));

        // PDF and documents
        list.Add(One("convert.pdf-images", "Images", "photo.on.rectangle", convert, pdf, PdfOps.ToImages, requires: Requirement.Windows));
        list.Add(One("convert.pdf-text", "Text", "text.alignleft", convert, pdf, PdfOps.ToText));
        foreach (var ext in DocOps.OutputFormats)
        {
            var kinds = ext switch
            {
                "pdf" => Set(FileKind.Document, FileKind.Data, FileKind.Subtitle),
                "docx" => Set(FileKind.Document, FileKind.Pdf),
                _ => Set(FileKind.Document),
            };
            list.Add(One($"convert.doc-{ext}", ext.ToUpperInvariant(), "doc.text", convert, kinds, Sync((p, o) => DocOps.Convert(p, ext, o)), ext));
        }
        foreach (var ext in new[] { "srt", "vtt" })
            list.Add(One($"convert.sub-{ext}", ext.ToUpperInvariant(), "captions.bubble", convert, Set(FileKind.Subtitle), Sync((p, o) => DocOps.ConvertSubtitle(p, ext, o)), ext));
        foreach (var ext in new[] { "csv", "tsv", "json" })
            list.Add(One($"convert.data-{ext}", ext.ToUpperInvariant(), "tablecells", convert, Set(FileKind.Data), Sync((p, o) => DocOps.ConvertData(p, ext, o)), ext));

        // Tools
        list.Add(One("tool.compress", "Compress", "arrow.down.right.and.arrow.up.left", tool, Set(FileKind.Image, FileKind.Video, FileKind.Pdf),
            (p, o, c) => FileKinds.Of(p) switch
            {
                FileKind.Video => MediaOps.CompressVideo(p, o, c),
                FileKind.Pdf => Task.Run(() => PdfOps.Compress(p, o), c),
                _ => Task.Run(() => ImageOps.Compress(p, o), c),
            }, kindRequires: new Dictionary<FileKind, Requirement> { [FileKind.Video] = Requirement.Media }));
        list.Add(One("tool.resize", "Resize", "arrow.up.left.and.down.right.magnifyingglass", tool, image, Sync(ImageOps.Resize)));
        list.Add(One("tool.strip-metadata", "Remove Metadata", "eye.slash", tool, Set(FileKind.Image, FileKind.Video, FileKind.Audio),
            (p, o, c) => FileKinds.Of(p) == FileKind.Image ? Task.Run(() => ImageOps.StripMetadata(p, o).Output, c) : MediaOps.StripMetadata(p, o, c),
            kindRequires: new Dictionary<FileKind, Requirement> { [FileKind.Video] = Requirement.FFmpeg, [FileKind.Audio] = Requirement.FFmpeg }));
        list.Add(One("tool.redact-faces", "Blur Faces", "person.crop.circle.badge.xmark", tool, image, VisionOps.RedactFaces, requires: Requirement.Windows));
        list.Add(One("tool.redact-pii", "Hide Personal Info", "eye.trianglebadge.exclamationmark", tool, image, VisionOps.RedactPersonalInfo, requires: Requirement.Windows));
        list.Add(One("tool.ocr", "Extract Text", "text.viewfinder", tool, Set(FileKind.Image, FileKind.Pdf), VisionOps.Ocr, requires: Requirement.Windows));
        list.Add(One("tool.qr", "Read QR", "qrcode.viewfinder", tool, Set(FileKind.Image, FileKind.Pdf), VisionOps.ReadCodes,
            kindRequires: new Dictionary<FileKind, Requirement> { [FileKind.Pdf] = Requirement.Windows }));
        list.Add(All("tool.merge-pdf", "Merge PDFs", "doc.on.doc", tool, pdf, (p, o, c) => Task.Run(() => PdfOps.Merge(p, o), c), minimum: 2));
        list.Add(new MorphAction
        {
            Id = "tool.split-pdf", Title = "Split PDF", Symbol = "scissors", Group = tool, Kinds = pdf,
            Run = (inputs, o, c) => Task.Run(() => (IReadOnlyList<string>)inputs.Select(p => PdfOps.Split(p, o)).ToList(), c),
        });
        list.Add(One("tool.mute", "Mute", "speaker.slash", tool, video, MediaOps.Mute, requires: Requirement.Media));
        list.Add(new MorphAction
        {
            Id = "tool.snapshots", Title = "Snapshots", Symbol = "camera.viewfinder", Group = tool, Kinds = video, Requires = Requirement.Media,
            Run = async (inputs, o, c) =>
            {
                var outputs = new List<string>();
                foreach (var input in inputs) outputs.AddRange(await MediaOps.Snapshots(input, o, c));
                return outputs;
            },
        });
        list.Add(One("tool.normalize", "Normalize Loudness", "speaker.wave.3", tool, audioOrVideo, MediaOps.Normalize, requires: Requirement.FFmpeg));
        list.Add(One("tool.trim-silence", "Trim Silence", "waveform.badge.minus", tool, Set(FileKind.Audio), MediaOps.TrimSilence, requires: Requirement.FFmpeg));
        list.Add(One("tool.waveform-video", "Waveform Video", "waveform.and.magnifyingglass", tool, Set(FileKind.Audio), MediaOps.WaveformVideo, requires: Requirement.FFmpeg));
        list.Add(All("tool.zip", "Zip", "doc.zipper", tool, FileKinds.All, (p, o, c) => Task.Run(() => ArchiveOps.Zip(p, o), c)));
        list.Add(All("tool.tar-gz", "tar.gz", "archivebox", tool, Set(FileKind.Folder), (p, o, c) => ArchiveOps.TarGz(p, o, c)));
        list.Add(One("tool.extract", "Extract", "shippingbox.and.arrow.backward", tool, Set(FileKind.Archive), ArchiveOps.Extract));
        return list;
    }

    public static MorphAction? Action(string id)
    {
        if (Actions.FirstOrDefault(a => a.Id == id) is { } action) return action;
        if (id.StartsWith("recipe.") && RecipeStore.Shared.Recipe(id[7..]) is { } recipe) return recipe.Action;
        return null;
    }

    /// Actions offered for a drop, in display order, recipes included.
    public static IReadOnlyList<MorphAction> ActionsFor(IReadOnlyList<string> paths, ActionGroup? group = null)
    {
        var recipes = RecipeStore.Shared.Recipes.Select(r => r.Action);
        return Actions.Concat(recipes)
            .Where(a => group is null || a.Group == group || (group == ActionGroup.Tool && a.Group == ActionGroup.Recipe))
            .Where(a => a.Accepts(paths))
            .ToList();
    }
}
