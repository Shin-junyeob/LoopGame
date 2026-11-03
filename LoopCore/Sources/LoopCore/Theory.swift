public struct Key: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case major, minor }
    public var root: Int  // pitch class 0-11
    public var mode: Mode
    public init(root: Int, mode: Mode) { self.root = root; self.mode = mode }

    /// Scale pitch classes as a 12-bit mask (bit n = pitch class n).
    public var scaleMask: Int {
        let steps = mode == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        return steps.reduce(0) { $0 | (1 << ((root + $1) % 12)) }
    }
    public func contains(_ pitch: Int) -> Bool { scaleMask & (1 << (((pitch % 12) + 12) % 12)) != 0 }
}

public struct Chord: Codable, Equatable, Sendable {
    public enum Quality: String, Codable, Sendable { case major, minor }
    public var root: Int
    public var quality: Quality
    public init(root: Int, quality: Quality) { self.root = root; self.quality = quality }

    private var steps: [Int] { quality == .major ? [0, 4, 7] : [0, 3, 7] }
    public var toneMask: Int { steps.reduce(0) { $0 | (1 << ((root + $1) % 12)) } }
    public func contains(_ pitch: Int) -> Bool { toneMask & (1 << (((pitch % 12) + 12) % 12)) != 0 }

    /// Playback-only close-position triad (MIDI) below the melody register: the first of root position,
    /// 1st, 2nd inversion whose lowest note fits in 53...60. Judgement still uses `root`.
    public var voicing: [Int] {
        for inv in 0..<3 {
            let shape = Array(steps[inv...]) + steps[..<inv].map { $0 + 12 }
            let bass = 53 + ((root + shape[0] - 53) % 12 + 12) % 12
            if bass <= 60 { return shape.map { bass + $0 - shape[0] } }
        }
        return steps.map { 48 + root + $0 }  // unreachable: every triad has a tone in pitch classes 5...0
    }
}

/// One chord per 4/4 bar, cycling.
public struct Progression: Codable, Equatable, Sendable {
    public var chords: [Chord]
    public init(_ chords: [Chord]) { self.chords = chords }
    public static let cGAmF = Progression([
        Chord(root: 0, quality: .major), Chord(root: 7, quality: .major),
        Chord(root: 9, quality: .minor), Chord(root: 5, quality: .major),
    ])
    public static let ticksPerBar: Int64 = 4 * ppq
    public func chord(atTick tick: Int64) -> Chord {
        let bar = tick >= 0 ? tick / Self.ticksPerBar : (tick + 1) / Self.ticksPerBar - 1  // floor
        let n = Int64(chords.count)
        return chords[Int((bar % n + n) % n)]
    }
}

/// Beats 1 and 3 of a 4/4 bar (exact onset).
public func isStrongBeat(_ tick: Int64) -> Bool {
    let r = (tick % Progression.ticksPerBar + Progression.ticksPerBar) % Progression.ticksPerBar
    return r == 0 || r == 2 * ppq
}
