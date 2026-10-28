# Morph for Windows

Morph's Windows app: the drop wheel, drag shortcuts, a tray panel, Settings and the welcome guide, on WPF and .NET 10, with the engine ported to C#. It matches the Mac app as closely as Windows allows.

## Install

- **Microsoft Store:** [Morph: File Converter](https://apps.microsoft.com/detail/9PHWJVRC85DW). Signed by Microsoft, so there's no SmartScreen warning, and it updates itself.
- **Installer (beta):** download [`Morph-1.0.1-x64-setup.exe`](https://github.com/geetxnshgoyal/morph/releases/download/v1.0.0/Morph-1.0.1-x64-setup.exe) (or [`Morph-1.0.1-arm64-setup.exe`](https://github.com/geetxnshgoyal/morph/releases/download/v1.0.0/Morph-1.0.1-arm64-setup.exe) for Arm PCs such as Surface Pro X and Copilot+ PCs) and run it. This first build hasn't been tried on many PCs yet, so please [report](https://github.com/geetxnshgoyal/morph/issues/new) anything that breaks. It installs for your user only, without an admin prompt; choose "Install for all users" in the first screen if you prefer. The installer isn't code-signed yet, so SmartScreen may warn that it doesn't recognise the app: click **More info**, then **Run anyway**.

Needs Windows 10 version 1809 or later, or Windows 11. .NET comes with the app; nothing else to install. Uninstall from Settings → Apps.

## Using it

Morph lives in the taskbar corner. Windows 11 may tuck a new icon behind the **^** arrow: drag it out next to the clock, or turn Morph on under Settings → Personalization → Taskbar → Other system tray icons.

- **Drag shortcuts.** While dragging files from File Explorer or the desktop, tap a wheel's keys and that wheel opens under the cursor: **Shift** for Convert, **Ctrl** for Tools, **Ctrl+Shift** for Recipes, **Alt** for Actions. Drop on an action and the result lands next to the original. Tap another wheel's keys to switch, or **Esc** to close. Keys can be changed in Settings, to any combination of Ctrl, Alt, Shift and Win, or Tab.
- **The tray panel.** Click the icon to drop files on it or choose them, see recent jobs, show their results or undo them (results go to the Recycle Bin; originals are never touched).
- **Right-click.** Select files in File Explorer and choose **Open in Morph**. On Windows 11 the installer's entry is under **Show more options**; the Store build adds it for the file types Morph handles and lists Morph under **Open with**.
- **The wheel.** Hover or use the arrow keys and the scroll wheel to move around it, Tab to switch wheels, Enter to run.
- **Settings.** Open at login, the drag keys, accent color, sounds, where results are saved, compression level and the size limit for Compress.

The Actions wheel shares files through Windows' share sheet, copies them or their paths, moves or copies them to a folder, and opens Windows Terminal (or PowerShell) there.

ffmpeg is optional: `winget install Gyan.FFmpeg` adds WebM, MKV, OGG, Opus and the loudness tools. Without it, Windows' own Media Foundation still converts and compresses MP4 and makes M4A, WAV, MP3 and FLAC.

### Differences from the Mac app

- Windows has no system-wide drag pasteboard to read, so a drag counts once it starts in File Explorer or on the desktop (or shows the shell's drag image), and the wheel learns which files it carries as the drag reaches it.
- There's no AirDrop or Messages; Share opens Windows' share sheet (Nearby Share, Mail, Phone Link and other apps).
- The tray icon can't take drops (Windows doesn't allow it), so files go to its panel instead.
- Windows 11 puts the installer's "Open in Morph" under Show more options. Putting it on the main menu needs a signed shell extension, which is planned.

## What's here

```
src/Morph.App/           the app: tray icon and panel, wheel, drag shortcuts, Actions, Settings, welcome guide
src/Morph.Core/          the engine: image, PDF, document, media, archive and vision ops, the action library,
                         runner, watch folder and the wheel's key model (Ctrl, Alt, Shift, Win or Tab)
src/Morph.Core/Windows/  Windows-only engine pieces: Media Foundation for audio and video, PDF rendering, and
                         on-device text and face detection
tests/Morph.Core.Tests/  xUnit tests for the engine and the wheel model
packaging/               MSIX manifest and tile images for the Microsoft Store
installer/               Inno Setup script for the GitHub release installer
scripts/                 package.ps1 (builds everything) and make-icon.cs (draws the icons)
```

Images go through Magick.NET (SVGs too, with every reference outside the file stripped first), PDFs through PDFsharp and PdfPig, documents through Open XML and Markdig, and QR codes through ZXing.Net. ffmpeg handles every audio and video format when it is installed; without it, Windows' own Media Foundation covers the common ones.

### Why WPF

The wheel is a borderless, per-pixel transparent window that floats over everything and takes a drop in the middle of another app's drag without taking focus. WPF does that natively (layered windows, OLE drag and drop, and a non-activating window style), runs on Windows 10 1809 and later with no extra runtime beyond .NET, and builds with the plain `dotnet` CLI on any OS, so the app compiles on the Mac it's written on. WinUI 3 has no transparent top-level windows and would add the Windows App SDK runtime as a dependency for no gain here. .NET 10's Fluent theme gives menus and dialogs the Windows 11 look.

## Build and test

Needs the [.NET 10 SDK](https://dotnet.microsoft.com/download). The engine and the app also build on macOS and Linux (the Windows-only parts compile there but only run on Windows).

```bash
dotnet test windows/tests/Morph.Core.Tests
```

```bash
dotnet build windows/src/Morph.App
```

To package on Windows (needs the Windows SDK and Inno Setup 6):

```powershell
windows/scripts/package.ps1 -Version 1.0.0
```

That writes `windows/dist/`: `Morph-1.0.0.msixbundle` and one `.msix` per architecture for the Microsoft Store, and `Morph-1.0.1-x64-setup.exe` and `-arm64-setup.exe` for GitHub releases.

`Morph.exe --snapshots <folder>` draws every screen in light and dark to PNGs without opening a window, for checking the UI on a machine that can't run it.

### CI

[`.github/workflows/windows.yml`](../.github/workflows/windows.yml) runs on `windows-latest` for every push to `windows/`: it runs the tests on both builds of the engine, packages everything, renders the snapshots, and uploads `Morph-<version>-windows` (the bundle, MSIX files and installers) and `snapshots` as artifacts of the run.

### Microsoft Store

The Store signs the package itself, so the MSIX needs no certificate, but its identity must match the one Partner Center reserved. Set these repository variables (Settings → Secrets and variables → Actions → Variables) from Partner Center → the app → Product identity, then rerun the workflow:

| Variable | Partner Center field |
| --- | --- |
| `MSIX_IDENTITY_NAME` | Package/Identity/Name |
| `MSIX_PUBLISHER` | Package/Identity/Publisher (`CN=…`) |
| `MSIX_PUBLISHER_DISPLAY_NAME` | Package/Properties/PublisherDisplayName |

The listing copy is in [`marketing/microsoft-store.md`](../marketing/microsoft-store.md).
