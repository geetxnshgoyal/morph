import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaOps {
    static let nativeVideo: Set<String> = ["mp4", "mov", "m4v"]

    static func isNativelyReadable(_ url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.isReadable)) ?? false
    }

    static func fileType(for ext: String) -> AVFileType {
        switch ext {
        case "mov": .mov
        case "m4v": .m4v
        case "m4a": .m4a
        default: .mp4
        }
    }

    static func export(_ asset: AVAsset, preset: String, type: AVFileType, to out: URL,
                       configure: ((AVAssetExportSession) -> Void)? = nil) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MorphError("This file can't be exported with \(preset)")
        }
        session.shouldOptimizeForNetworkUse = true
        configure?(session)
        if #available(macOS 15, iOS 18, *) {
            try await session.export(to: out, as: type)
        } else {
            session.outputURL = out
            session.outputFileType = type
            await session.export()
            if session.status != .completed {
                throw MorphError(session.error?.localizedDescription ?? "Export failed")
            }
        }
    }

    // MARK: Video

    public static func convertVideo(_ url: URL, to ext: String, options: Options) async throws -> URL {
        let out = Output.url(for: url, ext: ext, options: options)
        if nativeVideo.contains(ext), await isNativelyReadable(url) {
            let asset = AVURLAsset(url: url)
            do {
                try await export(asset, preset: AVAssetExportPresetPassthrough, type: fileType(for: ext), to: out)
            } catch {
                try? FileManager.default.removeItem(at: out)
                try await export(asset, preset: AVAssetExportPresetHighestQuality, type: fileType(for: ext), to: out)
            }
            return out
        }
        let args: [String]
        switch ext {
        case "webm": args = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus"]
        case "mkv": args = ["-c", "copy"]
        case "avi": args = ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame"]
        default: args = ["-c:v", "h264_videotoolbox", "-q:v", "65", "-c:a", "aac", "-movflags", "+faststart"]
        }
        try await ExternalTool.ffmpeg(["-i", url.path] + args + [out.path])
        return out
    }

    public static func compressVideo(_ url: URL, options: Options) async throws -> URL {
        let out = Output.url(for: url, ext: "mp4", suffix: "compressed", options: options)
        let asset = AVURLAsset(url: url)
        if let target = options.targetBytes {
            guard Runner.size(of: url) > Int64(target) else {
                throw MorphNote("\(url.lastPathComponent) is already under \(SizeLimit.label(target))")
            }
            if ExternalTool.ffmpeg != nil {
                let seconds = try await asset.load(.duration).seconds
                guard seconds > 0 else { throw MorphError("Video has no duration") }
                let videoKbps = max(Int(Double(target) * 8 / seconds / 1000 * 0.95) - 128, 100)
                try await ExternalTool.ffmpeg(["-i", url.path, "-c:v", "h264_videotoolbox", "-b:v", "\(videoKbps)k",
                                               "-maxrate", "\(videoKbps)k", "-c:a", "aac", "-b:a", "128k",
                                               "-movflags", "+faststart", out.path])
                return out
            }
            // Without ffmpeg (always the case on iPhone), step down through the system presets until one fits.
            for preset in [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540,
                           AVAssetExportPreset640x480] {
                try? FileManager.default.removeItem(at: out)
                try await export(asset, preset: preset, type: .mp4, to: out)
                if Runner.size(of: out) <= Int64(target) { return out }
            }
            try? FileManager.default.removeItem(at: out)
            throw MorphError("Couldn't get \(url.lastPathComponent) under \(SizeLimit.label(target))")
        }
        let preset = switch options.compression {
        case .light: AVAssetExportPresetHEVCHighestQuality
        case .balanced: AVAssetExportPresetHEVC1920x1080
        case .strong: AVAssetExportPreset960x540
        }
        guard await isNativelyReadable(url) else {
            let crf = switch options.compression { case .light: "23"; case .balanced: "28"; case .strong: "32" }
            try await ExternalTool.ffmpeg(["-i", url.path, "-c:v", "libx264", "-crf", crf, "-preset", "medium",
                                           "-c:a", "aac", "-movflags", "+faststart", out.path])
            return out
        }
        try await export(asset, preset: preset, type: .mp4, to: out)
        return out
    }

    public static func mute(_ url: URL, options: Options) async throws -> URL {
        let ext = nativeVideo.contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "mp4"
        let out = Output.url(for: url, ext: ext, suffix: "muted", options: options)
        let asset = AVURLAsset(url: url)
        let comp = AVMutableComposition()
        let duration = try await asset.load(.duration)
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try t.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
            t.preferredTransform = try await track.load(.preferredTransform)
        }
        try await export(comp, preset: AVAssetExportPresetPassthrough, type: fileType(for: ext), to: out)
        return out
    }

    /// Passthrough copy with location, device and personal tags filtered out.
    public static func stripMetadata(_ url: URL, options: Options) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let out = Output.url(for: url, ext: ext, suffix: "clean", options: options)
        if ["mp4", "mov", "m4v", "m4a"].contains(ext), await isNativelyReadable(url) {
            try await export(AVURLAsset(url: url), preset: AVAssetExportPresetPassthrough, type: fileType(for: ext), to: out) {
                $0.metadata = []
                $0.metadataItemFilter = .forSharing()
            }
        } else {
            try await ExternalTool.ffmpeg(["-i", url.path, "-map", "0", "-map_metadata", "-1", "-map_chapters", "-1", "-c", "copy", out.path])
        }
        return out
    }

    public static func toGIF(_ url: URL, options: Options) async throws -> URL {
        let out = Output.url(for: url, ext: "gif", options: options)
        let asset = AVURLAsset(url: url)
        let rawDuration = try await asset.load(.duration).seconds
        guard !rawDuration.isNaN, !rawDuration.isInfinite, rawDuration > 0 else {
            throw MorphError("Video has no duration or cannot be read")
        }
        let seconds = min(rawDuration, 30)
        let fps = 12.0
        let side = CGFloat(options.maxPixel ?? 480)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: side, height: side)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let count = max(Int(seconds * fps), 1)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw MorphError("Couldn't create GIF")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for i in 0..<count {
            let (img, _) = try await gen.image(at: CMTime(seconds: Double(i) / fps, preferredTimescale: 600))
            CGImageDestinationAddImage(dest, img, frameProps)
        }
        guard CGImageDestinationFinalize(dest) else { throw MorphError("Couldn't write GIF") }
        return out
    }

    public static func snapshots(_ url: URL, count: Int = 6, options: Options) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let rawDuration = try await asset.load(.duration).seconds
        guard !rawDuration.isNaN, !rawDuration.isInfinite, rawDuration > 0 else {
            throw MorphError("Video has no duration or cannot be read")
        }
        let seconds = rawDuration
        let folder = try Output.folder(for: url, suffix: "frames", options: options)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let safeCount = max(count, 1)
        var outputs: [URL] = []
        for i in 0..<safeCount {
            let t = seconds * (Double(i) + 0.5) / Double(safeCount)
            let (img, _) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
            let out = folder.appendingPathComponent(String(format: "frame %02d (%.1fs).jpg", i + 1, t))
            try ImageOps.encode(img, as: .jpg, quality: 0.9).write(to: out)
            outputs.append(out)
        }
        return [folder]
    }

    // MARK: Audio

    public static func convertAudio(_ url: URL, to ext: String, options: Options) async throws -> URL {
        let out = Output.url(for: url, ext: ext, options: options)
        let native = await isNativelyReadable(url)
        if native, ext == "m4a" {
            try await export(AVURLAsset(url: url), preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out)
            return out
        }
        if native, ["wav", "aiff", "caf"].contains(ext) {
            try transcodePCM(url, to: out)
            return out
        }
        let codec: [String] = switch ext {
        case "mp3": ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case "ogg": ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case "opus": ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case "flac": ["-vn", "-c:a", "flac"]
        case "wav": ["-vn", "-c:a", "pcm_s16le"]
        case "aiff": ["-vn", "-c:a", "pcm_s16be"]
        default: ["-vn", "-c:a", "aac", "-b:a", "192k"]
        }
        try await ExternalTool.ffmpeg(["-i", url.path] + codec + [out.path])
        return out
    }

    static func transcodePCM(_ url: URL, to out: URL) throws {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        var settings = input.fileFormat.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = out.pathExtension.lowercased() == "aiff"
        settings[AVLinearPCMIsNonInterleaved] = false
        let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else { throw MorphError("Audio buffer failed") }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }

    public static func extractAudio(_ url: URL, options: Options) async throws -> URL {
        try await convertAudio(url, to: "m4a", options: options)
    }

    public static func normalize(_ url: URL, options: Options) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        let out = Output.url(for: url, ext: ext, suffix: "normalized", options: options)
        let video = FileKind(url: url) == .video
        try await ExternalTool.ffmpeg(["-i", url.path, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]
                                      + (video ? ["-c:v", "copy"] : []) + [out.path])
        return out
    }

    public static func trimSilence(_ url: URL, options: Options) async throws -> URL {
        let out = Output.url(for: url, ext: url.pathExtension.lowercased(), suffix: "trimmed", options: options)
        let filter = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse,"
            + "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse"
        try await ExternalTool.ffmpeg(["-i", url.path, "-af", filter, out.path])
        return out
    }

    public static func waveformVideo(_ url: URL, options: Options) async throws -> URL {
        let out = Output.url(for: url, ext: "mp4", suffix: "waveform", options: options)
        try await ExternalTool.ffmpeg(["-i", url.path, "-filter_complex",
                                       "[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=0x7c5cff:scale=sqrt,format=yuv420p[v]",
                                       "-map", "[v]", "-map", "0:a", "-c:v", "h264_videotoolbox", "-b:v", "2M",
                                       "-c:a", "aac", "-shortest", out.path])
        return out
    }

    public static func summary(_ url: URL) async throws -> [String: String] {
        let asset = AVURLAsset(url: url)
        var info: [String: String] = [:]
        info["Duration"] = String(format: "%.1fs", try await asset.load(.duration).seconds)
        for track in try await asset.load(.tracks) {
            let kind = track.mediaType == .video ? "Video" : track.mediaType == .audio ? "Audio" : track.mediaType.rawValue
            if track.mediaType == .video {
                let size = try await track.load(.naturalSize)
                info[kind] = "\(Int(size.width))×\(Int(size.height)), \(Int(try await track.load(.estimatedDataRate) / 1000)) kbps"
            } else {
                info[kind] = "\(Int(try await track.load(.estimatedDataRate) / 1000)) kbps"
            }
        }
        let meta = try await asset.load(.metadata)
        info["Metadata items"] = "\(meta.count)"
        return info
    }
}
