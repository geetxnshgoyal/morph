# Microsoft Store submission (Windows)

Live at https://apps.microsoft.com/detail/9PHWJVRC85DW (Store ID 9PHWJVRC85DW, package `GeetanshGoyal.MorphFileConverter`).

Everything Partner Center asks for, field by field, for Morph 1.0.0. Character limits are noted and every field fits.

## Before the first submission

1. **Reserve the name** in Partner Center → Apps and games → New product → MSIX or PWA app: **Morph: File Converter**. If it's taken, use "Morph – Convert & Compress"; the name in the Start menu stays "Morph".
2. **Copy the package identity** from the app's Product management → Product identity into the repository variables `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER` and `MSIX_PUBLISHER_DISPLAY_NAME` (see [windows/README.md](../windows/README.md#microsoft-store)), then rerun the Windows workflow.
3. **Download** the `Morph-1.0.0-windows` artifact from that run and upload `Morph-1.0.0.msixbundle` under Packages. It holds x64 and Arm64. The Store signs it; no certificate is needed.

## Packages

| Field | Value |
| --- | --- |
| Package | `Morph-1.0.0.msixbundle` (x64 and Arm64) |
| Device family | Windows 10/11 Desktop, minimum version 10.0.17763.0 (1809) |
| Restricted capability | `runFullTrust` (see below) |

**Why the app needs runFullTrust** (Partner Center asks for this in Submission options):

Morph is a desktop app (WPF on .NET) packaged with MSIX, so it runs as a full-trust process like any desktop app. It reads the files the user drops on it and writes converted copies next to them, watches the keyboard and mouse button only while files are being dragged so the user can open its wheel with a key tap mid-drag, and shows a tray icon. It makes no network requests.

## Properties

| Field | Value |
| --- | --- |
| Category | Utilities & tools |
| Subcategory | File managers |
| Privacy policy URL | https://morph.geetanshgoyal.in/privacy.html |
| Website | https://morph.geetanshgoyal.in |
| Support contact | https://morph.geetanshgoyal.in/support.html |
| Product declarations | Leave "This app depends on non-Microsoft drivers or NT services" unchecked. Check "Customers can install this app to alternate drives or removable storage" |
| System requirements | Minimum: 4 GB memory. Recommended: 8 GB memory. Architecture: x64, Arm64 |

## Age ratings

Answer the IARC questionnaire with category **Utility, productivity, communication or other** and **No** to every question. Expect 3+ / Everyone / PEGI 3.

## Pricing and availability

Free, all markets, public audience, discoverable in the Store. Release as soon as certification passes.

## Store listing (English, United States)

| Field | Value |
| --- | --- |
| Product name | Morph: File Converter |
| Short title (50) | Morph |
| Sort title | Morph |
| Voice title | Morph |
| Copyright and trademark info (200) | © 2026 Geetansh Goyal. Morph is open source under the MIT License. |
| Developed by | Geetansh Goyal |
| App icon | Comes from the package (`windows/packaging/Assets`); the 300 × 300 Store logo is optional, and `play-store/icon-512.png` resized fits if Partner Center asks |
| Screenshots | `microsoft-store/1-wheel.png` … `6-dark.png` (1920 × 1080), in that order. `Morph.exe --snapshots` redraws them from the app (CI does this on every build) |

**Short description (1000):**

Convert, compress and clean up files right where they are. Drag files from File Explorer, tap a key, and drop them on the wheel. Nothing is uploaded.

**Description (10000):**

Morph turns any file into the one you need, right on your PC. Drag files from File Explorer or the desktop, tap a key, and a wheel of actions opens under your cursor. Drop the files on an action and the result appears next to the original. Only the actions that fit your files show up.

Fit any upload limit
Exam forms, job portals and government sites often want a photo under 200 KB, 100 KB or even 20 KB. Set a size limit once and Compress makes a JPG that fits, at the best quality that fits.

Four wheels, one key each
• Shift: Convert, to every format the files can become
• Ctrl: Tools, such as Compress, Resize and Remove Metadata
• Ctrl+Shift: Recipes, several steps in one drop
• Alt: Actions: share, copy, copy the path, move, or open Terminal there
Change any of them in Settings.

Convert
• Images: JPG, PNG, WEBP, AVIF, TIFF, GIF, BMP, or several images into one PDF
• Video: MP4, or a GIF
• Audio: M4A, WAV, MP3, FLAC, or the soundtrack of a video
• PDFs to images or text
• Documents: DOCX, ODT, RTF, HTML, Markdown, TXT and PDF
• Subtitles (SRT and VTT) and data (CSV, TSV, JSON)

Compress and clean up
• Shrink photos, videos and PDFs, keeping the look, or to a size limit
• Resize photos
• Remove location and camera details before you share
• Blur faces and hide emails, phone and card numbers in screenshots
• Extract text from images and PDFs, read QR codes and barcodes
• Merge and split PDFs, zip and unzip

Yours to tune
Choose how strongly to compress, set a size limit, choose where results are saved, and pick an accent color: Teal Ink, Ultramarine, Green, Magenta or Yellow.

Private by design
Everything happens on your PC. Morph makes no network requests: nothing is uploaded, there's no account, and your originals are never changed. Every job can be undone from the tray.

Install ffmpeg (winget install Gyan.FFmpeg) and Morph also handles WebM, MKV, OGG, Opus and loudness tools.

Morph is free and open source, and also available on Mac, iPhone and Android.

**What's new in this version (1500):**

First release on Windows. Drag files, tap a key, and drop them on the wheel to convert, compress and clean them up, with a size limit for upload forms and your own accent color. Nothing is uploaded.

**Product features (up to 20, 200 each):**

1. Convert images, video, audio, PDFs and documents between formats
2. Compress photos to fit a size limit such as 200 KB or 50 KB
3. Open a wheel of actions under the cursor by tapping a key while dragging files
4. Remove location and camera metadata before sharing
5. Blur faces and hide personal info in screenshots
6. Extract text from images and PDFs; read QR codes and barcodes
7. Merge and split PDFs; zip and unzip
8. Open in Morph from the File Explorer right-click menu
9. Undo any job; originals are never changed
10. Works offline; nothing is ever uploaded

**Search terms (7, 30 each):**

file converter, heic to jpg, compress photo, image resize, pdf tools, remove metadata, kb photo

**Additional license terms:** MIT License, https://github.com/geetxnshgoyal/morph/blob/main/LICENSE

## Notes for certification (optional, 2000)

Morph is a tray app. After launch it shows its welcome guide the first time, then its panel above the taskbar icon. To try it: drag any photo from File Explorer, tap Shift while still holding the mouse button, and drop the photo on a format on the wheel. Or click the tray icon, choose a file, and pick an action. No account or network access is needed.
