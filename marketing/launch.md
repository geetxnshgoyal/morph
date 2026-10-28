# Morph launch kit

Copy for the 1.0.0 launch. App Store Connect fields, screenshots and review notes are in [`app-store.md`](app-store.md). Screenshots are in [`docs/images`](../docs/images) and the site is [`docs/index.html`](../docs/index.html), served at https://morph.geetanshgoyal.in.

Facts to keep straight in every post:
- Free and open source. No accounts, no uploads, no tracking.
- Mac: menu bar app, macOS 14 or later, Apple Silicon and Intel. The DMG is signed with Developer ID and notarized by Apple.
- iPhone and iPad: iOS 17 or later. In internal testing on the App Store, out around 11 November 2026.
- Android: Android 10 or later. In closed testing on Google Play, out around 11 November 2026; anyone can join through https://morph.geetanshgoyal.in/android.html (APK on GitHub releases too). Google Play listing and policy answers are in [`play-store.md`](play-store.md).

## Positioning

**One line:** Drag a file, tap a key, drop it on the wheel.

**What it is:** Morph converts, shrinks and cleans up files right where they are, on Mac, iPhone and Android, without uploading anything.

**Who it's for:** people who convert files every week and are tired of upload-and-wait websites: designers sending exports, students turning photos into PDFs or fitting a photo under an exam form's 200 KB limit, anyone who has to get a video under an email limit or strip location data before posting.

**Why it's different:**
1. On the Mac, the tool comes to the file. While dragging anything, a tap of ⇧, ⌘, ⌃ or ⌥ opens a wheel of actions under the cursor. No app to open first.
2. Only actions that fit the file appear, so the wheel stays short.
3. On iPhone, every action is also a Shortcuts action, so Morph slots into automations, Siri and the Action button.
4. Everything runs on the device, results land beside the original, and any job can be undone.

## Taglines

- Drag a file, tap a key, drop it on the wheel.
- Every file format, one tap away.
- Convert anything without uploading anything.
- The file converter that comes to your cursor.

## App Store (iPhone and iPad)

**Subtitle (30):** Convert, compress, clean up

**Promotional text (170):** New: Morph works in Shortcuts. Convert photos, shrink videos, remove location data and pull text from images in your automations, with Siri or the Action button.

**Description:**

Morph turns any file into the one you need, right on your iPhone. Pick photos or files, or send them to Morph from any share sheet, and only the actions that fit show up.

Convert
- Photos to JPG, PNG, HEIC, WEBP, AVIF, TIFF, GIF or BMP, or several into one PDF
- Video to MP4 or MOV, or pull out the soundtrack
- Documents, subtitles and data files between common formats

Clean up
- Compress images, videos and PDFs to a size you can send
- Remove location and camera details before you share
- Blur faces and hide emails, phone and card numbers in screenshots
- Read the text in an image, or what a QR code says

Works with Shortcuts
Convert Images, Compress Files, Remove Metadata, Extract Text, Read Codes, Merge PDFs, or run any Morph action or recipe. Results flow into the next step, so "convert to JPG, then save to Photos" is one tap. Ask Siri, find actions in Spotlight, or put one on the Action button.

Private by design
Everything happens on your device. Nothing is uploaded, there's no account, and your originals are never changed.

**Keywords (100):** convert,converter,heic,jpg,pdf,compress,metadata,exif,shortcuts,ocr,qr,video,mp4,webp,resize

## Mac

**Short description:** A menu bar file converter that opens under your cursor while you drag.

**Long description:**

Morph lives in your menu bar and waits for you to drag a file. Tap ⇧ for the Convert wheel, ⌘ for Tools, ⌃ for Recipes or ⌥ for Actions, and the wheel opens right under the cursor. Drop on an action and the result appears next to the original.

- Convert images, video, audio, documents, subtitles and data
- Compress, resize, strip metadata, blur faces, hide personal info, read text and QR codes
- Merge and split PDFs, zip and extract archives
- Recipes chain several steps into one drop
- Actions send files with AirDrop, Messages or Mail, copy the path, move them, or open Terminal there
- Tap another wheel's keys to switch mid-drag; Esc closes it
- Liquid Glass design that follows your system appearance
- Includes the `morph` command-line tool, with folder watching and undo

## Google Play

**Short description (80):** Convert, compress and clean up files on your phone. Nothing is uploaded.

**Full description:** use the App Store description, replacing the Shortcuts section with: "Share to Morph: in any app, tap Share, then Morph."

## Product Hunt

**Name:** Morph

**Tagline (60):** Drag a file, tap a key, drop it on the wheel

**Description (260):** Morph is a free, open-source file converter for Mac, iPhone and Android. On the Mac, tap a key while dragging any file and a wheel of actions opens under your cursor. On iPhone, every action works in Shortcuts. Nothing is ever uploaded.

**First comment:**

Hi Product Hunt! I built Morph because converting a file shouldn't mean opening a website, uploading something private and waiting.

On the Mac it's a menu bar app with one trick: while you're dragging files anywhere, tap a key. ⇧ opens Convert, ⌘ Tools, ⌃ Recipes, ⌥ Actions. The wheel opens under your cursor, you drop on what you want, and the result lands next to the original. Only actions that make sense for the file show up.

On iPhone, every action is a Shortcuts action too, so you can build "remove location, then share" or "turn these photos into one PDF" and run it from the share sheet, Siri or the Action button.

It's free and open source, and it all runs on your device. I'd love to hear which formats or tools you want next.

## Show HN

**Title:** Show HN: Morph – a local file converter that opens under your cursor mid-drag

**Body:**

Morph is a free, open-source file converter for macOS, iOS and Android. Everything runs locally.

