# Changelog

## Unreleased

### Everywhere
- **SVG in and out.** Drop an SVG to get PNG, JPG, WEBP, HEIC, PDF or any other image format. It renders at its own size (at least 1024 px on the long side, so icons come out usable), or exactly at Max size when one is set. PDFs from SVGs stay vectors on the Mac, iPhone and Android.
- **Image to SVG.** The new SVG action traces a PNG, JPG or any other image into real vector shapes: a small palette, specks cleaned up, outlines smoothed into curves with sharp corners kept. Logos, icons and screenshots come out clean and usually smaller than the PNG. Compression level sets the detail (light keeps more colors and finer edges, strong makes the smallest files); the CLI's `--colors` picks the palette size.
- Nothing goes online: images an SVG links to on the web are skipped.
- **SVG and PDF come first** on the Convert wheel, right after the common photo formats, so they share its first page.
- **Exact photo size for forms.** Settings → Photo size makes Resize produce exactly the size a form asks for: passport and visa (600 × 600, 35 × 45 mm, China visa), exams (3.5 × 4.5 cm, bank exams 200 × 230), signatures (140 × 60, 280 × 120), social and web sizes, or any width × height. The photo is cropped to fill, keeping the face area, saved as a JPG without location data, and fitted under the size limit when one is set. Optionally the name and the date the photo was taken are printed in a strip under it, for exam forms. The CLI has `--size 600x600` and `--caption "Name"`.
- Text, CSV and subtitle files in older encodings (Windows-1252, Latin-1, UTF-16) open, CSVs with old Mac line endings parse, and duplicate column names no longer stop a JSON export. Zip copes with two files of the same name, and empty videos and PDFs give a clear error.

### Mac
- **Mac App Store version.** The menu bar app, sandboxed. Results go to Downloads until you allow saving next to the originals, once, in Settings → Output or the welcome guide; the wheel never stops to ask. Homebrew extras (MP3, WebM, FLAC; WebP) and the command-line tool stay in the download from the website.
- The download from the website is signed with a Developer ID and notarized by Apple, so it opens without a warning.
- Undo works after a relaunch in the App Store version.
- The wheel takes clicks and drops again in the App Store version. With Liquid Glass, a click or drop on a petal went to the window behind it, and a dragged file couldn't be read until it was dropped on Morph ("isn't a readable image").
- The download from the website now uses Liquid Glass on macOS 26 too, like the App Store version.

### iPhone and iPad
- Opening two files with the same name works (the second becomes "name 2"), and copies of imported files are cleared at launch.

### Windows
- Version 1.0.1, for the Microsoft Store update and the installers.

### Android
- Recent jobs and settings stay out of Google's cloud backup.
- A result that can't be written to Downloads is reported instead of leaving an empty or hidden file.

### Website
- The demo on the homepage shows Morph itself: its four wheels and their keys (⇧ ⌘ ⌃ ⌥, or Shift, Ctrl, Ctrl+Shift and Alt on Windows), the real actions for each file, and a Mac desktop.

## 1.0.0 (2026-10-22)

