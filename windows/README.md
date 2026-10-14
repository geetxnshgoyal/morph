# Morph for Windows

Work in progress. The engine is ported to C# on .NET 10; the Windows app itself (the drag wheel and settings) isn't built yet.

## What's here

```
src/Morph.Core/          the engine: image, PDF, document, media, archive and vision ops, the action library,
                         runner, watch folder and the wheel's key model (Ctrl, Alt, Shift, Win or Tab)
src/Morph.Core/Windows/  Windows-only pieces: Media Foundation for audio and video, PDF rendering, and
                         on-device text and face detection
tests/Morph.Core.Tests/  xUnit tests for the engine and the wheel model
```

Images go through Magick.NET, PDFs through PDFsharp and PdfPig, documents through Open XML and Markdig, and QR codes through ZXing.Net. ffmpeg handles every audio and video format when it is installed; without it, Windows' own Media Foundation covers the common ones.

## Build and test

Needs the [.NET 10 SDK](https://dotnet.microsoft.com/download). The engine also builds on macOS and Linux; the Windows-only parts compile there but only run on Windows.

```bash
dotnet test windows/tests/Morph.Core.Tests
```
