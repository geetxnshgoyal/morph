using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Morph;

public sealed class MorphException(string message) : Exception(message);

/// Not a failure: the file was left alone on purpose (say, it's already as small as it can get without losing
/// quality). Runner reports it as a note rather than an error.
public sealed class MorphNote(string message) : Exception(message);

public enum FileKind { Image, Video, Audio, Pdf, Document, Subtitle, Data, Archive, Folder, Other }

public static class FileKinds
{
    public static readonly IReadOnlySet<FileKind> All = Enum.GetValues<FileKind>().ToHashSet();

    static readonly Dictionary<string, FileKind> byExtension = Build(
        (FileKind.Image, "jpg jpeg jpe jfif png heic heif webp avif tif tiff gif bmp dib ico jxl svg dng cr2 cr3 nef arw raf orf rw2"),
        (FileKind.Video, "mp4 m4v mov avi mkv webm wmv flv mpg mpeg 3gp ts mts m2ts ogv"),
        (FileKind.Audio, "mp3 m4a aac wav aif aiff flac ogg oga opus wma caf amr"),
        (FileKind.Pdf, "pdf"),
        (FileKind.Subtitle, "srt vtt"),
        (FileKind.Data, "csv tsv json"),
        (FileKind.Document, "md markdown docx odt rtf html htm txt text log xml yaml yml ini cfg conf"),
        (FileKind.Archive, "zip tar gz tgz rar 7z xz txz bz2 tbz2"));

    static Dictionary<string, FileKind> Build(params (FileKind kind, string extensions)[] table)
    {
        var map = new Dictionary<string, FileKind>(StringComparer.OrdinalIgnoreCase);
        foreach (var (kind, extensions) in table)
            foreach (var ext in extensions.Split(' ')) map[ext] = kind;
        return map;
    }

    public static FileKind Of(string path)
    {
        if (Directory.Exists(path)) return FileKind.Folder;
        return byExtension.TryGetValue(Extension(path), out var kind) ? kind : FileKind.Other;
    }

    /// Lower-case extension without the dot: "photo.HEIC" → "heic".
    public static string Extension(string path) => Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
}

public enum CompressionLevel { Light, Balanced, Strong }

public static class CompressionLevels
{
    public static double ImageQuality(this CompressionLevel level) => level switch
    {
        CompressionLevel.Light => 0.85,
        CompressionLevel.Balanced => 0.7,
        _ => 0.5,
    };

    /// How close a compressed image must stay to the original (SSIM on luminance, 1 = identical). Light is
    /// indistinguishable, balanced looks the same side by side, strong may soften on a close look.
    public static double MinimumSimilarity(this CompressionLevel level) => level switch
    {
        CompressionLevel.Light => 0.995,
        CompressionLevel.Balanced => 0.985,
        _ => 0.97,
    };

    public static string Label(this CompressionLevel level) => level.ToString();

    public static string Detail(this CompressionLevel level) => level switch
    {
        CompressionLevel.Light => "Looks identical, smaller savings.",
        CompressionLevel.Balanced => "Looks the same side by side, much smaller.",
        _ => "Smallest files; a close look may show softening.",
    };
}

/// Size limits the apps offer for Compress, for upload forms that cap a file's size (often 20 KB to 2 MB).
/// 0 means no limit. Sizes are decimal, so "200 KB" also fits a 200 KiB cap.
public static class SizeLimit
{
    public static readonly IReadOnlyList<long> Presets = [20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000, 2_000_000, 5_000_000];

    /// The smallest custom limit Settings accepts; below this even a thumbnail won't fit.
    public const long Minimum = 5_000;

    public static string Label(long bytes) => bytes <= 0 ? "No limit" : Bytes.Format(bytes);

    /// What Compress does with this limit, for the Settings screens.
    public static string Detail(long bytes) => bytes <= 0
        ? "Compress makes the smallest file that still looks the same. Set a limit for upload forms that cap file size."
        : $"Compress fits photos under {Label(bytes)} as JPG, at the best quality that fits, ready for upload forms.";
}

