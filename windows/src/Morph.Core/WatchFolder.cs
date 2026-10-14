namespace Morph;

/// Runs an action on every file that lands in a folder, writing results to a "Morphed" folder inside it.
public sealed class WatchFolder(string folder, string actionId) : IDisposable
{
    FileSystemWatcher? watcher;
    readonly HashSet<string> pending = new(StringComparer.OrdinalIgnoreCase);
    readonly Lock gate = new();

    public event Action<string, RunResult>? Result;

    public string OutputFolder => Path.Combine(folder, "Morphed");

    public void Start()
    {
        if (!Directory.Exists(folder)) throw new MorphException($"No such folder: {folder}");
        Directory.CreateDirectory(OutputFolder);
        watcher = new FileSystemWatcher(folder) { IncludeSubdirectories = false, EnableRaisingEvents = true };
        watcher.Created += (_, e) => Queue(e.FullPath);
        watcher.Renamed += (_, e) => Queue(e.FullPath);
    }

    static bool IsPartial(string path)
    {
        var name = Path.GetFileName(path);
        return name.StartsWith('.') || name.StartsWith("~$") ||
               FileKinds.Extension(path) is "tmp" or "part" or "crdownload" or "download" or "partial";
    }

    void Queue(string path)
    {
        if (IsPartial(path) || Directory.Exists(path)) return;
        lock (gate) { if (!pending.Add(path)) return; }
        _ = Task.Run(async () =>
        {
            try
            {
                // Wait until the file stops growing, so copies and downloads are complete.
                long last = -1;
                while (File.Exists(path))
                {
                    var size = new FileInfo(path).Length;
                    if (size == last && size > 0) break;
                    last = size;
                    await Task.Delay(1000);
                }
                if (!File.Exists(path) || Library.Action(actionId) is not { } action || !action.Accepts([path])) return;
                var result = await Runner.Run(action, [path], new Options { OutputDirectory = OutputFolder });
                Result?.Invoke(path, result);
            }
            finally
            {
                lock (gate) pending.Remove(path);
            }
        });
    }

    public void Dispose() => watcher?.Dispose();
}
