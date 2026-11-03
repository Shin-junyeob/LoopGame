import AVFoundation
import LoopCore

/// Instrument sounds (`Timbres` ids) as one-shot buffers at the engine rate, built on main. Sampled timbres
/// are the bundled CAFs in App/Resources/Samples (44.1 kHz mono, licenses.json); the rest are synthesized
/// here. Pitched timbres get one pre-rendered buffer per MIDI note of the role's range, so the render
/// path only ever plays one-shots.
enum SampleBank {
    static let fileRate = 44_100.0
    /// Drum pad names, index = pad (`Timbres.drumPads`).
    static let names = ["kick", "snare", "closed hat", "open hat", "tom", "crash"]

    /// Drums: one buffer per pad, balanced by `DrumLevels` (kick = synthesized for both kits). Pitched: one per note of `Timbres.range[role]`, index = note - lowerBound.
    static func buffers(role: SongRole, timbre: String, rate: Double) -> [[Float]] {
        if role == .drums {
            let kit = timbre == "kit" ? [DrumLevels.kick(rate: rate)] + (1..<Timbres.drumPads).map { shift(load("drums/kit/\($0)"), ratio: 1, rate) }
                : electronicKit(rate)
            return zip(kit, DrumLevels.gains(kit, rate: rate)).map { pad, gain in pad.map { $0 * gain } }
        }
        let notes = Timbres.range[role]!
        let dir = samples.appendingPathComponent("keys/\(timbre)")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let roots = names.compactMap { Int($0.replacingOccurrences(of: ".caf", with: "")) }
            let loaded = Dictionary(uniqueKeysWithValues: roots.map { ($0, load("keys/\(timbre)/\($0)")) })
            return notes.map { note in
                let (root, ratio) = Timbres.sample(for: note, roots: roots)
                return shift(loaded[root]!, ratio: ratio, rate)
            }
        }
        return notes.map { synth(timbre, freq: 440 * pow(2, Float($0 - 69) / 12), rate) }
    }

    private static let samples = Bundle.main.url(forResource: "Samples", withExtension: nil)!

    /// Bundled file -> float samples at `fileRate`. Missing/corrupt bundle files are a build error, hence `try!`.
    private static func load(_ name: String) -> [Float] {
        let file = try! AVAudioFile(forReading: samples.appendingPathComponent(name + ".caf"))
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try! file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// Play `x` (at `fileRate`) `ratio` times faster, rendered at `rate`. resampleLinear takes integer rates,
    /// so both are scaled by 1000 (pitch error < 0.01 cent).
    private static func shift(_ x: [Float], ratio: Double, _ rate: Double) -> [Float] {
        resampleLinear(x, from: Int((fileRate * ratio * 1000).rounded()), to: Int((rate * 1000).rounded()))
    }

    // MARK: Synthesized timbres (license: self)

    /// `seconds` of f(t) at `rate`, with a 2 ms attack and 20 ms release so one-shots never click.
    private static func make(_ seconds: Float, _ rate: Double, _ f: (Float) -> Float) -> [Float] {
        let sr = Float(rate)
        return (0..<Int(seconds * sr)).map { i in
            let t = Float(i) / sr
            return f(t) * min(1, t / 0.002, (seconds - t) / 0.02)
        }
    }

    /// Deterministic white noise in -1...1.
    private static func noise(_ count: Int) -> [Float] {
        var seed: UInt32 = 1
        return (0..<count).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24) * 2 - 1
        }
    }

    /// Metronome tick: short sine blip, higher on beat 1.
    static func click(accent: Bool, _ rate: Double) -> [Float] {
        make(0.05, rate) { t in sin(2 * .pi * (accent ? 1_760 : 1_320) * t) * exp(-t * 80) }
    }

    private static func electronicKit(_ rate: Double) -> [[Float]] {
        let sr = Float(rate)
        let n = noise(Int(sr))
        let hp = zip(n.dropFirst(), n).map { ($0 - $1) * 0.5 }  // first difference = crude high-pass, hats/crash
        func at(_ x: [Float], _ t: Float) -> Float { x[min(Int(t * sr), x.count - 1)] }
        return [
            DrumLevels.kick(rate: rate),
            make(0.35, rate) { t in sin(2 * .pi * 180 * t) * exp(-t * 20) * 0.4 + at(n, t) * exp(-t * 14) * 0.5 },
            make(0.1, rate) { t in at(hp, t) * exp(-t * 60) * 0.8 },
            make(0.6, rate) { t in at(hp, t) * exp(-t * 7) * 0.6 },
            make(0.5, rate) { t in sin(2 * .pi * (110 * t + 80 * (1 - exp(-t * 15)) / 15)) * exp(-t * 7) * 0.8 },
            make(1.0, rate) { t in at(hp, t) * exp(-t * 3) * 0.5 },
        ]
    }

    private static func synth(_ timbre: String, freq: Float, _ rate: Double) -> [Float] {
        let sr = Float(rate)
        switch timbre {
        case "bass":  // Karplus-Strong plucked string; the 2-tap average adds half a sample of delay
            let period = max(2, Int((sr / freq - 0.5).rounded()))
            var y = noise(period).map { $0 * 0.5 }
            y.reserveCapacity(Int(1.2 * sr))
            for i in period..<Int(1.2 * sr) { y.append((y[i - period] + y[i - period + 1]) * 0.5 * 0.996) }
            return make(1.2, rate) { t in y[min(Int(t * sr), y.count - 1)] * 1.4 }
        case "synth":  // saw through a one-pole low-pass whose cutoff falls 2 kHz -> 300 Hz
            var lp: Float = 0
            return make(1.0, rate) { t in
                let saw = 2 * (t * freq - (t * freq).rounded(.down)) - 1
                let cutoff = 300 + 1700 * exp(-t * 8)
                lp += (saw - lp) * (1 - exp(-2 * .pi * cutoff / sr))
                return lp * exp(-t * 3) * 0.7
            }
        case "bell":  // 2-operator FM, inharmonic 1:1.4 ratio, decaying index
            return make(2.0, rate) { t in
                sin(2 * .pi * freq * t + 4 * exp(-t * 3) * sin(2 * .pi * 1.4 * freq * t)) * exp(-t * 2.5) * 0.5
            }
        default:  // "square": odd harmonics below a quarter of the rate (no aliasing)
            let harmonics = stride(from: 1, through: 15, by: 2).filter { Float($0) * freq < sr / 4 }
            return make(0.8, rate) { t in
                harmonics.reduce(0) { $0 + sin(2 * .pi * Float($1) * freq * t) / Float($1) } * exp(-t * 2) * 0.35
            }
        }
    }
}
