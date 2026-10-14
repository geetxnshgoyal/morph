using Windows.Media.Editing;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace Morph;

/// Media Foundation through WinRT: the encoders every Windows 10 and 11 machine has, used when ffmpeg isn't installed.
static class WinMedia
{
    static async Task<StorageFile> Create(string path)
    {
        await File.WriteAllBytesAsync(path, []);
        return await StorageFile.GetFileFromPathAsync(path);
    }

    static async Task Transcode(string input, string output, MediaEncodingProfile profile, CancellationToken cancel)
    {
        var source = await StorageFile.GetFileFromPathAsync(input);
        var destination = await Create(output);
        var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = true };
        var prepared = await transcoder.PrepareFileTranscodeAsync(source, destination, profile);
        if (!prepared.CanTranscode)
            throw new MorphException(prepared.FailureReason switch
            {
                TranscodeFailureReason.CodecNotFound => $"Windows can't decode this file. Install ffmpeg ({ExternalTool.InstallHint}) for more formats.",
                TranscodeFailureReason.InvalidProfile => "Windows can't encode to this format",
                _ => "Windows couldn't convert this file",
            });
        await prepared.TranscodeAsync().AsTask(cancel);
    }

    public static Task ToMp4(string input, string output, CancellationToken cancel) =>
        Transcode(input, output, MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Auto), cancel);

    public static Task ToAudio(string input, string output, string ext, CancellationToken cancel)
    {
        var profile = ext switch
        {
            "mp3" => MediaEncodingProfile.CreateMp3(AudioEncodingQuality.High),
            "wav" => MediaEncodingProfile.CreateWav(AudioEncodingQuality.High),
            "flac" => MediaEncodingProfile.CreateFlac(AudioEncodingQuality.High),
            _ => MediaEncodingProfile.CreateM4a(AudioEncodingQuality.High),
        };
        return Transcode(input, output, profile, cancel);
    }

    /// H.264 at a fraction of the source's bitrate (or whatever bitrate fits a target size), shrunk for Strong.
    public static async Task Compress(string input, string output, CompressionLevel level, long? targetBytes, CancellationToken cancel)
    {
        var file = await StorageFile.GetFileFromPathAsync(input);
        var properties = await file.Properties.GetVideoPropertiesAsync();
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Auto);
        var width = properties.Width;
        var height = properties.Height;
        var longest = level == CompressionLevel.Strong ? 960u : level == CompressionLevel.Balanced ? 1920u : uint.MaxValue;
        if (Math.Max(width, height) > longest && width > 0 && height > 0)
        {
            var scale = (double)longest / Math.Max(width, height);
            width = (uint)(width * scale) & ~1u;
            height = (uint)(height * scale) & ~1u;
        }
        if (width > 0 && height > 0)
        {
            profile.Video.Width = width;
            profile.Video.Height = height;
        }
        var sourceBitrate = properties.Bitrate > 0 ? properties.Bitrate : 8_000_000u;
        uint bitrate = targetBytes is long target && properties.Duration.TotalSeconds > 0
            ? (uint)Math.Max(target * 8 / properties.Duration.TotalSeconds * 0.95 - 128_000, 100_000)
            : (uint)(sourceBitrate * (level switch { CompressionLevel.Light => 0.6, CompressionLevel.Balanced => 0.4, _ => 0.25 }));
        profile.Video.Bitrate = bitrate;
        profile.Audio.Bitrate = 128_000;
        await Transcode(input, output, profile, cancel);
    }

    public static async Task Mute(string input, string output, CancellationToken cancel)
    {
        var profile = await MediaEncodingProfile.CreateFromFileAsync(await StorageFile.GetFileFromPathAsync(input));
        profile.Audio = null;
        profile.Container = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Auto).Container;
        await Transcode(input, output, profile, cancel);
    }

    public static async Task<double> Duration(string path)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        var properties = await file.Properties.GetVideoPropertiesAsync();
        if (properties.Duration > TimeSpan.Zero) return properties.Duration.TotalSeconds;
        var music = await file.Properties.GetMusicPropertiesAsync();
        return music.Duration.TotalSeconds;
    }

    /// Stills at the given times as JPEG bytes, the longest side at most `maxSide` (the video's own size if null).
    public static async Task<IReadOnlyList<byte[]>> Frames(string path, IReadOnlyList<TimeSpan> times, int? maxSide, CancellationToken cancel)
    {
        var clip = await MediaClip.CreateFromFileAsync(await StorageFile.GetFileFromPathAsync(path));
        var composition = new MediaComposition();
        composition.Clips.Add(clip);
        var encoding = clip.GetVideoEncodingProperties();
        double width = encoding.Width, height = encoding.Height;
        if (width <= 0 || height <= 0) (width, height) = (1280, 720);
        if (maxSide is int side && Math.Max(width, height) > side)
        {
            var scale = side / Math.Max(width, height);
            (width, height) = (width * scale, height * scale);
        }
        var frames = new List<byte[]>();
        foreach (var time in times)
        {
            cancel.ThrowIfCancellationRequested();
            using var stream = await composition.GetThumbnailAsync(time < clip.OriginalDuration ? time : clip.OriginalDuration - TimeSpan.FromMilliseconds(50),
                (int)width, (int)height, VideoFramePrecision.NearestFrame);
            using var reader = stream.AsStreamForRead();
            using var memory = new MemoryStream();
            await reader.CopyToAsync(memory, cancel);
            frames.Add(memory.ToArray());
        }
        return frames;
    }
}
