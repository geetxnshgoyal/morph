using System.Formats.Tar;
using System.IO.Compression;

namespace Morph;

public static class ArchiveOps
{
    /// One folder zips with its name as the top level; loose files and several items sit at the archive's root.
    public static string Zip(IReadOnlyList<string> paths, Options options)
    {
        if (paths.Count == 0) throw new MorphException("Nothing to zip");
        var first = Path.TrimEndingDirectorySeparator(paths[0]);
        var name = paths.Count == 1 ? Path.GetFileNameWithoutExtension(first) : "Archive";
        var output = Output.Unique(options.OutputDirectory ?? Output.FolderOf(first), name, "zip");
        if (paths.Count == 1 && Directory.Exists(first))
        {
            ZipFile.CreateFromDirectory(first, output, System.IO.Compression.CompressionLevel.Optimal, includeBaseDirectory: true);
            return output;
        }
        using var zip = ZipFile.Open(output, ZipArchiveMode.Create);
        foreach (var path in paths.Select(Path.TrimEndingDirectorySeparator))
        {
            if (File.Exists(path)) { zip.CreateEntryFromFile(path, Path.GetFileName(path), System.IO.Compression.CompressionLevel.Optimal); continue; }
            var root = Path.GetDirectoryName(path)!;
            foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
                zip.CreateEntryFromFile(file, Path.GetRelativePath(root, file).Replace('\\', '/'), System.IO.Compression.CompressionLevel.Optimal);
        }
        return output;
    }

    public static async Task<string> TarGz(IReadOnlyList<string> paths, Options options, CancellationToken cancel)
    {
        if (paths.Count == 0) throw new MorphException("Nothing to archive");
        var first = Path.TrimEndingDirectorySeparator(paths[0]);
        var name = paths.Count == 1 ? Path.GetFileName(first) : "Archive";
        var output = Output.Unique(options.OutputDirectory ?? Output.FolderOf(first), name, "tar.gz");
        await using var file = File.Create(output);
        await using var gzip = new GZipStream(file, System.IO.Compression.CompressionLevel.Optimal);
        await using var tar = new TarWriter(gzip, TarEntryFormat.Pax);
        foreach (var folder in paths.Select(Path.TrimEndingDirectorySeparator))
        {
            var root = Path.GetDirectoryName(folder)!;
            await tar.WriteEntryAsync(folder, Path.GetFileName(folder) + "/", cancel);
            foreach (var entry in Directory.EnumerateFileSystemEntries(folder, "*", SearchOption.AllDirectories))
            {
                var entryName = Path.GetRelativePath(root, entry).Replace('\\', '/') + (Directory.Exists(entry) ? "/" : "");
                await tar.WriteEntryAsync(entry, entryName, cancel);
            }
        }
        return output;
    }

    /// zip, tar and tar.gz are read here; 7z, rar, xz and bz2 go to the system's tar (bsdtar ships with Windows).
    public static async Task<string> Extract(string path, Options options, CancellationToken cancel)
    {
        var name = Path.GetFileNameWithoutExtension(path);
        if (name.EndsWith(".tar", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
        var folder = Output.Unique(options.OutputDirectory ?? Output.FolderOf(path), name, "");
        Directory.CreateDirectory(folder);
        try
        {
            var ext = FileKinds.Extension(path);
            var isTarGz = ext == "tgz" || ext == "gz" && path.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase);
            switch (ext)
            {
                case "zip":
                    // Entries that would land outside the folder are refused by ZipFile itself.
                    await Task.Run(() => ZipFile.ExtractToDirectory(path, folder), cancel);
                    break;
                case "tar":
                    await TarFile.ExtractToDirectoryAsync(path, folder, overwriteFiles: false, cancel);
                    break;
                case "gz" or "tgz" when isTarGz:
                    await using (var file = File.OpenRead(path))
                    await using (var gzip = new GZipStream(file, CompressionMode.Decompress))
                        await TarFile.ExtractToDirectoryAsync(gzip, folder, overwriteFiles: false, cancel);
                    break;
                case "gz":
                    await using (var file = File.OpenRead(path))
                    await using (var gzip = new GZipStream(file, CompressionMode.Decompress))
                    await using (var target = File.Create(Path.Combine(folder, Path.GetFileNameWithoutExtension(path))))
                        await gzip.CopyToAsync(target, cancel);
                    break;
                default:
                    var tar = OperatingSystem.IsWindows() ? Path.Combine(Environment.SystemDirectory, "tar.exe") : "/usr/bin/tar";
                    if (!File.Exists(tar)) throw new MorphException($"Opening .{ext} archives needs tar, which this system lacks");
                    await ExternalTool.Run(tar, ["-xf", path, "-C", folder], cancel);
                    break;
            }
            return folder;
        }
        catch
        {
            try { Directory.Delete(folder, true); } catch (IOException) { }
            throw;
        }
    }
}
