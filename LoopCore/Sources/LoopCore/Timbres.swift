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
