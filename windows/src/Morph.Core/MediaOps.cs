using System.Globalization;
using ImageMagick;

namespace Morph;

/// Audio and video. ffmpeg does everything when it's installed; without it, Windows' own Media Foundation
/// covers MP4, M4A, MP3, WAV and FLAC, compression, muting, GIFs and snapshots.
public static class MediaOps
{
    static bool HasFFmpeg => ExternalTool.FFmpeg is not null;

    static string NeedsFFmpeg => $"This needs ffmpeg. Install it with: {ExternalTool.InstallHint}";

    /// Runs `work` and deletes a half-written output if it fails.
    static async Task<string> Producing(string output, Func<Task> work)
    {
        try { await work(); return output; }
        catch
        {
            try { if (File.Exists(output)) File.Delete(output); } catch (IOException) { }
            throw;
        }
    }

    // MARK: Video

    public static async Task<string> ConvertVideo(string path, string ext, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, ext, options);
        if (HasFFmpeg)
        {
            if (ext is "mp4" or "mov")
            {
                // Rewrap without re-encoding when the streams allow it, like a passthrough export.
                try { return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-c", "copy", "-movflags", "+faststart", output], cancel)); }
                catch (MorphException) { }
                return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-c:v", "libx264", "-crf", "20", "-preset", "medium",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-sn", "-movflags", "+faststart", output], cancel));
            }
            string[] codecs = ext switch
            {
                "webm" => ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus"],
                "mkv" => ["-c", "copy"],
                _ => ["-c:v", "libx264", "-crf", "20", "-c:a", "aac"],
            };
            return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, .. codecs, output], cancel));
        }
#if WINDOWS
        if (ext == "mp4" && Platform.HasWindowsApis) return await Producing(output, () => WinMedia.ToMp4(path, output, cancel));
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    public static async Task<string> CompressVideo(string path, Options options, CancellationToken cancel)
    {
        if (options.TargetBytes is long limit && Bytes.Of(path) <= limit)
            throw new MorphNote($"{Path.GetFileName(path)} is already under {SizeLimit.Label(limit)}");
        var output = Output.For(path, "mp4", options, "compressed");
        if (HasFFmpeg)
        {
            if (options.TargetBytes is long target)
            {
                var seconds = await Duration(path, cancel);
                if (seconds <= 0) throw new MorphException("Video has no duration");
                var videoKbps = Math.Max((int)(target * 8 / seconds / 1000 * 0.95) - 128, 100);
                return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-c:v", "libx264", "-b:v", $"{videoKbps}k", "-maxrate", $"{videoKbps}k",
                    "-bufsize", $"{videoKbps * 2}k", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", output], cancel));
            }
            var (crf, longest) = options.Compression switch
            {
                CompressionLevel.Light => ("23", 0),
                CompressionLevel.Balanced => ("28", 1920),
                _ => ("32", 960),
            };
            string[] scale = longest > 0 ? ["-vf", $"scale='if(gt(iw,ih),min({longest},iw),-2)':'if(gt(iw,ih),-2,min({longest},ih))'"] : [];
            return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, .. scale, "-c:v", "libx264", "-crf", crf, "-preset", "medium",
                "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", output], cancel));
        }
#if WINDOWS
        if (Platform.HasWindowsApis) return await Producing(output, () => WinMedia.Compress(path, output, options.Compression, options.TargetBytes, cancel));
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    public static async Task<string> Mute(string path, Options options, CancellationToken cancel)
    {
        var source = FileKinds.Extension(path);
        if (HasFFmpeg)
        {
            var output = Output.For(path, source is "mp4" or "mov" or "m4v" or "mkv" or "webm" ? source : "mp4", options, "muted");
            return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-map", "0", "-map", "-0:a", "-c", "copy", output], cancel));
        }
#if WINDOWS
        if (Platform.HasWindowsApis)
        {
            var output = Output.For(path, "mp4", options, "muted");
            return await Producing(output, () => WinMedia.Mute(path, output, cancel));
        }
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    /// A stream copy with every metadata tag and chapter left out.
    public static async Task<string> StripMetadata(string path, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, FileKinds.Extension(path), options, "clean");
        return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-map", "0", "-map_metadata", "-1", "-map_chapters", "-1",
            "-fflags", "+bitexact", "-c", "copy", output], cancel));
    }

    public static async Task<string> ToGif(string path, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, "gif", options);
        var side = options.MaxPixel ?? 480;
        if (HasFFmpeg)
        {
            var filter = $"fps=12,scale='if(gt(iw,ih),min({side},iw),-2)':'if(gt(iw,ih),-2,min({side},ih))':flags=lanczos," +
                         "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a";
            return await Producing(output, () => ExternalTool.FFmpegRun(["-t", "30", "-i", path, "-vf", filter, "-loop", "0", output], cancel));
        }
