# Google Play submission (Android)

Everything Play Console asks for, field by field, for Morph 1.0.0 (version code 2). Character limits are noted and every field fits.

## Upload

- **App bundle:** build with `cd android && ./gradlew bundleRelease`; it lands at `android/app/build/outputs/bundle/release/app-release.aab`, signed with the upload key `android/morph-release.jks` (kept out of git; back it up, every update must be signed with it).
- **Play App Signing:** leave it on. Google holds the app signing key; the key above is only the upload key.
- **Package name:** `app.morph`. It can never change once published; if Play says it's taken, change `applicationId` in `android/app/build.gradle.kts` first.
- **Target API:** 36, above Play's current minimum.

## Store listing

| Field | Value |
| --- | --- |
| App name (30) | Morph: File Converter |
| Short description (80) | Convert, compress and clean up files on your phone. Nothing is uploaded. |
| App icon | `play-store/icon-512.png` (512 × 512) |
| Feature graphic | `play-store/feature-graphic.png` (1024 × 500) |
| Phone screenshots | `play-store/phone-1-home.png` … `phone-5-dark.png` (1080 × 1920), in that order |
| Category | Tools |
| Tags | File converter, Image editor, Productivity |
| Website | https://morph.geetanshgoyal.in |
| Privacy policy | https://morph.geetanshgoyal.in/privacy.html |
| Contact email | your developer email (Play shows it on the listing) |

**Full description (4000):**

Morph turns any file into the one you need, right on your phone. Pick photos or files, or share them to Morph from any app, and only the actions that fit show up.

Fit any upload limit
Exam forms, job portals and government sites often want a photo under 200 KB, 100 KB or even 20 KB. Set a size limit once and Compress makes a JPG that fits, at the best quality that fits.

Convert
• Photos to JPG, PNG or WEBP, or several into one PDF
• PDF pages to images
• Video to MP4, or pull out the soundtrack as M4A
• SVG to PNG, JPG, WEBP or PDF, and any image traced into a sharp SVG

Compress and clean up
• Shrink photos and videos to a size you can send
• Resize photos and mute videos
• Remove location and camera details from photos before you share
• Read the text in an image
• Zip files together
• One-tap recipes: Web Image, Under 1 MB and Share-Safe Photo

Yours to tune
Choose how strongly to compress, set a size limit, and pick an accent color: Teal Ink, Ultramarine, Green, Magenta or Yellow.

Private by design
Everything happens on your phone. Morph has no internet access at all: nothing is uploaded, there's no account, and your originals are never changed. Results are saved in Downloads › Morph, where any file manager can see them.

## App content (policy declarations)

| Question | Answer |
| --- | --- |
| Privacy policy | https://morph.geetanshgoyal.in/privacy.html (also linked in the app under Settings → Privacy) |
| App access | All functionality is available without special access |
| Ads | No, the app contains no ads |
| Content rating | Questionnaire category "Utility, productivity, communication or other"; answer No to every question. Expect Everyone / PEGI 3 |
| Target audience | 13 and over (picking under 13 brings in the Families policy) |
| News app | No |
| Data safety | Does the app collect or share user data? **No.** Morph declares no internet permission (the one ML Kit would add is removed in the manifest), so nothing can leave the device |
| Government, financial, health features | None |
| Foreground services, sensitive permissions | None; the photo picker is used instead of storage access |

## Testing before production

Personal developer accounts created after November 2023 must run a **closed test** with at least **12 testers opted in for 14 days in a row** before Play allows a production release. Upload the same bundle to a closed testing track, add the testers' Google accounts (an email list or a Google Group), share the opt-in link, and apply for production access once the 14 days are up.

Morph's closed test uses the Google Group [morph-tester](https://groups.google.com/g/morph-tester), added under Closed testing → Testers. Testers join the group, opt in at https://play.google.com/apps/testing/app.morph, then install from the Play Store; the steps for them are on https://morph.geetanshgoyal.in/android.html. Organization accounts skip this step.

## Release notes (500)

First release on Google Play. Convert, compress and clean up files on your phone, fit photos under any upload limit, and pick your own color. Nothing is uploaded.