public static class Bytes
{
    /// "171 KB", "1.5 MB": decimal units, as Explorer's size column and upload forms count them.
    public static string Format(long bytes) => bytes switch
    {
        >= 1_000_000_000 => $"{bytes / 1e9:0.#} GB",
        >= 1_000_000 => $"{bytes / 1e6:0.#} MB",
        >= 1_000 => $"{bytes / 1e3:0} KB",
        _ => $"{bytes} bytes",
    };

    public static long Of(string path)
    {
        try { return File.Exists(path) ? new FileInfo(path).Length : 0; }
        catch (IOException) { return 0; }
        catch (UnauthorizedAccessException) { return 0; }
    }
}

public enum RedactStyle { Pixelate, Solid }

/// An exact width × height in pixels, for forms that ask for one ("600 × 600", "413 × 531").
public sealed record PixelSize(int Width, int Height)
{
    public string Label => $"{Width} × {Height}";
    public string Key => $"{Width}x{Height}";

    /// Parses "600x600", "600 × 600" or "600*600".
    public static PixelSize? Parse(string? text)
    {
        var parts = (text ?? "").ToLowerInvariant().Split(['x', '×', '*', ' ', ','], StringSplitOptions.RemoveEmptyEntries);
        return parts.Length == 2 && int.TryParse(parts[0], out var w) && int.TryParse(parts[1], out var h)
            && w is >= 16 and <= 8000 && h is >= 16 and <= 8000 ? new PixelSize(w, h) : null;
    }

    /// Sizes people are asked for most, grouped for a menu. Millimetre sizes are at 300 dpi.
    public static readonly (string Group, (string Name, PixelSize Size)[] Items)[] Presets =
    [
        ("Passport and visa", [("US or India, 2 × 2 in", new(600, 600)), ("Schengen, UK, 35 × 45 mm", new(413, 531)), ("China visa, 33 × 48 mm", new(354, 472))]),
        ("Exams", [("Exam photo, 3.5 × 4.5 cm", new(413, 531)), ("Bank exams photo", new(200, 230))]),
        ("Signature", [("Signature, small", new(140, 60)), ("Signature, large", new(280, 120))]),
        ("Social and web", [("Square post", new(1080, 1080)), ("Portrait post", new(1080, 1350)), ("Story", new(1080, 1920)),
                            ("Full HD", new(1920, 1080)), ("HD", new(1280, 720)), ("Profile picture", new(400, 400))]),
    ];
}

/// Knobs shared by every action. Unset values fall back to sensible per-action defaults.
public sealed record Options
{
    public double? Quality { get; init; }
    public CompressionLevel Compression { get; init; } = CompressionLevel.Balanced;
    public int? MaxPixel { get; init; }
    public long? TargetBytes { get; init; }
    public RedactStyle RedactStyle { get; init; } = RedactStyle.Pixelate;
    /// null saves results next to each original.
    public string? OutputDirectory { get; init; }
    /// Palette size when tracing an image into an SVG; null picks one from `Compression`.
    public int? Colors { get; init; }
    /// Exact size for Resize, cropped to fill: what passport, visa and exam forms ask for.
    public PixelSize? ExactSize { get; init; }
    /// Printed with the date the photo was taken in a white strip under it, for exam forms.
    public string? Caption { get; init; }

    /// Parses "500KB", "2.5mb", "1g", or plain bytes.
    public static long? ParseSize(string text)
    {
        var s = text.Trim().ToLowerInvariant();
        (string suffix, double factor)[] units = [("gb", 1e9), ("g", 1e9), ("mb", 1e6), ("m", 1e6), ("kb", 1e3), ("k", 1e3), ("b", 1)];
        foreach (var (suffix, factor) in units)
        {
            if (!s.EndsWith(suffix)) continue;
            return double.TryParse(s[..^suffix.Length].Trim(), System.Globalization.CultureInfo.InvariantCulture, out var v)
                ? (long)(v * factor) : null;
        }
        return long.TryParse(s, out var bytes) ? bytes : null;
    }
}

/// Picks non-colliding output paths next to the source (originals are never overwritten).
public static class Output
{
    static readonly Lock gate = new();
    static readonly HashSet<string> reserved = new(StringComparer.OrdinalIgnoreCase);

    public static string For(string source, string ext, Options options, string? suffix = null)
    {
        var name = Path.GetFileNameWithoutExtension(Path.TrimEndingDirectorySeparator(source)) + (suffix is null ? "" : " " + suffix);
        return Unique(options.OutputDirectory ?? FolderOf(source), name, ext);
    }

