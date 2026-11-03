public struct Key: Sendable {
    public enum Mode: Sendable { case major, minor }
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

public struct Chord: Sendable {
    public enum Quality: Sendable { case major, minor }
    public var root: Int
    public var quality: Quality
    public init(root: Int, quality: Quality) { self.root = root; self.quality = quality }

    public var toneMask: Int {
        let steps = quality == .major ? [0, 4, 7] : [0, 3, 7]
        return steps.reduce(0) { $0 | (1 << ((root + $1) % 12)) }
    }
    public func contains(_ pitch: Int) -> Bool { toneMask & (1 << (((pitch % 12) + 12) % 12)) != 0 }
}

/// One chord per 4/4 bar, cycling.
public struct Progression: Sendable {
    public var chords: [Chord]
    public init(_ chords: [Chord]) { self.chords = chords }
    public static let cGAmF = Progression([
        Chord(root: 0, quality: .major), Chord(root: 7, quality: .major),
        Chord(root: 9, quality: .minor), Chord(root: 5, quality: .major),
    ])
    public static let ticksPerBar: Int64 = 4 * ppq
    public func chord(atTick tick: Int64) -> Chord {
        chords[Int((tick / Self.ticksPerBar) % Int64(chords.count))]
    }
}

/// Beats 1 and 3 of a 4/4 bar (exact onset).
public func isStrongBeat(_ tick: Int64) -> Bool {
    let r = tick % Progression.ticksPerBar
    return r == 0 || r == 2 * ppq
}