The Mac app is the interesting part. While you drag files from Finder (or anywhere), tapping a modifier key opens a radial menu under the cursor: ⇧ for conversions, ⌘ for tools, ⌃ for multi-step recipes, ⌥ for file actions like AirDrop or "open Terminal here". You drop the files on a petal and the output is written next to the source. No Accessibility or Input Monitoring permission is needed: it polls modifier state and watches the drag pasteboard while the mouse is down. A wheel is chosen when its exact key combination goes down, so a tap is enough and holding extra keys never opens the wrong one.

Conversions use the system frameworks (ImageIO, AVFoundation, PDFKit, Vision for OCR and face blurring), with ffmpeg picked up if installed for WEBM, MP3, FLAC and friends. Outputs never overwrite originals and every job can be undone. There's also a `morph` CLI with recipes and folder watching.

On iOS every action is an App Intent, so it works in Shortcuts, Siri, Spotlight and the Action button.

Source and builds: https://github.com/geetxnshgoyal/morph

## Launch thread (X, Threads, Bluesky)

1. I made Morph: drag a file, tap a key, drop it on the wheel. A free file converter for Mac, iPhone and Android that never uploads anything. [video of the wheel opening mid-drag]
2. On the Mac, tap ⇧ while dragging any file and a wheel of conversions opens under your cursor. ⌘ is tools, ⌃ is recipes, ⌥ is actions like AirDrop. Tap another key to switch wheels. [mac-wheel-convert.png]
3. Only what fits shows up. Drag a video and you get MP4, MOV, GIF, compress, mute. Drag a PDF and you get merge, split, text. [mac-wheel-tools-dark.png]
4. On iPhone, every action is in Shortcuts: convert to JPG, remove location, extract text, read QR codes, merge PDFs. "Remove location from photos with Morph" works with Siri. [ios-home.png]
5. All on device. Results land next to the original, and any job can be undone. Free and open source: https://github.com/geetxnshgoyal/morph

## LinkedIn

Attach `linkedin/linkedin-carousel.pdf` as a document (a swipeable carousel), or the four `linkedin/linkedin-*.png` slides (1080 × 1350) as images. `linkedin/preview.html` shows the whole post with the slides. LinkedIn shows fewer people posts with links in them, so the links can go in the first comment instead.

> I got tired of uploading my files to random converter websites. So I built my own. 🌀
>
> You know the drill: a HEIC photo that won't open, a form that wants your photo under 200 KB, a video too big to email. You search "converter", upload the file to a site you've never heard of, wait, download it, and hope they didn't keep a copy.
>
> Morph does all of that on your own device.
>
> On the Mac, you don't even open an app. Start dragging any file, tap ⇧, and a wheel of actions opens right under your cursor. Drop it on JPG, PDF, Compress or Remove Metadata, and the result lands next to the original.
>
> What it can do:
> → Convert images, video, audio, PDFs, documents, subtitles and CSV/JSON
> → Fit a photo under any upload limit: 200 KB for the exam form, 50 KB for the job portal
> → Strip location data, blur faces, and hide phone and card numbers in screenshots
> → Pull text out of images, read QR codes, merge and split PDFs
>
> It runs on Mac, iPhone, iPad and Android. On iPhone, every action also works in Shortcuts, so it plugs into Siri and the Action button.
>
> The part I care about most: nothing is ever uploaded. The Android app doesn't even ask for internet access.
>
> It's free and open source. No ads, no account, no tracking.
>
> 🖥 Mac and Android: download now at morph.geetanshgoyal.in
> 📱 App Store and Google Play: 11 November
> 💻 Source: github.com/geetxnshgoyal/morph
>
> If you try it, tell me which file it choked on. That's the most useful feedback I can get.
>
> #BuildInPublic #OpenSource #macOS #iOS #Android #Privacy

## r/macapps

**Title:** I made a free, open-source converter that opens under your cursor while you drag a file

**Body:** While dragging any file, tap ⇧ (Convert), ⌘ (Tools), ⌃ (Recipes) or ⌥ (Actions) and a wheel opens right under the cursor; drop on an action and the result appears beside the original. It handles images (incl. HEIC, WEBP, AVIF), video, audio, PDFs, documents, subtitles and data files; compresses to a target size; strips metadata; blurs faces; reads text and QR codes. No uploads, no account, no permissions beyond what you'd expect. The keys are configurable, including combinations. Feedback very welcome, especially on which formats you'd want next.

## Press blurb (about 100 words)

Morph is a free, open-source file converter for Mac, iPhone and Android that works without uploading anything. On the Mac it lives in the menu bar: while dragging a file anywhere, a tap of the Shift, Command, Control or Option key opens a wheel of actions under the cursor, and dropping the file on one writes the result next to the original. It converts images, video, audio, documents and data, compresses files to a target size, strips private metadata, blurs faces and reads text. On iPhone every action works in Shortcuts, Siri and the Action button. Morph is built with Apple's Liquid Glass design.

## Visual assets

| File | Use |
| --- | --- |
| `docs/images/mac-wheel-convert.png` | Hero image, Product Hunt gallery 1 |
| `docs/images/mac-wheel-tools-dark.png` | Dark mode, gallery 2 |
| `docs/images/mac-wheel-actions.png` | Actions wheel, gallery 3 |
| `docs/images/mac-welcome.png` | Onboarding, gallery 4 |
| `docs/images/ios-home.png` | iPhone home |
| `docs/images/ios-actions-dark.png` | iPhone picking an action |
| `docs/images/ios-result.png` | iPhone finished job |
| `docs/images/ios-onboarding.png` | iPhone welcome |

Still to make: a 20–30 second screen recording of a real Finder drag with the wheel opening, switching wheels and dropping. It's the single most convincing asset; record it with the screen recording toolbar (⇧⌘5) at 60 fps.