### Everywhere
- **Teal Ink.** A new look: one flat brand color on cool neutrals, in place of the tangerine aura gradients and glows. The app icon is redrawn with Morph's own seven-drop mark; the old icon used an SF Symbol, which Apple's license doesn't allow in app icons.
- **Pick your color.** Settings offers Teal Ink, Ultramarine, Green, Magenta and Yellow, and the whole app recolors at once. Every option keeps labels readable (WCAG AA) in light and dark mode. The app icon stays Teal Ink.
- **A fuller first-launch guide.** New pages show where Morph works (on iPhone: the share sheet, Shortcuts and Siri, the icon's quick actions; on Android: the share sheet and photo picker) and let you choose a color, a size limit and a compression level before you start. The guide recolors as you pick.
- **Faster Compress.** Qualities are now tried on a 1024-pixel sample of full-resolution patches from across the photo, several at once, and the photo is encoded once at the winner. Same results as before, about 3× faster: a 2.3 MB photo takes 0.4 s instead of 1.5 s.
- **Size limit for Compress.** Choose no limit, a size from 20 KB to 5 MB, or type any size. With a limit, photos come out as JPG under it at the best quality that fits, ready for exam forms and job portals; a JPG that's already small enough is left alone. Videos fit too: the Mac uses ffmpeg when it's installed, iPhone steps down through export sizes, and Android picks a bitrate from the video's length.

### iPhone and iPad
- **Ready for the App Store:** a privacy manifest, the export-compliance flag, an opaque 1024 px icon, and Privacy and Help links in Settings.
- Compress Files in Shortcuts takes an optional size limit in KB.

### Android
- **Ready for Google Play:** a signed release bundle, the listing, graphics and policy answers. Morph has no internet access at all; the network permissions ML Kit would bring in are removed, and text recognition still works offline.
- Privacy and Help links in Settings, and menus and dialogs in Morph's colors instead of Material's default tones.

### Windows
- **First Windows app.** Morph sits in the taskbar corner. While dragging files from File Explorer or the desktop, tap Shift, Ctrl, Ctrl+Shift or Alt to open the Convert, Tools, Recipes or Actions wheel under the cursor, then drop on an action. The tray panel takes files too, and File Explorer's right-click menu gets **Open in Morph**.
- Settings, the welcome guide, colors, the size limit and compression levels match the Mac. The Actions wheel shares through Windows' share sheet, copies files or paths, moves or copies them, and opens Windows Terminal there.
- Ships as an installer for GitHub releases (x64 and Arm64, no admin prompt) and an MSIX bundle for the Microsoft Store. Windows 10 1809 or later.

### Website
- Privacy policy and support pages, linked from the footer and from the iPhone app.

## 0.2.0 (2026-10-14)

### Mac
- **New wheel.** Actions are glass petals around a glass hub, with a bar below for switching wheels that shows each wheel's keys. The highlighted petal lifts outward and fills with Morph's aura colors, and a soft aura glows through the gaps.
- **Tap-to-open drag shortcuts.** While dragging files, tapping a wheel's keys opens it; the wheel stays open after the keys are released. Tap another wheel's keys to switch, or press Esc to close. A wheel opens only for its exact keys, so holding ⇧⌘ never opens ⇧'s wheel.
- **Key combinations.** Each wheel can use a single key (⇧, ⌘, ⌥, ⌃ or Tab) or any combination of modifiers. Keys set in an earlier version carry over.
- **Actions wheel (⌥).** AirDrop, Messages, Mail, Copy, Copy Path, Move To…, Copy To… and Terminal. These act on the files themselves and are not recorded in history.
- **Motion and sound.** The wheel springs out of a drop when it opens and melts back into it when it closes. Moving between petals plays a short click, and running jobs show a liquid loader.
- **Welcome guide.** "How it works" plays through each wheel with its key lit up.
- **Liquid Glass** on buttons, pickers and the wheel on macOS 26, following the system's Clear or Tinted setting.
- The DMG is now named by version (`Morph-0.2.0.dmg`).

### iPhone and iPad
- **Shortcuts, Siri, Spotlight and the Action button.** Convert Images, Compress Files, Remove Metadata, Extract Text, Read QR Codes and Barcodes, Merge PDFs, Run Morph Action and Open in Morph.
- **Home-screen quick actions:** Convert Photos and Choose Files.
- **Liquid Glass** buttons, pickers and sheets on iOS 26.
- **New look.** A launch animation where a drop splits into the Morph mark, a drifting aura behind the home card (iOS 18 and later), a liquid loader while working and an aura check when done.

### Engine
- **Smarter compression.** Images are re-encoded at a range of qualities and the smallest version that still looks the same (by SSIM against the original) is kept; Light, Balanced and Strong set how strict "looks the same" is. JPEGs are written progressive. If a file can't get at least 5% smaller without looking worse, nothing is written and Morph says so instead of handing back a near-identical copy. Every result shows before → after sizes ("171 KB → 144 KB, 16% smaller") on the Mac, iPhone and command line.
- New `file` action group for app-supplied file actions, and a public `Action` initializer so apps can define their own.

## 0.1.0 (2026-10-09)

First release: menu bar app with a drag wheel, `morph` CLI, iOS and Android apps.
