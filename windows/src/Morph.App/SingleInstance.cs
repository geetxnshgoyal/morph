using System.IO;
using System.IO.Pipes;

namespace Morph.App;

/// One Morph per user session. Starting it again ("Open in Morph" on several files starts it once per file, and
/// the Start menu while it already runs) hands the arguments to the running copy over a named pipe and exits.
public sealed class SingleInstance : IDisposable
{
    // Pipe names are machine-wide, so the session is part of it (Local\ already scopes the mutex).
    static readonly string name = $"Morph.App.{Environment.UserName}.{System.Diagnostics.Process.GetCurrentProcess().SessionId}";
    readonly Mutex mutex;
    readonly CancellationTokenSource stop = new();

    public bool IsFirst { get; }

    public SingleInstance()
    {
        mutex = new Mutex(true, $"Local\\{name}", out var created);
        IsFirst = created;
    }

    /// Sends this launch's working folder and arguments to the running copy.
    public static bool Forward(IReadOnlyList<string> args)
    {
        // This launch came from the user (Explorer, the Start menu), so it may hand focus to the running copy.
        Native.AllowSetForegroundWindow(-1);
        try
        {
            using var pipe = new NamedPipeClientStream(".", name, PipeDirection.Out);
            pipe.Connect(3000);
            using var writer = new StreamWriter(pipe);
            writer.WriteLine(Environment.CurrentDirectory);
            foreach (var arg in args) writer.WriteLine(arg);
            return true;
        }
        catch (Exception e) when (e is IOException or TimeoutException or UnauthorizedAccessException) { return false; }
    }

    /// Listens for later launches; `received` gets each one's working folder and arguments on a pool thread.
    public void Listen(Action<string, IReadOnlyList<string>> received)
    {
        Task.Run(async () =>
        {
            while (!stop.IsCancellationRequested)
            {
                try
                {
                    await using var pipe = new NamedPipeServerStream(name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                    await pipe.WaitForConnectionAsync(stop.Token);
                    using var reader = new StreamReader(pipe);
                    var folder = await reader.ReadLineAsync(stop.Token) ?? "";
                    var args = new List<string>();
                    while (await reader.ReadLineAsync(stop.Token) is { } line) args.Add(line);
                    received(folder, args);
                }
                catch (OperationCanceledException) { return; }
                catch (IOException) { }
            }
        });
    }

    public void Dispose()
    {
        stop.Cancel();
        if (IsFirst) mutex.ReleaseMutex();
        mutex.Dispose();
    }
}
