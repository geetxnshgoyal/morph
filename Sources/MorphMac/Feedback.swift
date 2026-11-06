import AppKit
import AVFoundation

/// A soft tick and a trackpad haptic each time the wheel's highlight moves, and a sound when a job ends.
/// For Diwali the tick becomes a soft bell, and a finished job sets off a rocket, a boom and crackling sparks with a
/// temple bell ringing through them, all in a little hall reverb so it sounds like it's outside.
/// Every sound is synthesized at launch, so no sound files ship with the app.
@MainActor
final class Feedback {
    static let shared = Feedback()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let tickBuffer: AVAudioPCMBuffer
    private let bellTickBuffer: AVAudioPCMBuffer
    private let celebrationBuffer: AVAudioPCMBuffer
    private let festivePlayer = AVAudioPlayerNode()
    private let reverb = AVAudioUnitReverb()
    private var lastTick = Date.distantPast

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        tickBuffer = Self.makeTick(format: format)
        bellTickBuffer = Self.makeBellTick(format: format)
        celebrationBuffer = Self.makeCelebration(format: format)
        // A few players take turns so quick sweeps overlap instead of cutting each other off.
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        // The celebration plays through its own reverb, so the boom and the bell have somewhere to ring.
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 30
        engine.attach(festivePlayer)
        engine.attach(reverb)
        engine.connect(festivePlayer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.35
    }

    func tick() {
        guard Preferences.shared.playSounds else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Keep very fast sweeps crisp rather than buzzing.
        let now = Date()
        guard now.timeIntervalSince(lastTick) > 0.02 else { return }
        lastTick = now
        play(Festive.isDiwali ? bellTickBuffer : tickBuffer)
    }

    /// A job finished well.
    func done() {
        guard Preferences.shared.playSounds else { return }
        if Festive.isDiwali {
            if !engine.isRunning { try? engine.start() }
            guard engine.isRunning else { return }
            festivePlayer.stop()
            festivePlayer.scheduleBuffer(celebrationBuffer)
            festivePlayer.play()
        } else {
            NSSound(named: "Glass")?.play()
        }
    }

    /// A job failed.
    func failed() {
        guard Preferences.shared.playSounds else { return }
        NSSound.beep()
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        // The engine stops when the output device changes; restart on demand.
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }

    /// Fills a buffer of `seconds` from `sample(t)` and normalises it to `level`.
    private static func render(_ format: AVAudioFormat, seconds: Double, level: Double = 0.4,
                               _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        var peak = 1e-9
        for i in 0..<Int(frames) {
            let value = sample(Double(i) / rate)
            samples[i] = Float(value)
            peak = max(peak, abs(value))
        }
        for i in 0..<Int(frames) { samples[i] = Float(Double(samples[i]) / peak * level) }
        return buffer
    }

    /// A soft bell for each step of the highlight: a rounded strike at 1.6 kHz with a couple of bell partials,
    /// gone in a fifth of a second so sweeps stay gentle.
    private static func makeBellTick(format: AVAudioFormat) -> AVAudioPCMBuffer {
        render(format, seconds: 0.2, level: 0.22) { t in
            let strike = min(1, t / 0.002)
            let f = 1_620.0
            return strike * (sin(2 * .pi * f * t) * exp(-t / 0.06)
                + 0.35 * sin(2 * .pi * f * 2.76 * t) * exp(-t / 0.025)
                + 0.12 * sin(2 * .pi * f * 5.4 * t) * exp(-t / 0.01))
        }
    }

    /// Diwali, in three seconds: a rocket whistles up, bursts with a deep boom, its sparks crackle and fizz out,
    /// and a temple bell rings through it all. Noise is filtered so nothing is harsh; a fixed seed makes it
    /// sound the same every time.
    private static func makeCelebration(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        var seed: UInt64 = 0x5EED_D1A7
        func noise() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53) * 2 - 1
        }
        // One-pole low-pass and high-pass filters over the noise, by cutoff in Hz.
        func coefficient(_ cutoff: Double) -> Double { 1 - exp(-2 * .pi * cutoff / rate) }
        var low = 0.0, crackleLow = 0.0, cracklePrev = 0.0, hiss = 0.0
        // Sparks: little crackles scattered after the burst, thinning out.
        var sparks: [(time: Double, size: Double)] = []
        var sparkTime = 0.66
        while sparkTime < 2.2 {
            sparks.append((sparkTime, 0.25 + 0.75 * (noise() + 1) / 2 * (1 - (sparkTime - 0.66) / 1.6)))
            sparkTime += 0.012 + 0.05 * (noise() + 1) / 2 * (1 + (sparkTime - 0.66) * 1.5)
        }
        var sparkIndex = 0
        let burst = 0.62, bell = 0.7
        return render(format, seconds: 3.4, level: 0.42) { t in
            let n = noise()
            var value = 0.0

            // Rocket: a whistle gliding up with a little wobble, over a soft hiss of thrust.
            if t < burst {
                let p = t / burst
                let pitch = 1_100 + 1_700 * p * p
                let phase = 2 * .pi * (1_100 * t + 1_700 * burst * pow(p, 3) / 3) + 0.4 * sin(2 * .pi * 7 * t)
                let swell = min(1, t / 0.08) * (0.4 + 0.6 * p) * (t > burst - 0.03 ? (burst - t) / 0.03 : 1)
                hiss += coefficient(5_000) * (n - hiss)
                value += swell * (0.32 * sin(phase) + 0.12 * hiss) * (pitch > 0 ? 1 : 0)
            }

            // Boom: a deep thump with a rumble of low noise under it.
            if t >= burst {
                let d = t - burst
                low += coefficient(260) * (n - low)
                let thump = sin(2 * .pi * (58 * d + 30 * (1 - exp(-d / 0.05)) * 0.05)) * exp(-d / 0.22)
                let crack = n * exp(-d / 0.004)
                value += 1.1 * thump + 2.2 * low * exp(-d / 0.5) + 0.5 * crack
            }

            // Crackle: tiny bright pops, high-passed so they sparkle rather than hiss.
            while sparkIndex < sparks.count, sparks[sparkIndex].time + 0.02 < t { sparkIndex += 1 }
            var pops = 0.0
            var i = sparkIndex
            while i < sparks.count, sparks[i].time <= t {
                let d = t - sparks[i].time
                if d < 0.02 { pops += sparks[i].size * exp(-d / 0.0025) }
                i += 1
            }
            crackleLow += coefficient(1_800) * (n - crackleLow)
            let bright = n - crackleLow
            cracklePrev = bright
            value += 0.55 * pops * cracklePrev

            // Temple bell: hum, prime, minor third, fifth and nominal of a brass bell, each beating gently.
            if t >= bell {
                let d = t - bell
                let f = 523.0
                let strike = min(1, d / 0.002)
                let partials: [(ratio: Double, amp: Double, decay: Double)] = [
                    (0.5, 0.35, 1.6), (1, 0.6, 1.3), (1.19, 0.4, 0.9), (1.5, 0.22, 0.7), (2, 0.3, 0.6), (2.76, 0.12, 0.3)]
                var ring = 0.0
                for p in partials {
                    ring += p.amp * (sin(2 * .pi * f * p.ratio * d) + 0.6 * sin(2 * .pi * f * p.ratio * 1.002 * d)) * exp(-d / p.decay)
                }
                value += 0.42 * strike * ring
            }
            return value
        }
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
