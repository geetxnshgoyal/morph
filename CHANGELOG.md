# Changelog

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
- New `file` action group for app-supplied file actions, and a public `Action` initializer so apps can define their own.

## 0.1.0 (2026-10-09)

First release: menu bar app with a drag wheel, `morph` CLI, iOS and Android apps.
