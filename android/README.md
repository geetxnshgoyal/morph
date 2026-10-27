# Morph for Android

A Kotlin + Jetpack Compose port of Morph. Open it and pick files, or share files to it from any app ("Morph" in the share sheet), then choose an action. Everything runs on the phone.

Needs Android 10 (API 29) or later.

## Install

Morph is in closed testing on Google Play and comes out around 11 November 2026. To test it: join the [Morph testers group](https://groups.google.com/g/morph-tester), tap **Become a tester** on the [opt-in page](https://play.google.com/apps/testing/app.morph) with the same Google account, then install it from the [Play Store](https://play.google.com/store/apps/details?id=app.morph). Without Play, download `Morph-1.0.0.apk` from [Releases](../../../releases/latest), open it on your phone, and allow installs from that source when Android asks.

The Play bundle is built with `./gradlew bundleRelease` (signed with the upload key in `keystore.properties`); the listing, graphics and policy answers are in [`marketing/play-store.md`](../marketing/play-store.md).

Morph has no internet access: the network permissions ML Kit would add are removed in the manifest, and text recognition uses the model bundled in the app.

## What it can do

- Convert images to JPG, PNG or WEBP, images to one PDF, PDF to images
- SVG to PNG, JPG, WEBP or PDF (drawn with AndroidSVG, offline), and any image traced into an SVG
- Convert video to MP4, pull audio out to M4A
- Compress images and videos, resize images, remove image metadata
- Extract text from images (ML Kit, on device)
- Mute a video, zip files
- Recipes: Web Image, Under 1 MB, Share-Safe Photo

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
core/Engine.kt       file kinds, actions and the image, PDF, media and OCR ops
core/Store.kt        inbox, sharing results, history, preferences
ui/App.kt            main screen
ui/Actions.kt        action sheet and results
ui/Onboarding.kt     first-launch intro
ui/Theme.kt          colors, typography (Nunito), components
```
