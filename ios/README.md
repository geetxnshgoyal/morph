# Morph for iOS

A SwiftUI app built on the same `MorphCore` engine as the Mac app. Pick photos, videos or files, or send them to Morph from any share sheet ("Open in Morph"), then choose an action. Results are saved to the Files app under **On My iPhone → Morph**, and converted photos and videos can go straight to your photo library.

Needs iOS 17 or later. Runs on iPhone and iPad. On iOS 26 the buttons, pickers and sheets use Liquid Glass and follow your Clear or Tinted choice in Settings.

## Shortcuts, Siri and the Action button

Every action is an App Intent, so it shows up in the Shortcuts app, Spotlight and Siri, and can be put on the Action button:

| Action | Takes | Gives back |
| --- | --- | --- |
| Convert Images | images or SVGs, a format (JPG, PNG, HEIC, WEBP, AVIF, TIFF, GIF, BMP, SVG or PDF) | files |
| Compress Files | images, videos or PDFs, a strength, an optional size limit in KB | files |
| Remove Metadata | photos, videos or audio | files |
| Extract Text | images or PDFs | text |
| Read QR Codes and Barcodes | images or PDFs | text |
| Merge PDFs | PDFs | one PDF |
| Run Morph Action | any action or recipe, files | files |
| Open in Morph | files | opens the app to choose |

Results are also saved in Morph's folder, like jobs started in the app. Siri phrases include "Convert images with Morph", "Remove location from photos with Morph" and "Extract text with Morph".

Press and hold the app icon for **Convert Photos** and **Choose Files**.

## Settings

- **Compression:** Light, Balanced or Strong.
- **Size limit:** no limit, 20 KB to 5 MB, or any size typed in. With a limit, Compress makes JPGs under it, for upload forms.
- **Color:** Teal Ink (Morph's own), Ultramarine, Green, Magenta or Yellow. The app icon stays Teal Ink.

## App Store

The app is set up for App Store review: a privacy manifest (`Morph/PrivacyInfo.xcprivacy`, no data collected), `ITSAppUsesNonExemptEncryption` set to `NO`, an opaque 1024 px icon, and Privacy and Help links in Settings. The listing text, screenshots and review notes are in [`marketing/app-store.md`](../marketing/app-store.md).

The project uses the Geetansh Goyal developer team (`675A56FHGZ`) with automatic signing. `ExportOptions.plist` selects App Store Connect distribution for this team and exports an IPA locally without uploading it. Distribution signing still requires a valid Apple Distribution certificate and App Store provisioning profile.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

```bash
cd ios && xcodegen
```

Then open `ios/Morph.xcodeproj`, choose your team under Signing & Capabilities, and run on a simulator or your device.

To build and install on a connected iPhone from the command line instead (replace the team ID and device ID with yours; `xcrun devicectl list devices` lists devices):

```bash
xcodebuild -project ios/Morph.xcodeproj -scheme Morph -destination 'generic/platform=iOS' -derivedDataPath ios/build -allowProvisioningUpdates DEVELOPMENT_TEAM=YOURTEAMID build
```

```bash
xcrun devicectl device install app --device YOUR-DEVICE-ID ios/build/Build/Products/Debug-iphoneos/Morph.app
```

The first time, the iPhone needs **Developer Mode** on (Settings → Privacy & Security) and your developer certificate trusted (Settings → General → VPN & Device Management).

## Files

```
MorphApp.swift        app entry, shared state, quick actions, preferences
HomeView.swift        pick files and see recent jobs
ActionsView.swift     action bubbles, progress and results
Intents.swift         Shortcuts actions and Siri phrases
MorphSplash.swift     launch animation
MorphLoader.swift     liquid loader and logo (mirrors the Mac app's copy)
OnboardingView.swift  first-launch intro
SettingsView.swift    compression level and other options
Theme.swift           colors, Liquid Glass and button styles
```

The ffmpeg-only formats from the Mac app are not available on iOS.
