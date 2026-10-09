# Morph

A free file converter and toolbox for macOS, iOS and Android. Drop a file on Morph and it shows only the actions that make sense for that file: convert it, compress it, strip its metadata, pull the text out of it and more. Everything runs on your device; nothing is uploaded.

## Download

Grab the latest build from [Releases](../../releases/latest):

| Platform | File | Needs |
| --- | --- | --- |
| macOS | `Morph-0.1.0.dmg` | macOS 14 or later, Apple Silicon or Intel |
| Android | `Morph-0.1.0.apk` | Android 10 or later |
| iOS | build from source, see [ios/README.md](ios/README.md) | iOS 17 or later |

**macOS:** open the DMG and drag Morph into Applications. The build is ad-hoc signed, so the first launch is blocked: open System Settings → Privacy & Security and click **Open Anyway**.

**Android:** open the APK on your phone and allow installs from that source when asked. See [android/README.md](android/README.md).

## What it does

**Convert**
- Images: JPG, PNG, HEIC, WEBP, AVIF, TIFF, GIF, BMP, or several images into one PDF
- Video: MP4, MOV, WEBM, MKV, GIF
- Audio: M4A, WAV, AIFF, MP3, FLAC, OGG, OPUS (or pull the soundtrack out of a video)
- PDF: to images or plain text
- Documents: DOCX, ODT, RTF, HTML, Markdown, TXT, PDF (DOCX and ODT on the Mac only)
- Subtitles: SRT ↔ VTT
- Data: CSV, TSV, JSON

**Tools**
- Compress images, videos and PDFs (light, balanced or strong), resize images
- Remove metadata such as location and camera info
- Blur faces, hide personal info (emails, phone and card numbers, IBANs, ID numbers, IP addresses) in screenshots
- Extract text (OCR), read QR codes and barcodes
- Merge and split PDFs
- Mute a video, grab snapshots, normalize loudness, trim silence, turn audio into a waveform video
- Zip, tar.gz and extract archives

**Recipes** chain several actions into one, like "Web Image" (resize + WEBP) or "Under 1 MB".

Formats marked as needing ffmpeg (WEBM, MKV, MP3, FLAC, OGG, OPUS and the loudness tools) show up on the Mac once `ffmpeg` is installed, for example with `brew install ffmpeg`.

## macOS app

Morph lives in the menu bar. There are a few ways to use it:
- Drop files on the menu bar icon.
- Hold a key (Shift, Option, Control or Tab, set in Settings) while dragging files anywhere, and the action wheel pops up under the cursor.
- In Finder, right-click files → Services → **Open in Morph**.

The app also bundles the `morph` command-line tool.

## Command line

```
morph actions [files…]                 list actions (only those that fit the files, if given)
morph run <action> [flags] <files…>    run an action or recipe ("recipe.Web Image")
morph info <file>                      size, format, private metadata
morph recipes                          list recipes
morph recipe add <name> <a,b,c>        save a recipe from action ids
morph recipe rm <name>
morph watch <folder> <action>          process new files as they arrive (Ctrl-C to stop)
morph history                          recent jobs
morph undo                             move the last job's outputs to the Trash

flags: --quality 0.8  --max 1600  --target 500KB  --level light|balanced|strong
       --out <dir>    --style pixelate|solid
```

For example: `morph run convert.webp --max 1600 photo.heic`.

## Building from source

The shared engine (`MorphCore`), the CLI and the Mac app are one Swift package.

```bash
swift build
```

```bash
scripts/bundle.sh --dmg
```

`bundle.sh` builds a universal `dist/Morph.app`; `--dmg` also makes `dist/Morph.dmg`, and `--install` copies the app to /Applications and launches it. To sign with a Developer ID and notarize, see the comments at the top of the script.

The iOS and Android apps have their own instructions in [ios/README.md](ios/README.md) and [android/README.md](android/README.md).

## Project layout

```
Sources/MorphCore   shared engine: image, PDF, media, document, vision and archive ops, recipes, history
Sources/MorphMac    macOS menu bar app
Sources/morph       command-line tool
ios/                iOS app (SwiftUI, uses MorphCore)
android/            Android app (Kotlin + Jetpack Compose)
scripts/            app bundle, icon and DMG build scripts
```
