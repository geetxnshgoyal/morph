import AppKit
import AVFoundation

/// A soft tick and a trackpad haptic each time the wheel's highlight moves.
/// The tick is synthesized at launch, so no sound files ship with the app.
@MainActor
final class Feedback {
    static let shared = Feedback()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let tickBuffer: AVAudioPCMBuffer
    private var lastTick = Date.distantPast

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        tickBuffer = Self.makeTick(format: format)
        // A few players take turns so quick sweeps overlap instead of cutting each other off.
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.35
    }

    func tick() {
        guard Preferences.shared.playSounds else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Keep very fast sweeps crisp rather than buzzing.
        let now = Date()
        guard now.timeIntervalSince(lastTick) > 0.025 else { return }
        lastTick = now
        // The engine stops when the output device changes; restart on demand.
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(tickBuffer)
        player.play()
    }

    /// 40 ms "pop": a quick downward chirp with a fast exponential decay and a click-free attack.
    private static func makeTick(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let length = 0.04
        let frames = AVAudioFrameCount(rate * length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let frequency = 1_800 - 900 * (t / length)
            phase += 2 * .pi * frequency / rate
            let envelope = exp(-t * 110) * min(1, t * 4_000)
            samples[i] = Float(sin(phase) * envelope * 0.6)
        }
        return buffer
    }
}
