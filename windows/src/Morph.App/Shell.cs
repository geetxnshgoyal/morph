using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Win32;

namespace Morph.App;

/// File Explorer and the rest of Windows: showing results, opening links and settings pages, and whether Morph
/// runs from its MSIX package (Store) or the installer.
public static partial class Shell
{
    /// Opens File Explorer with the files selected (each folder's files in one window).
    public static void Reveal(IEnumerable<string> paths)
    {
        foreach (var group in paths.Where(p => File.Exists(p) || Directory.Exists(p)).GroupBy(Output.FolderOf, StringComparer.OrdinalIgnoreCase).Take(3))
        {
            var folder = ILCreateFromPath(group.Key);
            var items = group.Select(ILCreateFromPath).Where(p => p != IntPtr.Zero).ToArray();
            try
            {
                if (folder == IntPtr.Zero || SHOpenFolderAndSelectItems(folder, (uint)items.Length, items, 0) != 0)
                    Open("explorer.exe", $"/select,\"{group.First()}\"");
            }
            finally
            {
                foreach (var item in items) ILFree(item);
                if (folder != IntPtr.Zero) ILFree(folder);
            }
        }
    }

    public static void Open(string target, string? arguments = null)
    {
        try { Process.Start(new ProcessStartInfo(target) { Arguments = arguments ?? "", UseShellExecute = true })?.Dispose(); }
        catch (Win32Exception) { }
    }

    /// Running from the MSIX package (the Store build) rather than the installer.
    public static bool IsPackaged { get; } = DetectPackage();

    static bool DetectPackage()
    {
        var length = 0;
        // APPMODEL_ERROR_NO_PACKAGE (15700) means an ordinary, unpackaged process.
        return GetCurrentPackageFullName(ref length, IntPtr.Zero) != 15700;
    }

    public static string Version =>
        typeof(Shell).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "dev";

    /// "Open in Morph" on the right-click menu. The MSIX package declares it for the file types Morph handles;
    /// the installer adds it for every file and folder.
    public static string ContextMenuHint => IsPackaged
        ? "Right-click files in File Explorer and choose Open in Morph. On Windows 11 it may be under Show more options."
        : "Right-click files or folders and choose Open in Morph. On Windows 11 it's under Show more options.";

    /// Runs `action` on the UI thread once, after a delay.
    public static void After(int milliseconds, Action action)
    {
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
        timer.Tick += (_, _) => { timer.Stop(); action(); };
        timer.Start();
    }

    public static void Alert(string title, string message) =>
        MessageBox.Show(message, title, MessageBoxButton.OK, MessageBoxImage.Warning);

    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16, EntryPoint = "ILCreateFromPathW")]
    private static partial IntPtr ILCreateFromPath(string path);

    [LibraryImport("shell32.dll")]
    private static partial void ILFree(IntPtr pidl);

    [LibraryImport("shell32.dll")]
    private static partial int SHOpenFolderAndSelectItems(IntPtr folder, uint count, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] items, uint flags);

    [LibraryImport("kernel32.dll")]
    private static partial int GetCurrentPackageFullName(ref int length, IntPtr name);
}

/// "Open at login": the package's startup task in the Store build, the Run key otherwise.
public static class LoginItem
{
    const string runKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string taskId = "MorphStartup";

    public static async Task<bool> IsOn()
    {
        if (Shell.IsPackaged)
        {
            try
            {
                var task = await Windows.ApplicationModel.StartupTask.GetAsync(taskId);
                return task.State is Windows.ApplicationModel.StartupTaskState.Enabled or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
            }
            catch (Exception e) when (e is COMException or ArgumentException or InvalidOperationException) { return false; }
        }
        using var key = Registry.CurrentUser.OpenSubKey(runKey);
        return key?.GetValue("Morph") is string;
    }

    /// Turns it on or off; returns a problem to show, if any.
    public static async Task<string?> Set(bool on)
    {
        if (Shell.IsPackaged)
        {
            try
            {
                var task = await Windows.ApplicationModel.StartupTask.GetAsync(taskId);
                if (!on) { task.Disable(); return null; }
                var state = await task.RequestEnableAsync();
                return state switch
                {
                    Windows.ApplicationModel.StartupTaskState.DisabledByUser => "Turned off in Task Manager's Startup apps. Turn it on there.",
                    Windows.ApplicationModel.StartupTaskState.DisabledByPolicy => "Your organization doesn't allow startup apps.",
                    _ => null,
                };
            }
            catch (Exception e) when (e is COMException or ArgumentException or InvalidOperationException) { return e.Message; }
        }
        using var key = Registry.CurrentUser.CreateSubKey(runKey);
        if (on) key.SetValue("Morph", $"\"{Environment.ProcessPath}\" --background");
        else key.DeleteValue("Morph", throwOnMissingValue: false);
        return null;
    }
}
