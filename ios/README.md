# Morph for iOS

A SwiftUI app built on the same `MorphCore` engine as the Mac app. Pick photos, videos or files, or send them to Morph from any share sheet ("Open in Morph"), then choose an action. Results are saved to the Files app under **On My iPhone → Morph**, and converted photos and videos can go straight to your photo library.

Needs iOS 17 or later. Runs on iPhone and iPad.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

```bash
cd ios && xcodegen
```

Then open `ios/Morph.xcodeproj`, choose your team under Signing & Capabilities, and run on a simulator or your device.

## Files

```
MorphApp.swift        app entry, shared state, preferences
HomeView.swift        pick files and see recent jobs
ActionsView.swift     action bubbles, progress and results
OnboardingView.swift  first-launch intro
SettingsView.swift    compression level and other options
Theme.swift           colors and button styles
```

The ffmpeg-only formats from the Mac app are not available on iOS.
