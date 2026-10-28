# App Store submission (iPhone and iPad)

Everything App Store Connect asks for, field by field, for Morph 1.0.0 (build 3). Character limits are noted and every field fits.

## App information

| Field | Value |
| --- | --- |
| Name (30) | Morph: File Converter |
| Subtitle (30) | Convert & compress any file |
| Bundle ID | app.morph.Morph |
| SKU | morph-ios |
| Primary category | Utilities |
| Secondary category | Productivity |
| Content rights | Contains no third-party content |
| Age rating | 4+ (answer "None" to every question) |
| Copyright | 2026 Geetansh Goyal |
| Price | Free |

If "Morph: File Converter" is taken, use "Morph – Convert & Compress". The name under the icon on the Home Screen stays "Morph".

## URLs

| Field | URL |
| --- | --- |
| Privacy policy | https://morph.geetanshgoyal.in/privacy.html |
| Support | https://morph.geetanshgoyal.in/support.html |
| Marketing | https://morph.geetanshgoyal.in/ |

The site in `docs/` is deployed on Vercel at morph.geetanshgoyal.in. The privacy link is also in the app under Settings → Privacy, as Apple requires.

## App privacy

Choose **Data Not Collected**. Morph has no accounts, analytics, ads or network requests; files are processed on the device. The bundled privacy manifest (`ios/Morph/PrivacyInfo.xcprivacy`) says the same and declares the one required-reason API it uses, UserDefaults (reason CA92.1), for its own settings.

## Export compliance

Morph uses no encryption of its own. `ITSAppUsesNonExemptEncryption` is `NO` in Info.plist, so App Store Connect won't ask.

## Version 1.0.0

**Promotional text (170):**

New: fit any upload limit. Set 200 KB or 50 KB and Morph makes a JPG that fits, ready for exam forms and job portals. And pick the accent color you like.

**Keywords (100):**

converter,heic,jpg,pdf,compress,resize,kb,size,photo,image,exif,metadata,ocr,qr,webp,video,shortcuts

**Description (4000):**

Morph turns any file into the one you need, right on your iPhone or iPad. Pick photos or files, or send them to Morph from any share sheet, and only the actions that fit show up.

Fit any upload limit
Exam forms, job portals and government sites often want a photo under 200 KB, 100 KB or even 20 KB. Set a size limit once and Compress makes a JPG that fits, at the best quality that fits.

Convert
- Photos to JPG, PNG, HEIC, WEBP, AVIF, TIFF, GIF or BMP, or several into one PDF
- Video to MP4 or MOV, or pull out the soundtrack
- Documents, subtitles and data files between common formats

Compress and clean up
- Shrink photos, videos and PDFs without a visible change. Morph checks every result against the original and tells you when a file is already as small as it can get
- Remove location and camera details before you share
- Blur faces and hide emails, phone and card numbers in screenshots
- Read the text in an image, or what a QR code or barcode says
- Merge PDFs

Works with Shortcuts
Convert Images, Compress Files (with an optional size limit), Remove Metadata, Extract Text, Read QR Codes and Barcodes, Merge PDFs, or run any Morph action or recipe. Results flow into the next step. Ask Siri, find actions in Spotlight, or put one on the Action button. Press and hold the app icon to convert photos straight away.

Yours to tune
Choose how strongly to compress, set a size limit, and pick an accent color: Teal Ink, Ultramarine, Green, Magenta or Yellow.

Private by design
Everything happens on your device. Nothing is uploaded, there's no account, and your originals are never changed. Results are kept in the Files app under On My iPhone → Morph.

**What's New:** First release on the App Store.

## Screenshots

Upload in this order. Files are in `marketing/app-store/`.

| # | iPhone 6.9" (1320 × 2868) | iPad 13" (2064 × 2752) | Caption |
| --- | --- | --- | --- |
| 1 | iphone-1-home.png | ipad-1-home.png | Convert, shrink and clean up any file |
| 2 | iphone-2-actions.png | ipad-2-actions.png | Pick what you need, it runs on your device |
| 3 | iphone-3-result.png | ipad-3-result.png | Fit any upload limit, like 200 KB |
| 4 | iphone-4-settings.png | ipad-4-settings.png | Set a size limit and your own color |
| 5 | iphone-5-dark.png | ipad-5-dark.png | Nothing is uploaded. Ever. |

## Notes for App Review

No account or sign-in is needed, and the app works offline.

To try it: tap Photos, pick any photo, then choose a format such as JPG, or Tools → Compress. Results appear in the Files app under On My iPhone → Morph. To try the size limit, open Settings (the gear), set Size limit to 200 KB, then compress a photo.

