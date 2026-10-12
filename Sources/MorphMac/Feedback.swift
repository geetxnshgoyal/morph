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
        guard now.timeIntervalSince(lastTick) > 0.02 else { return }
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

    /// 60 ms detent click: a bright edge that is gone within a millisecond, a short knock under it and a
    /// soft low thump carrying the tail. Crisp rather than tonal, so fast sweeps sound like a dial turning.
    private static func makeTick(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * 0.06)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        func wave(_ frequency: Double, _ t: Double) -> Double { sin(2 * .pi * frequency * t) }
        var peak = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let edge = (wave(9_200, t) + 0.45 * wave(14_800, t) + 0.35 * wave(6_300, t)) * exp(-t / 0.000_45)
            let knock = 0.24 * wave(1_100, t) * exp(-t / 0.000_8)
            let thump = 0.09 * wave(230, t) * exp(-t / 0.005_2) * (1 - exp(-t / 0.000_6))
            let value = (edge + knock) * min(1, t / 0.000_2) + thump
            samples[i] = Float(value)
            peak = max(peak, abs(value))
        }
        // Normalise so the mixer's volume alone sets loudness.
        for i in 0..<Int(frames) { samples[i] = Float(Double(samples[i]) / peak * 0.4) }
        return buffer
    }
}