    public static string FolderOf(string path) => Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(path)))!;

    /// "name.ext", or "name 2.ext", "name 3.ext"… if taken. An empty `ext` names a folder.
    public static string Unique(string folder, string name, string ext)
    {
        lock (gate)
        {
            string Make(string n) => Path.Combine(folder, ext.Length == 0 ? n : $"{n}.{ext}");
            var candidate = Make(name);
            for (var i = 2; File.Exists(candidate) || Directory.Exists(candidate) || reserved.Contains(candidate); i++)
                candidate = Make($"{name} {i}");
            reserved.Add(candidate);
            return candidate;
        }
    }

    public static string Folder(string source, string suffix, Options options)
    {
        var dir = For(source, "", options, suffix);
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string TemporaryDirectory()
    {
        var dir = Path.Combine(Path.GetTempPath(), "morph-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }
}

public static class Paths
{
    /// %LOCALAPPDATA%\Morph on Windows. MORPH_HOME overrides it (the tests use a scratch folder).
    public static string Support
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("MORPH_HOME") is { Length: > 0 } home
                ? home
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Morph");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }
}

/// What an action needs beyond Morph itself, least to most demanding (a recipe needs the most any step needs).
public enum Requirement
{
    None,
    /// ffmpeg, or Windows' own Media Foundation encoders.
    Media,
    /// Windows 10 1809 or later (OCR, face detection, PDF rendering).
    Windows,
    /// ffmpeg on the PATH or in a usual install location.
    FFmpeg,
}

public static class Platform
{
#if WINDOWS
    public static bool HasWindowsApis => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763);
#else
    public static bool HasWindowsApis => false;
#endif

    public static bool Satisfies(Requirement requirement) => requirement switch
    {
        Requirement.FFmpeg => ExternalTool.FFmpeg is not null,
        Requirement.Media => ExternalTool.FFmpeg is not null || HasWindowsApis,
        Requirement.Windows => HasWindowsApis,
        _ => true,
    };
}

public static class ExternalTool
{
    static string? cachedFFmpeg;
    static DateTime checkedAt = DateTime.MinValue;

    /// Where ffmpeg was found; looked up again at most every few seconds, so a fresh install shows up without a relaunch.
    public static string? FFmpeg
    {
        get
        {
            if (DateTime.UtcNow - checkedAt > TimeSpan.FromSeconds(4))
            {
                cachedFFmpeg = Find("ffmpeg");
                checkedAt = DateTime.UtcNow;
            }
            return cachedFFmpeg;
        }
    }

    public static string? FFprobe => FFmpeg is { } ffmpeg && Path.GetDirectoryName(ffmpeg) is { } dir
        && File.Exists(Path.Combine(dir, Exe("ffprobe"))) ? Path.Combine(dir, Exe("ffprobe")) : Find("ffprobe");

    public static void Refresh() => checkedAt = DateTime.MinValue;

    public static string InstallHint => OperatingSystem.IsWindows() ? "winget install Gyan.FFmpeg" : "brew install ffmpeg";

    static string Exe(string name) => OperatingSystem.IsWindows() ? name + ".exe" : name;

    public static string? Find(string name)
    {
        var exe = Exe(name);
        foreach (var dir in SearchDirectories())
        {
            try
            {
                var candidate = Path.Combine(dir, exe);
                if (File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException) { }
        }
        return OperatingSystem.IsWindows() ? FindInWinGetPackages(exe) : null;
    }

    static IEnumerable<string> SearchDirectories()
    {
        // Beside Morph itself, so ffmpeg.exe can simply be dropped into the install folder.
        yield return AppContext.BaseDirectory;
        foreach (var dir in CurrentPath()) yield return dir;
        if (OperatingSystem.IsWindows())
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            yield return Path.Combine(local, @"Microsoft\WinGet\Links");
            yield return Path.Combine(profile, @"scoop\shims");
            yield return @"C:\ProgramData\chocolatey\bin";
            yield return Path.Combine(programFiles, @"ffmpeg\bin");
            yield return @"C:\ffmpeg\bin";
        }
        else
        {
            yield return "/opt/homebrew/bin";
            yield return "/usr/local/bin";
            yield return "/usr/bin";
        }
    }

    /// The PATH as it is now: on Windows the saved user and machine values, since this process's copy goes stale
    /// when an installer adds to it.
    static IEnumerable<string> CurrentPath()
    {
        var parts = new List<string?> { Environment.GetEnvironmentVariable("PATH") };
        if (OperatingSystem.IsWindows())
        {
            parts.Add(Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User));
            parts.Add(Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine));
        }
        return parts.Where(p => p is not null)
            .SelectMany(p => p!.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            .Select(Environment.ExpandEnvironmentVariables)
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    /// winget's portable ffmpeg builds unpack under Packages\Gyan.FFmpeg_…\ffmpeg-…\bin.
    static string? FindInWinGetPackages(string exe)
    {
        var packages = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WinGet\Packages");
        if (!Directory.Exists(packages)) return null;
        try
        {
            return Directory.EnumerateDirectories(packages, "*FFmpeg*")
                .SelectMany(d => Directory.EnumerateFiles(d, exe, SearchOption.AllDirectories))
                .FirstOrDefault();
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// Runs a tool to completion and returns its standard output; a non-zero exit throws with the tail of stderr.
    public static async Task<string> Run(string tool, IEnumerable<string> args, CancellationToken cancel = default)
    {
        var info = new ProcessStartInfo(tool)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var arg in args) info.ArgumentList.Add(arg);
        using var process = Process.Start(info) ?? throw new MorphException($"Couldn't start {Path.GetFileName(tool)}");
        // Drain both pipes at once so a chatty tool can't block on a full buffer.
        var stdout = process.StandardOutput.ReadToEndAsync(cancel);
        var stderr = process.StandardError.ReadToEndAsync(cancel);
        try { await process.WaitForExitAsync(cancel); }
        catch (OperationCanceledException) { try { process.Kill(true); } catch (InvalidOperationException) { } throw; }
        var output = await stdout;
        var errors = await stderr;
        if (process.ExitCode != 0)
        {
            var tail = string.Join(" ", errors.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).TakeLast(3));
            throw new MorphException($"{Path.GetFileNameWithoutExtension(tool)} failed: {(tail.Length > 0 ? tail : $"exit {process.ExitCode}")}");
        }
        return output;
    }

    public static string RequireFFmpeg() =>
        FFmpeg ?? throw new MorphException($"This needs ffmpeg. Install it with: {InstallHint}");

    public static Task<string> FFmpegRun(IEnumerable<string> args, CancellationToken cancel = default) =>
        Run(RequireFFmpeg(), ["-hide_banner", "-loglevel", "error", "-y", .. args], cancel);
}

/// Moves files to the Recycle Bin (the Trash elsewhere), so undo is itself undoable.
public static class Trash
{
    /// Lets the tests watch what would be recycled without filling the real Recycle Bin or Trash.
    internal static Action<string>? Override;

    public static void Move(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path)) return;
        if (Override is not null) { Override(path); return; }
        if (OperatingSystem.IsWindows()) { Recycle(path); return; }
        var trash = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".Trash");
        if (Directory.Exists(trash))
        {
            var name = Path.GetFileName(Path.TrimEndingDirectorySeparator(path));
            var target = Output.Unique(trash, Path.GetFileNameWithoutExtension(name), FileKinds.Extension(name));
            if (Directory.Exists(path)) Directory.Move(path, target); else File.Move(path, target);
        }
        else if (Directory.Exists(path)) Directory.Delete(path, true);
        else File.Delete(path);
    }

    static void Recycle(string path)
    {
        var op = new ShFileOpStruct
        {
            wFunc = FO_DELETE,
            pFrom = Path.GetFullPath(path) + "\0\0",
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT,
        };
        var result = SHFileOperationW(ref op);
        if (result != 0 || op.fAnyOperationsAborted)
            throw new MorphException($"Couldn't move {Path.GetFileName(path)} to the Recycle Bin (error {result})");
    }

    const uint FO_DELETE = 3;
    const ushort FOF_SILENT = 0x4, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40, FOF_NOERRORUI = 0x400;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ShFileOpStruct
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperationW(ref ShFileOpStruct op);
}