Shortcuts: open the Shortcuts app, tap +, search for "Morph" and add Convert Images or Compress Files.

## Before submitting

1. Wait for Apple to approve the developer membership, then in Xcode → Settings → Apple Accounts check that the team no longer says "Personal Team".
2. In Xcode, open `ios/Morph.xcodeproj`, select the Morph target → Signing & Capabilities, and choose the team. Xcode registers `app.morph.Morph`; if that ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml` and run `xcodegen`.
3. In App Store Connect, create the app with the name, bundle ID and SKU above.
4. In Xcode: Product → Archive, then Distribute App → App Store Connect → Upload.
5. Fill in this page's fields, add the screenshots, pick the build and submit for review.

## Mac (macOS 1.0.0)

The Mac App Store build of the menu bar app, added as the macOS platform of the same app (same bundle ID, so it is one universal purchase). App information, privacy, pricing and URLs above are shared. Built from `mac/project.yml`; see [`mac/README.md`](../mac/README.md).

**Promotional text (170):**

Drag a file, tap a key, and a wheel of everything you can do with it opens under your cursor. Set a size limit once and Compress makes a JPG that fits.

**Keywords (100):**

converter,heic,jpg,pdf,compress,resize,svg,menu bar,photo,image,exif,metadata,ocr,qr,video,kb,size

**Description (4000):**

Morph lives in your menu bar and turns any file into the one you need, right where it is. Drop files on the menu bar icon, use Open With or right-click → Services → Open in Morph, or tap a key while you drag files anywhere, and a wheel of actions opens under your cursor. Only the actions that fit the file show up.

Drag shortcuts
While dragging files in Finder or any app, tap ⇧ for Convert, ⌘ for Tools, ⌃ for Recipes or ⌥ for Actions, then drop on the wheel. Tap another key to switch wheels, or Esc to close. Pick your own keys in Settings.

Fit any upload limit
Exam forms, job portals and government sites often want a photo under 200 KB, 100 KB or even 20 KB. Set a size limit once and Compress makes a JPG that fits, at the best quality that fits.

Convert
- Photos to JPG, PNG, HEIC, AVIF, TIFF, GIF or BMP, trace them to SVG, or combine several into one PDF
- Video to MP4 or MOV, or pull out the soundtrack
- Documents, subtitles and data files between common formats

Compress and clean up
- Shrink photos, videos and PDFs without a visible change. Morph checks every result against the original and tells you when a file is already as small as it can get
- Remove location and camera details before you share
- Blur faces and hide emails, phone and card numbers in screenshots
- Read the text in an image, or what a QR code or barcode says
- Merge PDFs, or zip files up

Recipes and actions
One-tap recipes like Web Image, Under 1 MB and Share-Safe Photo. The Actions wheel sends files with AirDrop, Messages or Mail, copies them or their paths, moves them, or opens Terminal there.

Private by design
Everything happens on your Mac. Nothing is uploaded, there's no account, and your originals are never changed. Results are saved to Downloads, next to the original once you allow it in Settings, or in a folder you choose.

Form-ready photos
Set a photo size (passport and visa 600 × 600 or 35 × 45 mm, exam photos, signatures, social posts, or any size) and Resize crops to exactly that size, under your KB limit, with your name and the date printed below when an exam asks for it.

**What's New:** First release on the Mac App Store.

**Screenshots (2880 × 1800), in this order:**

| # | File | Caption |
| --- | --- | --- |
| 1 | mac-1-convert.png | Drop a file. Pick what to make. |
| 2 | mac-2-tools.png | Compress, clean up and read any file |
| 3 | mac-3-result.png | Fit any upload limit, like 200 KB |
| 4 | mac-4-recipes.png | One-tap recipes for everyday jobs |
| 5 | mac-5-settings.png | Set a size limit once. Morph does the rest. |
| 6 | mac-6-dark.png | Nothing is uploaded. Ever. |

**Notes for App Review:**

No account or sign-in is needed, and the app works offline. Morph is a menu bar app (no Dock icon): look for the hexagon icon at the top right of the screen.

To try it: drag any photo onto the menu bar icon and a wheel of actions appears; click PNG. The app is sandboxed, so the PNG is saved to Downloads; to save next to originals instead, open Settings → Output and click Allow… once. You can also hold a file mid-drag in Finder and tap Shift to open the Convert wheel under the cursor, then drop the file on it. To try the size limit, click the menu bar icon → Settings → Output, set Size limit to 200 KB, then use Tools → Compress on a photo.
