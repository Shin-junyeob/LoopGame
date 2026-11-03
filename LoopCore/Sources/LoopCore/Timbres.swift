import Foundation

/// Instrument sounds per role. Ids are saved in songs (`LoopTrack.timbre`), so never rename one; the first is the default.
public enum Timbres {
    public static let ids: [SongRole: [String]] = [
        .drums: ["kit", "electronic"],
        .bass: ["bass", "synth"],
        .chords: ["piano", "epiano"],
        .melody: ["piano", "bell", "square"],
    ]
    /// Playable MIDI range of the pitched roles (drums play pads 0..<drumPads instead).
    public static let range: [SongRole: ClosedRange<Int>] = [.bass: 36...55, .chords: 53...72, .melody: 60...81]
    /// Drum pads: 0 kick, 1 snare, 2 closed hat, 3 open hat, 4 tom, 5 crash (same order as the drums corpus).
    public static let drumPads = 6

    /// Multisample to play for `note`: the nearest root (ties -> lower root, so it is pitched up) and the
    /// playback-rate ratio 2^((note - root) / 12).
    public static func sample(for note: Int, roots: [Int]) -> (root: Int, ratio: Double) {
        let root = roots.min { (abs(note - $0), $0) < (abs(note - $1), $1) }!
        return (root, pow(2, Double(note - root) / 12))
    }
}

/// Drum-kit balance by heard loudness. Peak-normalized samples made the boomy kick sound quieter than the hats
/// (device feedback), because most of its energy sits below what a phone speaker / the ear picks up.
public enum DrumLevels {
    /// Target loudness per pad relative to the kick, dB: kick ≥ snare > open hat > closed hat (kick ≥ closed hat + 4).
    public static let targetDb: [Float] = [0, -1, -9, -6, -3, -7]  // pad order: kick, snare, closed hat, open hat, tom, crash

    /// RMS (dB) of the first 150 ms after a one-pole 150 Hz high-pass.
    // ponytail: the high-pass stands in for speaker rolloff / A-weighting; use K-weighting if it misjudges a kit.
    public static func loudness(_ x: [Float], rate: Double) -> Float {
        let a = 1 - exp(-2 * Float.pi * 150 / Float(rate))
        var low: Float = 0
        let n = min(x.count, Int(0.15 * rate))
        let energy = x.prefix(n).reduce(Float(0)) { sum, v in
            low += (v - low) * a
            return sum + (v - low) * (v - low)
        }
        return 10 * log10(max(energy / Float(max(n, 1)), 1e-12))
    }

    /// Per-pad gains reaching `targetDb`, scaled together so the hottest single hit peaks at -1 dBFS.
    public static func gains(_ pads: [[Float]], rate: Double) -> [Float] {
        let raw = zip(pads, targetDb).map { pow(10, ($1 - loudness($0, rate: rate)) / 20) }
        let peak = zip(pads, raw).map { ($0.map(abs).max() ?? 0) * $1 }.max() ?? 0
        return peak > 0 ? raw.map { $0 * 0.89 / peak } : raw
    }

    /// Pop kick for both kits (license: self): 160 -> 50 Hz sine sweep plus a 4 ms beater click, soft-clipped so its
    /// harmonics carry on small speakers.
    public static func kick(rate: Double) -> [Float] {
        let sr = Float(rate), seconds: Float = 0.45
        return (0..<Int(seconds * sr)).map { i in
            let t = Float(i) / sr
            let body = sin(2 * .pi * (50 * t + 110 * (1 - exp(-t * 35)) / 35)) * exp(-t * 7)
            let click = t < 0.004 ? sin(2 * .pi * 1800 * t) * (1 - t / 0.004) * 0.5 : 0
            return tanh((body + click) * 2.5) * min(1, t / 0.0005, (seconds - t) / 0.02)
        }
    }
}
