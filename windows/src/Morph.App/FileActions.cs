using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Microsoft.VisualBasic.FileIO;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

namespace Morph.App;

/// The Actions wheel: everyday things to do with the files themselves (share, copy, move, open a terminal there)
/// rather than new files to make. They run at once on the UI thread and stay out of history, since undoing a
/// move would recycle the originals.
public static class FileActions
{
    public static IReadOnlyList<MorphAction> For(IReadOnlyList<string> files)
    {
        if (files.Count == 0) return [];
        var list = new List<MorphAction>();
        void Add(string id, string title, string symbol, Action<IReadOnlyList<string>> body) => list.Add(new MorphAction
        {
            Id = $"file.{id}", Title = title, Symbol = symbol, Group = ActionGroup.File, Kinds = FileKinds.All,
            CombinesInputs = true,
            Run = (inputs, _, _) => { body(inputs); return Task.FromResult<IReadOnlyList<string>>([]); },
        });

        if (files.All(File.Exists)) Add("share", "Share", "square.and.arrow.up", Share);
        Add("copy", "Copy", "doc.on.doc", paths =>
        {
            var list = new StringCollection();
            list.AddRange([.. paths]);
            System.Windows.Clipboard.SetFileDropList(list);
            Confirm();
        });
        Add("copy-path", files.Count == 1 ? "Copy Path" : "Copy Paths", "link", paths =>
        {
            System.Windows.Clipboard.SetText(string.Join(Environment.NewLine, paths));
            Confirm();
        });
        Add("move", "Move To…", "folder", paths => Transfer(paths, move: true));
        Add("copy-to", "Copy To…", "plus.rectangle.on.folder", paths => Transfer(paths, move: false));
        Add("terminal", "Terminal", "terminal", OpenTerminal);
        return list;
    }

    /// Shows a failed file action, since the wheel has already gone by the time it fails.
    public static void Report(Exception error) => Shell.Alert("Couldn't finish that", error.Message);

    static void Confirm()
    {
        if (Preferences.Shared.PlaySounds) System.Media.SystemSounds.Asterisk.Play();
    }

    /// Moves or copies into a folder the user picks, renaming instead of overwriting, then shows the results.
    /// Windows' own copy engine does the work, so big transfers get its progress window.
    static void Transfer(IReadOnlyList<string> paths, bool move)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = $"{(move ? "Move" : "Copy")} {(paths.Count == 1 ? Path.GetFileName(paths[0]) : $"{paths.Count} items")} to",
            InitialDirectory = Output.FolderOf(paths[0]),
        };
        if (dialog.ShowDialog() != true) return;
        var results = new List<string>();
        foreach (var path in paths)
        {
            var isFolder = Directory.Exists(path);
            var name = Path.GetFileName(Path.TrimEndingDirectorySeparator(path));
            var target = isFolder ? Output.Unique(dialog.FolderName, name, "")
                : Output.Unique(dialog.FolderName, Path.GetFileNameWithoutExtension(name), Path.GetExtension(name).TrimStart('.'));
            try
            {
                if (isFolder && move) FileSystem.MoveDirectory(path, target, UIOption.OnlyErrorDialogs);
                else if (isFolder) FileSystem.CopyDirectory(path, target, UIOption.OnlyErrorDialogs);
                else if (move) FileSystem.MoveFile(path, target, UIOption.OnlyErrorDialogs);
                else FileSystem.CopyFile(path, target, UIOption.OnlyErrorDialogs);
                results.Add(target);
            }
            catch (OperationCanceledException) { break; }
        }
        Shell.Reveal(results);
    }

    /// Opens Windows Terminal in the folder itself, or in the folder that holds the file; PowerShell without it.
    static void OpenTerminal(IReadOnlyList<string> paths)
    {
        var folder = Directory.Exists(paths[0]) ? paths[0] : Output.FolderOf(paths[0]);
        try
        {
            Process.Start(new ProcessStartInfo("wt.exe") { ArgumentList = { "-d", folder }, UseShellExecute = true })?.Dispose();
        }
        catch (Win32Exception)
        {
            Process.Start(new ProcessStartInfo("powershell.exe") { WorkingDirectory = folder, UseShellExecute = true })?.Dispose();
        }
    }

    // MARK: Share

    /// Windows' share sheet (Nearby Share, Mail, Teams…). It belongs to a window, so a tiny invisible one is
    /// opened at the cursor and closed once the sheet is done with it.
    static void Share(IReadOnlyList<string> paths)
    {
        var anchor = new Window
        {
            Width = 1, Height = 1, WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent,
            ShowInTaskbar = false, Topmost = true, WindowStartupLocation = WindowStartupLocation.Manual,
        };
        Native.GetCursorPos(out var cursor);
        var scale = Native.ScaleAt(cursor);
        anchor.Left = cursor.X / scale;
        anchor.Top = cursor.Y / scale;
        anchor.Show();
        var handle = new WindowInteropHelper(anchor).Handle;
        var manager = DataTransferManagerInterop.GetForWindow(handle);
        manager.DataRequested += async (_, args) =>
        {
            var deferral = args.Request.GetDeferral();
            try
            {
                var items = new List<IStorageItem>();
                foreach (var path in paths) items.Add(await StorageFile.GetFileFromPathAsync(path));
                args.Request.Data.Properties.Title = paths.Count == 1 ? Path.GetFileName(paths[0]) : $"{paths.Count} files";
                args.Request.Data.SetStorageItems(items);
            }
            catch (Exception e) when (e is COMException or IOException or UnauthorizedAccessException)
            {
                args.Request.FailWithDisplayText(e.Message);
            }
            finally { deferral.Complete(); }
        };
        manager.TargetApplicationChosen += (_, _) => anchor.Dispatcher.BeginInvoke(anchor.Close);
        // The sheet has no "closed" event; the anchor goes after a while either way.
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMinutes(2) };
        timer.Tick += (_, _) => { timer.Stop(); anchor.Close(); };
        timer.Start();
        DataTransferManagerInterop.ShowShareUIForWindow(handle);
    }

    static class DataTransferManagerInterop
    {
        static readonly Guid iid = new(0xa5caee9b, 0x8708, 0x49d1, 0x8d, 0x36, 0x67, 0xd2, 0x5a, 0x8d, 0xa0, 0x0c);

        static IDataTransferManagerInterop Instance => DataTransferManager.As<IDataTransferManagerInterop>();

        public static DataTransferManager GetForWindow(IntPtr window)
        {
            var guid = iid;
            return WinRT.MarshalInterface<DataTransferManager>.FromAbi(Instance.GetForWindow(window, ref guid));
        }

        public static void ShowShareUIForWindow(IntPtr window) => Instance.ShowShareUIForWindow(window);
    }

    [ComImport, Guid("3A3DCD6C-3EAB-43DC-BCDE-45671CE800C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDataTransferManagerInterop
    {
        IntPtr GetForWindow([In] IntPtr appWindow, [In] ref Guid riid);
        void ShowShareUIForWindow(IntPtr appWindow);
    }
}