#if WINDOWS
        if (Platform.HasWindowsApis)
        {
            const double fps = 12;
            var seconds = Math.Min(await WinMedia.Duration(path), 30);
            var times = Enumerable.Range(0, Math.Max((int)(seconds * fps), 1)).Select(i => TimeSpan.FromSeconds(i / fps)).ToList();
            var frames = await WinMedia.Frames(path, times, side, cancel);
            return await Producing(output, async () =>
            {
                using var gif = new MagickImageCollection();
                foreach (var frame in frames)
                {
                    var image = new MagickImage(frame);
                    image.AnimationDelay = (uint)Math.Round(100 / fps);
                    gif.Add(image);
                }
                gif[0].AnimationIterations = 0;
                gif.Quantize(new QuantizeSettings { Colors = 256, DitherMethod = DitherMethod.FloydSteinberg });
                gif.Optimize();
                await gif.WriteAsync(output, MagickFormat.Gif, cancel);
            });
        }
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    /// Six evenly spaced stills, in a folder beside the video.
    public static async Task<IReadOnlyList<string>> Snapshots(string path, Options options, CancellationToken cancel)
    {
        const int count = 6;
        var seconds = await Duration(path, cancel);
        var times = Enumerable.Range(0, count).Select(i => seconds * (i + 0.5) / count).ToList();
        var folder = Output.Folder(path, "frames", options);
        string Name(int i) => Path.Combine(folder, string.Create(CultureInfo.InvariantCulture, $"frame {i + 1:00} ({times[i]:0.0}s).jpg"));
        if (HasFFmpeg)
        {
            for (var i = 0; i < count; i++)
                await ExternalTool.FFmpegRun(["-ss", times[i].ToString("0.###", CultureInfo.InvariantCulture), "-i", path, "-frames:v", "1", "-q:v", "2", Name(i)], cancel);
            return [folder];
        }
#if WINDOWS
        if (Platform.HasWindowsApis)
        {
            var frames = await WinMedia.Frames(path, times.Select(TimeSpan.FromSeconds).ToList(), null, cancel);
            for (var i = 0; i < frames.Count; i++)
            {
                using var image = new MagickImage(frames[i]);
                ImageOps.Write(image, ImageFormat.Jpg, 0.9, Name(i));
            }
            return [folder];
        }
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    /// Length in seconds, from ffprobe or Windows' media properties.
    public static async Task<double> Duration(string path, CancellationToken cancel = default)
    {
        if (ExternalTool.FFprobe is { } ffprobe)
        {
            var text = await ExternalTool.Run(ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], cancel);
            if (double.TryParse(text.Trim(), CultureInfo.InvariantCulture, out var seconds)) return seconds;
        }
#if WINDOWS
        if (Platform.HasWindowsApis) return await WinMedia.Duration(path);
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    // MARK: Audio

    public static async Task<string> ConvertAudio(string path, string ext, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, ext, options);
        if (HasFFmpeg)
        {
            string[] codec = ext switch
            {
                "mp3" => ["-c:a", "libmp3lame", "-q:a", "2"],
                "ogg" => ["-c:a", "libvorbis", "-q:a", "5"],
                "opus" => ["-c:a", "libopus", "-b:a", "128k"],
                "flac" => ["-c:a", "flac"],
                "wav" => ["-c:a", "pcm_s16le"],
                "aiff" => ["-c:a", "pcm_s16be"],
                _ => ["-c:a", "aac", "-b:a", "192k"],
            };
            return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-vn", .. codec, output], cancel));
        }
#if WINDOWS
        if (ext is "m4a" or "mp3" or "wav" or "flac" && Platform.HasWindowsApis)
            return await Producing(output, () => WinMedia.ToAudio(path, output, ext, cancel));
#endif
        throw new MorphException(NeedsFFmpeg);
    }

    public static async Task<string> Normalize(string path, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, FileKinds.Extension(path), options, "normalized");
        string[] video = FileKinds.Of(path) == FileKind.Video ? ["-c:v", "copy"] : [];
        return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", .. video, output], cancel));
    }

    public static async Task<string> TrimSilence(string path, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, FileKinds.Extension(path), options, "trimmed");
        const string filter = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse," +
                              "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse";
        return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-af", filter, output], cancel));
    }

    /// A video of the sound's waveform in Morph's tangerine, for posting audio where only video goes.
    public static async Task<string> WaveformVideo(string path, Options options, CancellationToken cancel)
    {
        var output = Output.For(path, "mp4", options, "waveform");
        return await Producing(output, () => ExternalTool.FFmpegRun(["-i", path, "-filter_complex",
            "[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=0xFF8F38:scale=sqrt,format=yuv420p[v]",
            "-map", "[v]", "-map", "0:a", "-c:v", "libx264", "-b:v", "2M", "-c:a", "aac", "-shortest", output], cancel));
    }

    public static async Task<Dictionary<string, string>> Summary(string path, CancellationToken cancel = default)
    {
        var info = new Dictionary<string, string>();
        try { info["Duration"] = $"{await Duration(path, cancel):0.0}s"; }
        catch (MorphException) { }
        if (ExternalTool.FFprobe is { } ffprobe)
        {
            var streams = await ExternalTool.Run(ffprobe, ["-v", "error", "-show_entries", "stream=codec_type,codec_name,width,height,bit_rate",
                "-of", "compact=p=0:nk=0", path], cancel);
            foreach (var line in streams.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var fields = line.Split('|').Select(f => f.Split('=', 2)).Where(f => f.Length == 2).ToDictionary(f => f[0], f => f[1]);
                var kind = fields.GetValueOrDefault("codec_type") is "video" ? "Video" : "Audio";
                var size = fields.GetValueOrDefault("width") is { } w && w != "N/A" ? $"{w}×{fields.GetValueOrDefault("height")}, " : "";
                info.TryAdd(kind, $"{size}{fields.GetValueOrDefault("codec_name")}");
            }
        }
        return info;
    }
}
