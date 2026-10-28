# Morph for the Mac App Store

The menu bar app from `Sources/MorphMac`, built as a sandboxed Mac App Store app. It shares the bundle ID `app.morph.Morph` with the iPhone and iPad app, so the App Store sells all three as one universal purchase. The Developer ID download is built from the same sources by [`scripts/bundle.sh`](../scripts/bundle.sh), without the sandbox.

Version 1.0.0 is in App Store review and comes out around 11 November 2026. The beta is on [TestFlight](https://testflight.apple.com/join/6fFuMydz) for the Mac too; it's early, so expect bugs.

## What the sandbox changes

Morph notices the sandbox at run time (`Sandbox.isActive` in MorphCore), so one set of sources serves both builds:

- **Saving next to the original:** a dropped file can be read but its folder can't be written to. Rather than stop the wheel to ask, results go to Downloads (the `files.downloads.read-write` entitlement) until the user allows saving next to originals, once, from Settings → Output or the welcome guide. Picking the home folder there covers every folder in it; the grant is kept as a security-scoped bookmark (`FolderAccess.swift`) and restored at launch, so Undo keeps working.
- **A chosen output folder** is stored as a bookmark too, so it stays writable after relaunch.
- **Move To…** asks the same way, since moving takes the file out of its folder.
- **Homebrew tools** (ffmpeg for MP3, WebM, FLAC and more; cwebp for WebP) can't run, so those formats don't appear, and the Settings rows that set them up are hidden.
- **The command-line tool** and **Move to Applications** are left out.

Entitlements: App Sandbox, read/write access to user-selected files and to Downloads, and app-scoped bookmarks.

## Build and upload

```bash
cd mac && xcodegen
```

```bash
xcodebuild -project mac/Morph.xcodeproj -scheme Morph -configuration Release -destination 'generic/platform=macOS' -archivePath mac/build/Morph.xcarchive -allowProvisioningUpdates archive
```

Then Xcode → Window → Organizer → Distribute App → App Store Connect, or `xcodebuild -exportArchive` with `method` `app-store-connect` and `destination` `upload`. Automatic signing creates the distribution and installer certificates the first time.

The listing text, review notes and screenshots are in [`marketing/app-store.md`](../marketing/app-store.md).

## Screenshots

Debug builds take launch arguments, so screenshots don't need clicking:

```bash
open -a mac/build/Build/Products/Debug/Morph.app photo.jpg --args -hasSeenWelcome YES -group tool -hover tool.compress
```

`-group` picks the wheel (`convert`, `tool`, `recipe`, `file`), `-hover` highlights an action, `-run` runs one, and `-settings output` opens Settings on a tab. Take wheel shots from the sandboxed build so they only show what the App Store version has.
