#!/usr/bin/env python3
"""Writes the site's conversion pages (docs/<slug>.html), one per thing people search for: "heic to jpg",
"pdf converter", "mp4 to mp3" and so on. Each page says exactly what Morph does on each platform, so
nobody lands on a promise the app doesn't keep.

    python3 scripts/make-pages.py

Edit PAGES below and rerun; the sitemap's conversion entries are rewritten too.
"""
import html
import json
import pathlib
import re

SITE = "https://morph.geetanshgoyal.in"
DOCS = pathlib.Path(__file__).resolve().parent.parent / "docs"
LAUNCH = "around 11 November 2026"
UPDATED = "2026-10-28"
TESTFLIGHT = "https://testflight.apple.com/join/6fFuMydz"

# Where each platform's download or status lives, for the "Get Morph" block.
GET = [
    ("Mac", f'<a class="button" href="https://github.com/geetxnshgoyal/morph/releases/download/v1.0.0/Morph-1.0.0.dmg">Download for Mac</a> <a class="button quiet" href="{TESTFLIGHT}">Mac App Store beta</a>',
     f"macOS 14 or later, Apple Silicon or Intel. The App Store beta is on TestFlight; it's early and still has bugs."),
    ("Windows", '<a class="button quiet" href="https://apps.microsoft.com/detail/9PHWJVRC85DW">Microsoft Store</a>',
     "Windows 10 (1809) or later and Windows 11."),
    ("Android", '<a class="button quiet" href="android.html">Join the Google Play test</a>',
     f"Android 10 or later. Out for everyone on Google Play {LAUNCH}."),
    ("iPhone and iPad", f'<a class="button quiet" href="{TESTFLIGHT}">Join the TestFlight beta</a>',
     f"iOS 17 or later. On the App Store {LAUNCH}; try the beta now with TestFlight (expect a few bugs)."),
]

# Platform notes reused across pages.
MAC = "Mac"
WIN = "Windows"
IOS = "iPhone and iPad"
AND = "Android"

