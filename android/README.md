# Morph for Android

A Kotlin + Jetpack Compose port of Morph. Open it and pick files, or share files to it from any app ("Morph" in the share sheet), then choose an action. Everything runs on the phone.

Needs Android 10 (API 29) or later.

## Install

Morph is in closed testing on Google Play and comes out around 11 November 2026. To test it: join the [Morph testers group](https://groups.google.com/g/morph-tester), tap **Become a tester** on the [opt-in page](https://play.google.com/apps/testing/app.morph) with the same Google account, then install it from the [Play Store](https://play.google.com/store/apps/details?id=app.morph). Without Play, download `Morph-1.0.1-arm64.apk` (or `-armv7` for older phones) from [Releases](../../../releases/latest), open it on your phone, and allow installs from that source when Android asks.

The Play bundle is built with `./gradlew bundleRelease` and the per-CPU APKs with `./gradlew assembleRelease` (signed with the upload key in `keystore.properties`); the listing, graphics and policy answers are in [`marketing/play-store.md`](../marketing/play-store.md).

Morph has no internet access: the network permissions ML Kit would add are removed in the manifest, and text recognition uses the model bundled in the app.

## What it can do

The same actions as the Mac app, apart from the ones that need a desktop (tar.gz of folders, the Actions wheel):

- Images: JPG, PNG, HEIC (on phones with a HEVC encoder), WEBP, TIFF, GIF, BMP, SVG, or several images into one PDF. Camera RAW (DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2 and more) opens too: Android develops DNG and some others itself, and for the rest Morph uses the full-size preview the camera saved inside the file.
- Video to MP4, MOV or GIF; audio to M4A, WAV, AIFF, FLAC, OGG or OPUS (or the soundtrack of a video)
- PDF to images or text; merge, split and compress PDFs (PdfBox, offline)
- Documents between DOCX, ODT, RTF, HTML, Markdown, TXT and PDF; subtitles between SRT and VTT; data between CSV, TSV and JSON
- Compress images, videos and PDFs, or to a size limit; resize images, or crop them to exact form sizes
- Remove metadata from photos, videos and audio
- Blur faces, hide personal info in screenshots, extract text and read QR codes and barcodes (ML Kit, on device)
- Mute a video, grab snapshots, normalize loudness, trim silence
- Zip files, and extract zip, tar, tar.gz and gz archives
- Recipes: Web Image, Under 1 MB, Share-Safe Photo

`./gradlew connectedAndroidTest` runs every action on a phone or emulator against the files in the app's cache under `samples` (push them with `adb push`, then copy them in with `adb shell run-as app.morph`); it writes a report of each run next to them.

## Build

You need JDK 17 and the Android SDK (put its path in `local.properties` as `sdk.dir=...`, or set `ANDROID_HOME`).

```bash
cd android && ./gradlew assembleDebug
```

The debug APK lands in `app/build/outputs/apk/debug/`.

### Release builds

Release builds are signed from `keystore.properties`, which stays out of git:

```
storeFile=morph-release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

```bash
cd android && ./gradlew assembleRelease
```

Keep a backup of the keystore. Android only installs an update when it is signed with the same key as the version already on the phone.

## Files

```
MainActivity.kt      entry point, handles share and open intents
MorphModel.kt        view model: picked files, running jobs, results
core/Engine.kt       file kinds, actions and the image, PDF, video and archive ops
core/ImageFormats.kt TIFF, BMP and GIF encoders, HEIC, camera RAW previews
core/AudioOps.kt     decoding to PCM, WAV, AIFF, FLAC and Opus, loudness and silence
core/VideoOps.kt     GIFs and snapshots from video, metadata-free copies
core/DocOps.kt       documents, subtitles and data tables
core/Vision.kt       text, faces, personal info and codes (ML Kit)
core/Store.kt        inbox, sharing results, history, preferences
ui/App.kt            main screen
ui/Actions.kt        action sheet and results
ui/Onboarding.kt     first-launch intro
ui/Theme.kt          colors, typography (Nunito), components
```