PAGES = [
    {
        "slug": "heic-to-jpg",
        "title": "HEIC to JPG Converter, Free and Offline | Morph",
        "description": "Convert HEIC photos from your iPhone to JPG on Mac, Windows, iPhone or Android. Free, no upload, no account, and the original stays untouched.",
        "h1": "Convert HEIC to JPG",
        "lede": "iPhones save photos as HEIC, and plenty of websites, forms and older PCs still won't take them. Morph turns them into JPG on your own device, one photo or a hundred at once.",
        "steps": [
            ("Open the photos in Morph", "On a Mac or Windows PC, start dragging the HEIC files and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose JPG", "The Convert wheel only shows formats that fit the file, so JPG is right there."),
            ("Find the JPGs beside the originals", "Each JPG gets the same name and lands next to its HEIC. The HEIC files are never changed."),
        ],
        "where": [
            (MAC, "Yes, plus PNG, WEBP, AVIF, TIFF, GIF, BMP, SVG or PDF."),
            (WIN, "Yes, plus PNG, WEBP, AVIF, TIFF, GIF, BMP, SVG or PDF."),
            (IOS, "Yes, from the Photos picker, the share sheet or Shortcuts."),
            (AND, "Yes, to JPG, PNG or WEBP."),
        ],
        "faq": [
            ("Does converting HEIC to JPG lose quality?", "JPG is a lossy format, so a little detail is traded for compatibility, but Morph saves at high quality and you won't see the difference at normal sizes. Choose PNG instead if you need a lossless copy."),
            ("Can I convert many HEIC photos at once?", "Yes. Select or drag as many as you like; Morph converts them in one go and shows how many finished."),
            ("Are my photos uploaded anywhere?", "No. The conversion runs on your device and Morph makes no network requests."),
        ],
        "related": ["heic-to-png", "heic-to-pdf", "image-converter", "compress-image", "remove-exif"],
    },
    {
        "slug": "pdf-converter",
        "title": "Free PDF Converter: JPG to PDF, PDF to JPG, Word to PDF | Morph",
        "description": "Turn photos into a PDF, PDFs into images or text, Word and Markdown into PDF, and merge, split or compress PDFs. Free, offline, nothing uploaded.",
        "h1": "A PDF converter that never uploads your files",
        "lede": "Scans, forms and contracts are exactly the files you shouldn't hand to a website. Morph does the everyday PDF jobs on your own device.",
        "steps": [
            ("Open the files in Morph", "Drag them and tap Shift on a Mac or Windows PC, or share them to Morph on iPhone and Android."),
            ("Pick the job", "Photos show PDF; a PDF shows Images and Text under Convert, and Compress, Merge and Split under Tools."),
            ("Get the result next to the original", "Morph names the new file after the original and never overwrites anything."),
        ],
        "where": [
            (MAC, "Images to PDF, PDF to images or text, Word (DOCX), ODT, RTF, HTML, Markdown and TXT to PDF, merge, split and compress PDFs, and read text from scanned PDFs."),
            (WIN, "Images to PDF, PDF to images or text, documents to PDF, merge, split and compress PDFs, and read text from scans."),
            (IOS, "Images to PDF, PDF to images or text, RTF, HTML, Markdown and TXT to PDF, merge, split and compress PDFs."),
            (AND, "Images to one PDF, and PDF pages to images."),
        ],
        "faq": [
            ("How do I convert JPG to PDF?", "Select the photos, open them in Morph and choose PDF. They become one PDF, one photo per page, in the order you picked them."),
            ("How do I convert a PDF to JPG?", "Open the PDF in Morph and choose Images. Each page is saved as its own image in a folder named after the PDF."),
            ("Can Morph convert Word to PDF?", "On a Mac and on Windows, yes: DOCX, ODT, RTF, HTML, Markdown and plain text all convert to PDF."),
            ("Is it safe for private documents?", "Yes. Everything runs on your device, with no uploads, no account and no tracking."),
        ],
        "related": ["png-to-pdf", "pdf-to-png", "pdf-to-word", "pdf-to-text", "jpg-to-pdf", "compress-pdf", "merge-pdf", "split-pdf"],
    },
    {
        "slug": "jpg-to-pdf",
        "title": "JPG to PDF: Combine Photos into One PDF, Free | Morph",
        "description": "Combine JPG, PNG or HEIC photos into a single PDF on Mac, Windows, iPhone or Android. Free, works offline, and nothing is uploaded.",
        "h1": "JPG to PDF: turn photos into one PDF",
        "lede": "Receipts, ID scans, homework pages: pick the photos and Morph puts them into a single PDF, one photo per page.",
        "steps": [
            ("Select the photos", "JPG, PNG, HEIC, WEBP and more all work, and you can mix them."),
            ("Choose PDF", "Drag them and tap Shift on a computer, or share them to Morph on your phone, then pick PDF."),
            ("Share the PDF", "It's saved next to the first photo, ready to email or upload."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes, straight from the Photos picker."), (AND, "Yes, straight from the photo picker.")],
        "faq": [
            ("What order do the pages come in?", "The order you selected the photos in."),
            ("Can I make the PDF smaller?", "Yes. On a Mac, Windows or iPhone, use Compress on the finished PDF, or set a size limit before converting the photos."),
            ("Does it need internet?", "No. Morph works fully offline."),
        ],
        "related": ["png-to-pdf", "heic-to-pdf", "pdf-converter", "merge-pdf", "compress-pdf"],
    },
    {
        "slug": "merge-pdf",
        "title": "Merge PDF Files Offline, Free | Morph",
        "description": "Merge several PDFs into one, or split a PDF into pages, on Mac, Windows, iPhone and iPad. Free and private: your documents never leave your device.",
        "h1": "Merge PDFs without uploading them",
        "lede": "Select two or more PDFs and Morph joins them into one, in the order you picked. Split works the other way round, one PDF per page.",
        "steps": [
            ("Select the PDFs", "Two or more, in the order you want them."),
            ("Choose Merge PDFs", "It's on the Tools wheel, or under Tools in the app on iPhone and iPad."),
            ("Done", "The merged PDF is saved next to the first file as Merged.pdf."),
        ],
        "where": [(MAC, "Merge and split."), (WIN, "Merge and split."), (IOS, "Merge and split, and Merge PDFs in Shortcuts."), (AND, "Not yet. Android can turn images into a PDF and PDF pages into images.")],
        "faq": [
            ("Is there a limit on pages or file size?", "No limit is set by Morph; it's only bound by your device's memory."),
            ("Are my PDFs uploaded?", "No. Merging happens on your device."),
        ],
        "related": ["split-pdf", "compress-pdf", "pdf-converter", "jpg-to-pdf"],
    },
    {
        "slug": "mp4-to-mp3",
        "title": "MP4 to MP3: Extract Audio from Video, Free | Morph",
        "description": "Pull the soundtrack out of an MP4 or MOV video as MP3, M4A or WAV. Free and offline on Windows and Mac; M4A on iPhone and Android.",
        "h1": "MP4 to MP3: get the audio out of a video",
        "lede": "Lectures, songs, voice notes recorded as video: Morph saves just the sound, so the file is a fraction of the size.",
        "steps": [
            ("Open the video in Morph", "MP4, MOV and most videos your device can play work."),
            ("Choose an audio format", "The Convert wheel shows the audio formats your device supports next to the video ones."),
            ("Play it anywhere", "The audio file is saved next to the video."),
        ],
        "where": [
            (WIN, "MP3, M4A, WAV and FLAC built in; AIFF, OGG and OPUS with ffmpeg installed."),
            (MAC, "M4A, WAV and AIFF built in. MP3, FLAC, OGG and OPUS in the download from this site once ffmpeg is installed (Morph shows the one command to run). The Mac App Store version makes M4A, WAV and AIFF."),
            (IOS, "M4A, WAV and AIFF. M4A plays everywhere MP3 does, including WhatsApp, Android and Windows."),
            (AND, "M4A."),
        ],
        "faq": [
            ("Why M4A instead of MP3 on some devices?", "MP3 encoding isn't built into macOS, iOS or Android. M4A (AAC) is built in, sounds as good or better at the same size, and plays on practically everything."),
            ("Can I convert MP3 to M4A or WAV too?", "Yes. Audio files convert between the same formats."),
            ("Is the video uploaded?", "No. Morph converts on your device and makes no network requests."),
        ],
        "related": ["mov-to-mp4", "video-to-gif", "compress-image"],
    },
    {
        "slug": "mov-to-mp4",
        "title": "MOV to MP4 Converter, Free and Offline | Morph",
        "description": "Convert MOV videos from iPhone or Mac to MP4 that plays everywhere, or compress a video to send by email. Free, no upload, no watermark.",
        "h1": "Convert MOV to MP4",
        "lede": "iPhone and Mac videos are often MOV, which some apps and websites refuse. Morph converts them to MP4 on your device, with no watermark and no size cap.",
        "steps": [
            ("Open the video in Morph", "Drag and tap Shift on a computer, or share it to Morph on your phone."),
            ("Choose MP4", "Or Compress, to make the video small enough to email or upload."),
            ("Find it beside the original", "The MP4 keeps the original's name."),
        ],
        "where": [
            (MAC, "MP4 and MOV built in, plus WEBM and MKV with ffmpeg in the download from this site."),
            (WIN, "MP4 built in, plus MOV, WEBM and MKV with ffmpeg."),
            (IOS, "MP4 and MOV, and Compress."),
            (AND, "MP4, and Compress."),
        ],
        "faq": [
            ("Is there a watermark or a length limit?", "No watermark, no limit, no account. Morph is free and open source."),
            ("Can I make a video smaller?", "Yes. Use Compress, or set a size limit and Morph aims the video under it."),
        ],
        "related": ["compress-video", "mp4-to-mp3", "video-to-gif"],
    },
    {
        "slug": "video-to-gif",
        "title": "Video to GIF Converter, Free | Morph",
        "description": "Turn a short MP4 or MOV clip into a GIF on Mac, Windows, iPhone or iPad. Free, offline and private.",
        "h1": "Convert video to GIF",
        "lede": "Screen recordings and short clips become GIFs that play anywhere, from chat apps to bug reports.",
        "steps": [
            ("Open the clip in Morph", "Short clips make the best GIFs."),
            ("Choose GIF", "It's on the Convert wheel with the video formats."),
            ("Share it", "The GIF is saved next to the video."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Not yet.")],
        "faq": [
            ("Why is my GIF large?", "GIF is an old format that doesn't compress video well. Keep clips to a few seconds for small files."),
        ],
        "related": ["mp4-to-gif", "mov-to-mp4", "mp4-to-mp3", "image-converter"],
    },
    {
        "slug": "compress-image",
        "title": "Compress Image to 200 KB, 100 KB, 50 KB or 20 KB | Morph",
        "description": "Make a photo fit an upload limit like 200 KB, 100 KB, 50 KB or 20 KB for exam forms and job portals. Free and offline on every device.",
        "h1": "Compress a photo to 200 KB, 100 KB, 50 KB or 20 KB",
        "lede": "Exam forms, job portals and government sites keep asking for photos under a size limit. Set the limit once and Morph makes a JPG that fits, at the best quality that fits.",
        "steps": [
            ("Set a size limit", "In Morph's Settings, pick 20 KB to 5 MB, or type any size."),
            ("Open the photo and choose Compress", "Drag and tap ⌘ (Ctrl on Windows) for the Tools wheel, or pick Compress on your phone."),
            ("Upload it", "Morph shows the new size, like 2.3 MB → 198 KB. If a JPG is already small enough, it's left alone."),
        ],
        "where": [(MAC, "Yes, for photos, videos and PDFs."), (WIN, "Yes, for photos, videos and PDFs."), (IOS, "Yes, and in Shortcuts with a size in KB."), (AND, "Yes, for photos and videos.")],
        "faq": [
            ("How do I reduce a photo to exactly 200 KB?", "Set the size limit to 200 KB and use Compress. Morph finds the highest quality that stays under 200 KB; the result is usually just below it, such as 198 KB."),
            ("Will the photo look worse?", "Morph checks each result against the original. Without a size limit it only keeps changes you can't see; with a tight limit like 20 KB it shrinks the photo as needed to fit."),
            ("Can I compress many photos at once?", "Yes, and each one is fitted under the limit."),
        ],
        "related": ["passport-photo-size", "heic-to-jpg", "image-converter", "compress-pdf", "compress-video"],
    },
    {
        "slug": "png-to-svg",
        "title": "PNG to SVG: Convert Images to Vector, Free | Morph",
        "description": "Trace a PNG or JPG logo, icon or drawing into a real vector SVG with clean curves. Free and offline on Mac, Windows, iPhone and Android.",
        "h1": "Convert PNG or JPG to SVG",
        "lede": "Morph traces an image into real vector shapes: a small palette, specks cleaned up, outlines smoothed into curves with sharp corners kept. Logos, icons and screenshots come out clean and often smaller than the PNG.",
        "steps": [
            ("Open the image in Morph", "PNG, JPG and every other image format work."),
            ("Choose SVG", "Compression level sets the detail: Light keeps more colors and finer edges, Strong makes the smallest file."),
            ("Open it in any editor", "The SVG works in browsers, Figma, Illustrator and Inkscape."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Is this a real vector or a PNG inside an SVG?", "A real vector: shapes and curves, not an embedded bitmap. That's why it scales without blur."),
            ("What works best?", "Logos, icons, text and flat drawings. Photos trace into a stylised poster look."),
        ],
        "related": ["jpg-to-svg", "svg-to-png", "svg-to-pdf", "image-converter"],
    },
    {
        "slug": "svg-to-png",
        "title": "SVG to PNG Converter, Free and Offline | Morph",
        "description": "Turn SVG files into sharp PNG, JPG, WEBP or PDF on Mac, Windows, iPhone or Android. Free, offline and private.",
        "h1": "Convert SVG to PNG",
        "lede": "Drop an SVG and get a sharp PNG, JPG, WEBP, HEIC or PDF. Icons render at least 1024 px on the long side so they come out usable.",
        "steps": [
            ("Open the SVG in Morph", ""),
            ("Choose PNG", "Or set Max size first to get an exact width."),
            ("Done", "The PNG lands next to the SVG."),
        ],
        "where": [(MAC, "Yes, and PDFs stay vectors."), (WIN, "Yes."), (IOS, "Yes, and PDFs stay vectors."), (AND, "Yes.")],
        "faq": [
            ("Does Morph load images linked from the web inside an SVG?", "No. Morph never goes online, so linked web images are skipped."),
        ],
        "related": ["svg-to-pdf", "png-to-svg", "jpg-to-svg", "image-converter"],
    },
    {
        "slug": "webp-to-jpg",
        "title": "WEBP to JPG or PNG Converter, Free | Morph",
        "description": "Convert WEBP images saved from the web into JPG or PNG that every app opens. Free and offline on Mac, Windows, iPhone and Android.",
        "h1": "Convert WEBP to JPG or PNG",
        "lede": "Images saved from websites are often WEBP, which some apps still can't open. Morph turns them into JPG or PNG on your device.",
        "steps": [
            ("Open the WEBP files in Morph", ""),
            ("Choose JPG or PNG", "PNG keeps transparency; JPG makes smaller files."),
            ("Done", "The new image lands next to the original."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes, and to WEBP too."), (IOS, "Yes."), (AND, "Yes, and to WEBP too.")],
        "faq": [
            ("Can I convert to WEBP as well?", "Yes on Windows and Android, and on a Mac in the download from this site once the free webp tools are installed."),
        ],
        "related": ["webp-to-png", "png-to-webp", "avif-to-jpg", "image-converter"],
    },
    {
        "slug": "compress-pdf",
        "title": "Compress PDF Offline, Free | Morph",
        "description": "Make a PDF smaller to email or upload, on Mac, Windows, iPhone and iPad. Text stays selectable. Free, and the PDF never leaves your device.",
        "h1": "Compress a PDF",
        "lede": "Scanned PDFs and documents full of photos get huge. Morph re-saves the images inside at screen resolution, so the file shrinks a lot while text stays sharp and selectable.",
        "steps": [
            ("Open the PDF in Morph", "Drag it and tap ⌘ (Ctrl on Windows) for the Tools wheel, or share it to Morph on iPhone and iPad."),
            ("Choose Compress", "Morph shows the new size, like 8.4 MB → 1.2 MB."),
            ("Send it", "The smaller PDF is saved next to the original, which stays untouched."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes, and in Shortcuts with Compress Files."), (AND, "Not yet. Android compresses photos and videos.")],
        "faq": [
            ("Will the text still be selectable?", "Yes. Morph only re-encodes the images inside the PDF; text and vector drawings are kept as they are."),
            ("Why didn't my PDF get smaller?", "PDFs that are mostly text are already small. Morph says so instead of making a bigger file."),
            ("Is it safe for confidential documents?", "Yes. Nothing is uploaded; the PDF is processed on your device."),
        ],
        "related": ["pdf-converter", "merge-pdf", "split-pdf", "pdf-to-jpg"],
    },
    {
        "slug": "pdf-to-jpg",
        "title": "PDF to JPG or PNG: Save PDF Pages as Images, Free | Morph",
        "description": "Turn every page of a PDF into an image on Mac, Windows, iPhone or Android. Free, offline, and the PDF is never uploaded.",
        "h1": "PDF to JPG: save each page as an image",
        "lede": "Need a page of a PDF as a picture for a form, a slide or a chat? Morph saves every page as a sharp image, all in one folder.",
        "steps": [
            ("Open the PDF in Morph", "Drag and tap Shift on a computer, or share it to Morph on your phone."),
            ("Choose Images", "Each page is saved as a PNG in a folder named after the PDF."),
            ("Want JPG?", "Select the page images and choose JPG. It takes one more tap and makes smaller files."),
        ],
        "where": [(MAC, "Yes, and PDF to text too."), (WIN, "Yes, and PDF to text too."), (IOS, "Yes, and PDF to text too."), (AND, "Yes.")],
        "faq": [
            ("Why PNG first?", "PNG keeps text and lines perfectly sharp. Convert to JPG afterwards if you need smaller files or a site only accepts JPG."),
            ("Can I get just one page?", "Morph saves every page; keep the one you need and delete the rest, or use Split PDF on a Mac, Windows PC or iPhone."),
        ],
        "related": ["pdf-converter", "split-pdf", "image-converter", "compress-pdf"],
    },
    {
        "slug": "split-pdf",
        "title": "Split PDF into Pages, Free and Offline | Morph",
        "description": "Split a PDF into one file per page on Mac, Windows, iPhone or iPad. Free and private: the document never leaves your device.",
        "h1": "Split a PDF into pages",
        "lede": "Pull the pages of a PDF apart: Morph saves one PDF per page in a folder named after the original, ready to send just the page someone needs.",
        "steps": [
            ("Open the PDF in Morph", ""),
            ("Choose Split PDF", "It's on the Tools wheel, or under Tools in the app on iPhone and iPad."),
            ("Pick the pages you need", "Each page is its own PDF, numbered in order."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Not yet.")],
        "faq": [
            ("Can I put pages back together?", "Yes. Select the page PDFs in the order you want and choose Merge PDFs."),
        ],
        "related": ["merge-pdf", "pdf-to-jpg", "compress-pdf", "pdf-converter"],
    },
    {
        "slug": "word-to-pdf",
        "title": "Convert Word to PDF on Mac or Windows, Free | Morph",
        "description": "Turn DOCX, ODT, RTF, HTML or Markdown into PDF on a Mac or Windows PC, without Word and without uploading. Free and open source.",
        "h1": "Convert Word to PDF on Mac or Windows",
        "lede": "No Word installed, or don't want to upload a contract to a website? Morph turns DOCX and other documents into PDF on your own computer, and PDF back into DOCX or text.",
        "steps": [
            ("Start dragging the document", "In Finder or File Explorer, start dragging the DOCX and tap Shift."),
            ("Drop it on PDF", "The Convert wheel opens under your cursor."),
            ("Done", "The PDF is saved next to the document."),
        ],
        "where": [
            (MAC, "DOCX, ODT, RTF, HTML, Markdown and TXT to PDF, and back to DOCX, ODT, RTF, HTML, Markdown or TXT."),
            (WIN, "DOCX, ODT, RTF, HTML, Markdown and TXT to PDF, and back."),
            (IOS, "RTF, HTML, Markdown and TXT to PDF."),
            (AND, "Not yet."),
        ],
        "faq": [
            ("Does it keep the formatting?", "Headings, paragraphs, bold and italics, lists and simple tables carry over. Complex layouts with text boxes and floating images may come out simpler; for those, Word's own Save as PDF keeps them exactly."),
            ("Do I need Microsoft Word?", "No. Morph reads the document itself."),
        ],
        "related": ["pdf-converter", "compress-pdf", "merge-pdf"],
    },
    {
        "slug": "passport-photo-size",
        "title": "Passport Photo Size: 600×600 Under 50 KB, Free | Morph",
        "description": "Make a passport, visa or exam photo the exact size a form asks for, like 600×600 or 35×45 mm, under 20, 50 or 200 KB. Free and offline.",
        "h1": "Make a passport or exam photo the exact size the form asks for",
        "lede": "Online passport, visa, exam and job applications check two things: the photo's size in pixels (like 600 × 600, or 35 × 45 mm) and its file size (like under 50 KB). Morph does both in one step, and can print your name and the date under the photo when an exam asks for it.",
        "steps": [
            ("Set the photo size", "In Morph's Settings, under Photo size, pick a preset (US or India passport 600 × 600, Schengen or UK 35 × 45 mm, exam 3.5 × 4.5 cm, bank exams 200 × 230) or type the size from the form."),
            ("Set the size limit, and a name if the exam wants one", "Pick or type the KB limit, like 50 KB. For exams that want the name and date under the photo, type the name."),
            ("Choose Resize and upload", "Morph crops the photo to exactly that size, keeping the face area, and saves a JPG under the limit, with location data removed."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("How does Morph crop it?", "It scales the photo to cover the size and trims the edges, trimming a little more from the bottom than the top so heads aren't cut off. For the best result, start from a photo with some space around the face."),
            ("Can it add my name and the date below the photo?", "Yes. Type the name under Photo size and Morph adds a white strip at the bottom with the name and the date the photo was taken, inside the exact size."),
            ("Will the photo be accepted?", "Morph saves a normal JPG at the exact pixel size and under the limit you set, which is what these forms check. The form's own rules for background, lighting and framing still apply."),
            ("Is my photo uploaded?", "No. Morph runs on your device, so your ID photo stays with you."),
        ],
        "related": ["signature-resize", "resize-image-pixels", "compress-image", "heic-to-jpg"],
    },
    {
        "slug": "signature-resize",
        "title": "Resize Signature for Online Forms: 140×60 Under 20 KB | Morph",
        "description": "Make a scanned or photographed signature the exact size an exam or job form asks for, like 140×60 pixels under 20 KB. Free and offline.",
        "h1": "Resize a signature for an online form",
        "lede": "Exam, bank and government forms often want the signature at an exact size like 140 × 60 or 280 × 120 pixels and under 10 to 20 KB. Morph makes a JPG that matches both.",
        "steps": [
            ("Photograph or scan the signature", "Black or blue ink on white paper, filling most of the frame."),
            ("Set the photo size and the size limit", "In Morph's Settings, pick Signature, small (140 × 60) or large (280 × 120), or type the form's size, then set the KB limit, like 20 KB."),
            ("Choose Resize", "The signature is cropped to exactly that size and saved as a JPG under the limit."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("My signature got cut off. What now?", "Morph crops to fill the size, so leave a little space around the signature, and crop the photo to roughly the right shape first if it's very tall or wide."),
            ("Can I do the photo and the signature together?", "Do them one after the other: they need different sizes, so change Photo size in between."),
        ],
        "related": ["passport-photo-size", "resize-image-pixels", "compress-image"],
    },
    {
        "slug": "resize-image-pixels",
        "title": "Resize Image to Exact Pixels: 600×600, 1080×1080 | Morph",
        "description": "Resize and crop an image to exact pixels, like 600×600 for forms or 1080×1080 for Instagram, on Mac, Windows, iPhone or Android. Free.",
        "h1": "Resize an image to exact pixels",
        "lede": "Need exactly 600 × 600, 1080 × 1080 or 1920 × 1080? Morph crops the image to fill that size, so there are no stretched faces and no white bars, and it can keep the file under a size limit too.",
        "steps": [
            ("Set the photo size", "In Morph's Settings, under Photo size, pick a preset (square post 1080 × 1080, story 1080 × 1920, Full HD, profile picture 400 × 400 and more) or type any width × height."),
            ("Open the images and choose Resize", "One image or a batch; each comes out at exactly that size."),
            ("Done", "The resized JPG lands next to the original, named with the size, like photo 1080x1080.jpg."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Will it stretch my photo?", "No. Morph keeps the proportions and trims the edges to fit, rather than squashing the picture."),
            ("Can I just make an image smaller without cropping?", "Yes: set Photo size to Off and Resize fits the longest side to 2048 pixels, keeping the whole picture."),
        ],
        "related": ["passport-photo-size", "signature-resize", "image-converter", "compress-image"],
    },
    {
        "slug": "compress-video",
        "title": "Compress Video for Email or WhatsApp, Free | Morph",
        "description": "Make a video small enough to email, upload or send, on Mac, Windows, iPhone or Android. Free, no watermark, and nothing is uploaded.",
        "h1": "Compress a video to send it",
        "lede": "Phone videos are huge. Morph re-encodes them at a sensible size so they fit email and upload limits, with no watermark and no length cap.",
        "steps": [
            ("Open the video in Morph", ""),
            ("Choose Compress", "Or set a size limit first, and Morph aims the video under it."),
            ("Send it", "The smaller video is saved next to the original."),
        ],
        "where": [
            (MAC, "Yes, and size limits are most precise with ffmpeg installed (download from this site)."),
            (WIN, "Yes."),
            (IOS, "Yes, stepping down through export sizes to fit a limit."),
            (AND, "Yes, choosing a bitrate from the video's length to fit a limit."),
        ],
        "faq": [
            ("How small can it get?", "That depends on the length. A one-minute clip fits a few megabytes easily; an hour-long video won't fit 25 MB without looking rough."),
            ("Is there a watermark?", "No. Morph is free and open source, with no watermark and no account."),
        ],
        "related": ["mov-to-mp4", "mp4-to-mp3", "video-to-gif", "compress-image"],
    },
    {
        "slug": "png-to-jpg",
        "title": "PNG to JPG Converter, Free and Offline | Morph",
        "description": "Convert PNG screenshots and images to JPG, or JPG to PNG, on Mac, Windows, iPhone or Android. Batch convert, free, nothing uploaded.",
        "h1": "Convert PNG to JPG, or JPG to PNG",
        "lede": "JPG makes smaller files for photos and screenshots; PNG keeps transparency and sharp edges. Morph converts either way, one file or a whole folder's worth.",
        "steps": [
            ("Open the images in Morph", "Drag and tap Shift on a computer, or share them to Morph on your phone."),
            ("Choose JPG or PNG", ""),
            ("Done", "Converted images land next to the originals."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("What happens to transparency in JPG?", "JPG has no transparency, so transparent areas are filled with white."),
            ("Which is smaller?", "JPG, usually by a lot for photos. For screenshots with flat colors, PNG can be smaller and sharper."),
        ],
        "related": ["jpg-to-png", "png-to-pdf", "png-to-webp", "image-converter", "compress-image"],
    },
    {
        "slug": "png-to-pdf",
        "title": "PNG to PDF Converter: Combine Images into One PDF | Morph",
        "description": "Convert PNG screenshots and images to PDF, one file or many in a single PDF, on Mac, Windows, iPhone or Android. Free and offline.",
        "h1": "Convert PNG to PDF",
        "lede": "Screenshots, scans and diagrams saved as PNG turn into a PDF you can email, print or upload. Pick one PNG for a one-page PDF, or several to get them all in one PDF, a page each.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose PDF", "It's on the Convert wheel. Several PNGs become one PDF in the order you picked them."),
            ("Done", "The PDF is saved next to the first PNG."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Will the PDF be sharp?", "Yes. Each PNG goes in at its full resolution, so text in screenshots stays crisp."),
            ("Can I mix PNG and JPG?", "Yes. Any images can go in one PDF, in the order you pick them."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["pdf-to-png", "jpg-to-pdf", "pdf-converter", "compress-pdf"],
    },
    {
        "slug": "pdf-to-png",
        "title": "PDF to PNG Converter: Every Page as an Image | Morph",
        "description": "Save each page of a PDF as a sharp PNG image, on Mac, Windows, iPhone or Android. Free, offline, and the PDF is never uploaded.",
        "h1": "Convert PDF to PNG",
        "lede": "Need a PDF page as a picture for a slide, a chat or a form? Morph saves every page as a high-resolution PNG, all in one folder named after the PDF.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose Images", "Each page becomes a PNG, numbered page 001, page 002 and so on."),
            ("Use the pages you need", "The folder is saved next to the PDF."),
        ],
        "where": [(MAC, "Yes, rendered at twice the page size for sharp text."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Why PNG and not JPG?", "PNG keeps text and lines perfectly sharp. If a site only takes JPG, select the PNGs and convert them to JPG in one more step."),
            ("Can I get the text instead?", "Yes, on Mac, Windows, iPhone and iPad: choose Text to save the PDF's words as a text file."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["pdf-to-jpg", "png-to-pdf", "pdf-to-text", "pdf-converter"],
    },
    {
        "slug": "jpg-to-png",
        "title": "JPG to PNG Converter, Free and Offline | Morph",
        "description": "Convert JPG photos to PNG on Mac, Windows, iPhone or Android, one file or a whole batch. Free, private, and nothing is uploaded.",
        "h1": "Convert JPG to PNG",
        "lede": "PNG is lossless, so further edits don't add more JPG blur, and many design tools and upload forms prefer it. Morph converts any number of JPGs to PNG at once.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose PNG", ""),
            ("Done", "Each PNG lands next to its JPG; the JPGs aren't touched."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Will PNG look better than the JPG?", "It keeps exactly what's in the JPG without losing more, but it can't bring back detail the JPG already lost."),
            ("Why is the PNG bigger?", "PNG doesn't throw away detail like JPG does, so photos come out larger. For screenshots and graphics the difference is small."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["png-to-jpg", "image-converter", "heic-to-png", "png-to-svg"],
    },
    {
        "slug": "heic-to-png",
        "title": "HEIC to PNG Converter, Free and Offline | Morph",
        "description": "Convert iPhone HEIC photos to PNG on Mac, Windows, iPhone or Android. Batch convert, keep full quality, nothing uploaded.",
        "h1": "Convert HEIC to PNG",
        "lede": "Need a lossless copy of an iPhone photo for editing or a site that won't take HEIC? Morph turns HEIC into PNG at full quality.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose PNG", "Choose JPG instead if you want smaller files."),
            ("Done", "The PNGs land next to the HEIC photos."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("HEIC to PNG or HEIC to JPG?", "PNG keeps every pixel and is best for editing; JPG is much smaller and fine for sharing and upload forms."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["heic-to-jpg", "heic-to-pdf", "jpg-to-png", "image-converter"],
    },
    {
        "slug": "heic-to-pdf",
        "title": "HEIC to PDF Converter: iPhone Photos to One PDF | Morph",
        "description": "Turn iPhone HEIC photos into a PDF, one photo per page, on Mac, Windows, iPhone or Android. Free and offline.",
        "h1": "Convert HEIC to PDF",
        "lede": "Photos of documents, receipts or homework taken on an iPhone are saved as HEIC. Morph puts them straight into one PDF, ready to send.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose PDF", "Pick the photos in the order you want the pages."),
            ("Send it", "The PDF is saved next to the first photo."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Can I make the PDF smaller?", "Yes, on Mac, Windows and iPhone: use Compress on the finished PDF."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["heic-to-jpg", "jpg-to-pdf", "png-to-pdf", "compress-pdf"],
    },
    {
        "slug": "webp-to-png",
        "title": "WEBP to PNG Converter, Free and Offline | Morph",
        "description": "Convert WEBP images saved from the web to PNG, keeping transparency, on Mac, Windows, iPhone or Android. Free, nothing uploaded.",
        "h1": "Convert WEBP to PNG",
        "lede": "Images saved from websites are often WEBP, which older apps can't open. Morph converts them to PNG and keeps any transparent background.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose PNG", ""),
            ("Done", "Each PNG lands next to its WEBP."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Does transparency survive?", "Yes. PNG keeps transparent areas; JPG would fill them with white."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["webp-to-jpg", "png-to-webp", "image-converter", "png-to-jpg"],
    },
    {
        "slug": "png-to-webp",
        "title": "PNG to WEBP and JPG to WEBP Converter | Morph",
        "description": "Make images smaller for your website by converting PNG or JPG to WEBP, on Windows, Android or Mac. Free and offline.",
        "h1": "Convert PNG or JPG to WEBP",
        "lede": "WEBP images are usually a third smaller than JPG or PNG at the same look, so pages load faster. The Web Image recipe resizes to 1600 px and converts to WEBP in one step.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose WEBP", "Or use the Web Image recipe to resize and convert at once."),
            ("Upload", "The WEBP files land next to the originals."),
        ],
        "where": [(MAC, "In the download from this site, once the free webp tools are installed (Morph shows the one command)."), (WIN, "Yes."), (IOS, "Not yet: iOS can read WEBP but not write it. Morph makes AVIF or HEIC instead, which are just as small."), (AND, "Yes.")],
        "faq": [
            ("Do all browsers show WEBP?", "Yes, every current browser does."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["webp-to-png", "webp-to-jpg", "compress-image", "image-converter"],
    },
    {
        "slug": "avif-to-jpg",
        "title": "AVIF to JPG Converter, Free and Offline | Morph",
        "description": "Convert AVIF images to JPG or PNG that every app opens, on Mac, Windows, iPhone or Android. Free, nothing uploaded.",
        "h1": "Convert AVIF to JPG",
        "lede": "AVIF is a new, very small image format some sites now serve, but many apps can't open it yet. Morph turns it into a JPG or PNG that works everywhere.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose JPG or PNG", ""),
            ("Done", "The converted image lands next to the AVIF."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes, on Android 12 and later.")],
        "faq": [
            ("Can Morph make AVIF too?", "Yes, on Mac, Windows and iPhone: choose AVIF on the Convert wheel."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["webp-to-jpg", "heic-to-jpg", "image-converter", "png-to-jpg"],
    },
    {
        "slug": "svg-to-pdf",
        "title": "SVG to PDF Converter: Keep It Vector | Morph",
        "description": "Convert SVG logos and drawings to a PDF that stays vector, sharp at any zoom, on Mac, Windows, iPhone or Android. Free and offline.",
        "h1": "Convert SVG to PDF",
        "lede": "Need a logo or diagram as a PDF for print or a client? Morph puts the SVG into a PDF without turning it into pixels, so it stays sharp at any size.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose PDF", "Several SVGs become one PDF, a page each."),
            ("Done", "The PDF is saved next to the SVG."),
        ],
        "where": [(MAC, "Yes, and the PDF stays vector."), (WIN, "Yes."), (IOS, "Yes, and the PDF stays vector."), (AND, "Yes, and the PDF stays vector.")],
        "faq": [
            ("Will text in the SVG stay text?", "Shapes and paths stay vector. Morph never goes online, so images the SVG links to on the web are skipped."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["svg-to-png", "png-to-svg", "png-to-pdf", "pdf-converter"],
    },
    {
        "slug": "jpg-to-svg",
        "title": "JPG to SVG Converter: Trace a Photo into Vector | Morph",
        "description": "Trace a JPG logo, icon or sketch into a real vector SVG with smooth curves, on Mac, Windows, iPhone or Android. Free, offline.",
        "h1": "Convert JPG to SVG",
        "lede": "Got a logo only as a JPG? Morph traces it into real vector shapes with a small palette and smooth curves, so it scales without blur and edits in any vector app.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose SVG", "Compression level sets the detail: Light keeps more colors, Strong makes the smallest file."),
            ("Edit it", "Open the SVG in Figma, Illustrator, Inkscape or a browser."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Yes.")],
        "faq": [
            ("Does it work on photos?", "It works best on logos, icons, text and flat drawings. Photos come out as a stylised poster."),
            ("Is it a real vector?", "Yes: paths and curves, not a JPG wrapped in an SVG."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["png-to-svg", "svg-to-png", "svg-to-pdf", "image-converter"],
    },
    {
        "slug": "pdf-to-word",
        "title": "PDF to Word (DOCX) on Mac or Windows, Free | Morph",
        "description": "Get the text of a PDF into an editable Word document on a Mac or Windows PC, without uploading it. Free and open source.",
        "h1": "Convert PDF to Word",
        "lede": "Morph pulls the text and paragraphs out of a PDF into a DOCX you can edit in Word, Pages or Google Docs, on your own computer.",
        "steps": [
            ("Start dragging the PDF", "In Finder or File Explorer, start dragging it and tap Shift."),
            ("Drop it on DOCX", "The Convert wheel opens under your cursor."),
            ("Edit it", "The DOCX is saved next to the PDF."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Not yet: iPhone and iPad can save a PDF's text as a text file."), (AND, "Not yet.")],
        "faq": [
            ("Does it keep the layout?", "It keeps the text and paragraphs, which is what you need to edit or reuse the words. Columns, images and exact positions aren't carried over."),
            ("What about scanned PDFs?", "A scan is a picture of text. Use Extract Text first to read the words, then paste them into a document."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["word-to-pdf", "pdf-to-text", "pdf-converter", "image-to-text"],
    },
    {
        "slug": "pdf-to-text",
        "title": "PDF to Text: Copy the Text out of a PDF | Morph",
        "description": "Save all the text in a PDF as a plain text file, or read scanned PDFs, on Mac, Windows, iPhone and iPad. Free and offline.",
        "h1": "Get the text out of a PDF",
        "lede": "Morph saves every word of a PDF as a plain text file you can search, copy or paste anywhere. For scanned PDFs, Extract Text reads the words from the page images.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose Text", "Or Extract Text on the Tools wheel for a scanned PDF."),
            ("Copy what you need", "The text file is saved next to the PDF."),
        ],
        "where": [(MAC, "Yes, and scanned PDFs too."), (WIN, "Yes, and scanned PDFs too."), (IOS, "Yes, and scanned PDFs too."), (AND, "Not yet: Android reads text from photos and screenshots.")],
        "faq": [
            ("Does it work on scans?", "Yes, with Extract Text, which uses the text recognition built into your device. It runs offline."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["pdf-to-word", "image-to-text", "pdf-to-png", "pdf-converter"],
    },
    {
        "slug": "mp4-to-gif",
        "title": "MP4 to GIF Converter, Free and Offline | Morph",
        "description": "Turn a short MP4 or MOV clip into a GIF on Mac, Windows, iPhone or iPad. Free, no watermark, nothing uploaded.",
        "h1": "Convert MP4 to GIF",
        "lede": "Screen recordings and short clips become GIFs that play anywhere, from Slack and GitHub to chat apps. No watermark, no account.",
        "steps": [
            ("Open the files in Morph", "On a Mac or Windows PC, start dragging them and tap Shift. On iPhone or Android, share them to Morph or pick them in the app."),
            ("Choose GIF", "It's on the Convert wheel next to the video formats."),
            ("Share it", "The GIF is saved next to the video."),
        ],
        "where": [(MAC, "Yes."), (WIN, "Yes."), (IOS, "Yes."), (AND, "Not yet.")],
        "faq": [
            ("How long can the clip be?", "Morph uses the first 30 seconds. Shorter clips make smaller GIFs."),
            ("Is there a watermark?", "No. Morph is free and open source."),
            ("Are my files uploaded?", "No. Morph converts on your own device and makes no network requests, so nothing leaves it."),
        ],
        "related": ["video-to-gif", "mov-to-mp4", "compress-video", "mp4-to-mp3"],
    },
    {
        "slug": "image-converter",
        "title": "Image Converter: JPG, PNG, HEIC, WEBP, AVIF, SVG | Morph",
        "description": "Convert images between JPG, PNG, HEIC, WEBP, AVIF, TIFF, GIF, BMP, SVG and PDF, resize them or shrink them to a size limit. Free and offline.",
        "h1": "Image converter for every format",
        "lede": "JPG, PNG, HEIC, WEBP, AVIF, TIFF, GIF, BMP, SVG and PDF. Morph only shows the formats that fit the file and your device, and converts a whole batch at once.",
        "steps": [
            ("Open the images in Morph", "On a computer, drag them and tap Shift. On a phone, share them to Morph."),
            ("Pick a format", "Or Resize, Compress or Remove Metadata from the Tools wheel."),
            ("Find them beside the originals", "Originals are never overwritten."),
        ],
        "where": [
            (MAC, "JPG, PNG, HEIC, AVIF, TIFF, GIF, BMP, SVG and PDF, plus WEBP in the download from this site with the free webp tools."),
            (WIN, "JPG, PNG, WEBP, AVIF, TIFF, GIF, BMP, SVG and PDF, and HEIC where the PC can encode it."),
            (IOS, "JPG, PNG, HEIC, AVIF, TIFF, GIF, BMP, SVG and PDF."),
            (AND, "JPG, PNG, WEBP, SVG and PDF."),
        ],
        "faq": [
            ("Which format should I pick?", "JPG for photos, PNG for screenshots and anything with transparency, SVG for logos, HEIC or AVIF for the smallest photos on newer devices."),
            ("Can I resize at the same time?", "Yes. Use Resize, or the Web Image recipe, which resizes to 1600 px and converts in one step."),
        ],
        "related": ["png-to-jpg", "jpg-to-png", "heic-to-jpg", "webp-to-png", "avif-to-jpg", "png-to-webp", "png-to-svg", "compress-image"],
    },
    {
        "slug": "remove-exif",
        "title": "Remove Location and EXIF Data from Photos, Free | Morph",
        "description": "Strip GPS location, camera details and other metadata from photos and videos before you share them. Free and offline on every device.",
        "h1": "Remove location and EXIF data from photos",
        "lede": "Photos carry where they were taken, the camera, and the time. Remove Metadata strips it before you post or send, and the Share-Safe Photo recipe also resizes in one step.",
        "steps": [
            ("Open the photos or videos in Morph", ""),
            ("Choose Remove Metadata", "It's on the Tools wheel, or under Tools in the app."),
            ("Share the clean copy", "The original keeps its metadata; the copy has none."),
        ],
        "where": [(MAC, "Photos, videos and audio."), (WIN, "Photos, videos and audio."), (IOS, "Photos, videos and audio, and in Shortcuts."), (AND, "Photos.")],
        "faq": [
            ("What gets removed?", "GPS location, camera make and model, dates, and other EXIF, IPTC and XMP fields. The picture itself is unchanged."),
            ("Can Morph also hide faces or phone numbers?", "Yes, on Mac, Windows, iPhone and iPad: Blur Faces and Hide Personal Info cover faces, emails, phone and card numbers in screenshots."),
        ],
        "related": ["compress-image", "heic-to-jpg", "image-to-text"],
    },
    {
        "slug": "image-to-text",
        "title": "Image to Text (OCR) and QR Reader, Offline | Morph",
        "description": "Copy the text out of a photo, screenshot or scanned PDF, or read a QR code or barcode. Free, offline and private.",
        "h1": "Image to text: copy the words out of a photo",
        "lede": "Extract Text reads the words in a photo, screenshot or scanned PDF and saves them as a text file. Read QR shows what a QR code or barcode says, without opening a link.",
        "steps": [
            ("Open the image or PDF in Morph", ""),
            ("Choose Extract Text or Read QR", "Both are on the Tools wheel."),
            ("Copy the text", "It's saved next to the original as a .txt file."),
        ],
        "where": [(MAC, "Extract Text and Read QR."), (WIN, "Extract Text and Read QR."), (IOS, "Extract Text and Read QR, and both in Shortcuts."), (AND, "Extract Text, fully offline.")],
        "faq": [
            ("Does text recognition need internet?", "No. It uses the recognition built into your device, so nothing is sent anywhere."),
            ("Does Read QR open the link?", "No. Morph only shows what the code says, so you can check a link before visiting it."),
        ],
        "related": ["pdf-converter", "remove-exif", "image-converter"],
    },
]

CSS = """
  :root { --ink: #121A19; --ink-soft: #4F5957; --paper: #F1F4F3; --line: #DCE3E1; --brand: #0B6E69;
          --display: "Bricolage Grotesque", "Avenir Next", system-ui, sans-serif; --body: "Figtree", system-ui, -apple-system, sans-serif; }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--paper); color: var(--ink); font: 400 1.0625rem/1.65 var(--body); -webkit-font-smoothing: antialiased; }
  a { color: var(--brand); }
  :focus-visible { outline: 3px solid var(--brand); outline-offset: 3px; border-radius: 6px; }
  .wrap { width: min(760px, 100% - 2.5rem); margin-inline: auto; }
  .bar { display: flex; align-items: center; justify-content: space-between; padding: 1.4rem 0; }
  .brand { display: flex; align-items: center; gap: .6rem; font: 700 1.25rem/1 var(--display); text-decoration: none; color: var(--ink); }
  .brand svg { width: 30px; height: 30px; }
  .crumbs { font-size: .9rem; color: var(--ink-soft); }
  .crumbs a { color: inherit; }
  h1 { font: 750 clamp(2.2rem, 6vw, 3.2rem)/1.02 var(--display); font-variation-settings: "wdth" 84; letter-spacing: -0.02em; margin: 1.2rem 0 .8rem; text-wrap: balance; }
  h2 { font: 700 1.35rem/1.25 var(--display); margin: 2.4rem 0 .6rem; }
  h3 { font: 650 1.05rem/1.3 var(--body); margin: 0 0 .25rem; }
  p, li { max-width: 66ch; }
  .lede { font-size: 1.2rem; color: var(--ink-soft); margin: 0 0 1rem; }
  .steps { list-style: none; padding: 0; margin: 1rem 0 0; display: grid; gap: .8rem; counter-reset: step; }
  .steps li { counter-increment: step; display: grid; grid-template-columns: auto 1fr; gap: .2rem 1rem; align-items: start;
              background: white; border: 1px solid var(--line); border-radius: 20px; padding: 1.1rem 1.3rem; max-width: none; margin: 0; }
  .steps li::before { content: counter(step); grid-row: span 2; width: 2rem; height: 2rem; border-radius: 50%; display: grid; place-items: center;
                      background: var(--brand); color: white; font: 700 1rem/1 var(--display); }
  .steps p { margin: 0; color: var(--ink-soft); }
  .where { display: grid; gap: .6rem; margin: 0; padding: 0; list-style: none; }
  .where li { background: white; border: 1px solid var(--line); border-radius: 16px; padding: .8rem 1.1rem; max-width: none; margin: 0; }
  .where b { display: inline-block; min-width: 9.5rem; }
  .faq div { border-top: 1px solid var(--line); padding: 1rem 0; }
  .faq p { margin: 0; color: var(--ink-soft); }
  .get { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .8rem; margin-top: 1rem; }
  .get div { background: white; border: 1px solid var(--line); border-radius: 20px; padding: 1.1rem 1.3rem; display: grid; gap: .4rem; align-content: start; }
  .get p { margin: 0; color: var(--ink-soft); font-size: .95rem; }
  .button { justify-self: start; display: inline-flex; align-items: center; padding: .7rem 1.2rem; border-radius: 999px;
            background: var(--brand); color: white; font: 650 .98rem/1 var(--body); text-decoration: none; }
  .button:hover { background: #08524E; }
  .button.quiet { background: transparent; color: var(--brand); box-shadow: inset 0 0 0 2px var(--brand); }
  .related { display: flex; flex-wrap: wrap; gap: .5rem; padding: 0; list-style: none; }
  .related li { margin: 0; }
  .related a { display: inline-block; padding: .45rem .9rem; border-radius: 999px; background: white; border: 1px solid var(--line); text-decoration: none; }
  .promise { margin-top: 2.4rem; padding: 1.2rem 1.4rem; border-radius: 20px; background: var(--brand); color: white; }
  .promise p { margin: 0; max-width: none; }
  footer { padding: 3rem 0 4rem; color: var(--ink-soft); font-size: .92rem; display: flex; gap: 1.4rem; flex-wrap: wrap; }
  footer a { color: inherit; }
  @media (max-width: 640px) { .get { grid-template-columns: 1fr; } .where b { display: block; } }
"""

LOGO = ('<svg viewBox="0 0 64 64" aria-hidden="true"><rect width="64" height="64" rx="16" fill="#0B6E69"/><g fill="#fff">'
        '<circle cx="32" cy="32" r="6"/><circle cx="32" cy="17" r="6"/><circle cx="32" cy="47" r="6"/><circle cx="19" cy="24.5" r="6"/>'
        '<circle cx="45" cy="24.5" r="6"/><circle cx="19" cy="39.5" r="6"/><circle cx="45" cy="39.5" r="6"/></g></svg>')

e = html.escape


def ld(data):
    return '<script type="application/ld+json">\n' + json.dumps(data, indent=2, ensure_ascii=False) + "\n</script>"


def page(p, by_slug):
    url = f"{SITE}/{p['slug']}.html"
    howto = {
        "@context": "https://schema.org", "@type": "HowTo", "name": p["h1"], "description": p["description"],
        "tool": {"@type": "HowToTool", "name": "Morph"},
        "step": [{"@type": "HowToStep", "position": i + 1, "name": n, "text": t or n} for i, (n, t) in enumerate(p["steps"])],
    }
    faq = {
        "@context": "https://schema.org", "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in p["faq"]],
    }
    crumbs = {
        "@context": "https://schema.org", "@type": "BreadcrumbList",
        "itemListElement": [{"@type": "ListItem", "position": 1, "name": "Morph", "item": SITE + "/"},
                            {"@type": "ListItem", "position": 2, "name": p["h1"], "item": url}],
    }
    app = {
        "@context": "https://schema.org", "@type": "SoftwareApplication", "name": "Morph", "url": SITE + "/",
        "applicationCategory": "UtilitiesApplication",
        "operatingSystem": "macOS 14 or later, Windows 10 or later, iOS 17 or later, Android 10 or later",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"}, "isAccessibleForFree": True,
    }
    steps = "\n".join(f"      <li><h3>{e(n)}</h3><p>{e(t)}</p></li>" if t else f"      <li><h3>{e(n)}</h3></li>" for n, t in p["steps"])
    where = "\n".join(f"      <li><b>{e(k)}</b> {e(v)}</li>" for k, v in p["where"])
    faqs = "\n".join(f"      <div><h3>{e(q)}</h3><p>{e(a)}</p></div>" for q, a in p["faq"])
    get = "\n".join(f"      <div><h3>{e(n)}</h3><p>{e(note)}</p>{btn or ''}</div>" for n, btn, note in GET)
    related = "\n".join(f'      <li><a href="{r}.html">{e(by_slug[r]["h1"])}</a></li>' for r in p["related"])
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(p['title'])}</title>
<meta name="description" content="{e(p['description'])}">
<link rel="canonical" href="{url}">
<meta property="og:title" content="{e(p['title'])}">
<meta property="og:description" content="{e(p['description'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}/images/og-card.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Morph's convert wheel beside the words: Convert any file without uploading it.">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Morph">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#0B6E69">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/icon-512.png" type="image/png" sizes="512x512">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,400..800&family=Figtree:wght@400;500;600;700&display=swap" rel="stylesheet">
{ld(app)}
{ld(howto)}
{ld(faq)}
{ld(crumbs)}
<style>{CSS}</style>
</head>
<body>
<div class="wrap">
  <header class="bar">
    <a class="brand" href="./">{LOGO}Morph</a>
  </header>
  <main>
    <nav class="crumbs" aria-label="Breadcrumb"><a href="./">Morph</a> › {e(p['h1'])}</nav>
    <h1>{e(p['h1'])}</h1>
    <p class="lede">{e(p['lede'])}</p>

    <h2>How to do it</h2>
    <ol class="steps">
{steps}
    </ol>

    <h2>Where it works</h2>
    <ul class="where">
{where}
    </ul>

    <div class="promise"><p>Free and open source. Everything runs on your device: no uploads, no account, no ads, and your originals are never changed.</p></div>

    <h2>Get Morph</h2>
    <div class="get">
{get}
    </div>

    <h2>Questions</h2>
    <div class="faq">
{faqs}
    </div>

    <h2>More conversions</h2>
    <ul class="related">
{related}
    </ul>
  </main>
  <footer>
    <a href="./">Morph</a>
    <a href="privacy.html">Privacy</a>
    <a href="support.html">Support</a>
    <a href="sponsor.html">Sponsor</a>
    <a href="https://github.com/geetxnshgoyal/morph">Source on GitHub</a>
  </footer>
</div>
</body>
</html>
"""


def main():
    by_slug = {p["slug"]: p for p in PAGES}
    for p in PAGES:
        assert len(p["title"]) <= 70, p["slug"]
        assert len(p["description"]) <= 160, (p["slug"], len(p["description"]))
        (DOCS / f"{p['slug']}.html").write_text(page(p, by_slug))

    # Sitemap: keep the hand-written entries, replace the conversion pages.
    sitemap = DOCS / "sitemap.xml"
    text = sitemap.read_text()
    text = re.sub(r"\n  <!-- conversions -->.*?<!-- /conversions -->", "", text, flags=re.S)
    entries = "".join(f"\n  <url><loc>{SITE}/{p['slug']}.html</loc><lastmod>{UPDATED}</lastmod><priority>0.8</priority></url>" for p in PAGES)
    text = text.replace("</urlset>", f"  <!-- conversions -->{entries}\n  <!-- /conversions -->\n</urlset>")
    sitemap.write_text(text)
    print(f"wrote {len(PAGES)} pages")


if __name__ == "__main__":
    main()
