/// One recorded loop. `notes` are ticks within the loop (0 ..< bars × ticksPerBar).
public struct LoopTrack: Codable, Equatable, Sendable {
    public var role: SongRole
    public var timbre: String
    public var bars: Int
    public var notes: [Note]
    public init(role: SongRole, timbre: String = "default", bars: Int, notes: [Note]) {
        self.role = role; self.timbre = timbre; self.bars = bars; self.notes = notes
    }
    public var loopTicks: Int64 { Int64(bars) * Progression.ticksPerBar }
}

/// A stretch of the arrangement playing `tracks` (indices into `Song.tracks`, sorted) for `bars` bars.
public struct Section: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case intro, main, outro }
    public var kind: Kind
    public var bars: Int
    public var tracks: [Int]
    public init(kind: Kind, bars: Int, tracks: [Int]) { self.kind = kind; self.bars = bars; self.tracks = tracks }
}

public enum SongError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case tooManyTracks(Int)
    case bpmOutOfRange(Int)
    case invalidBars(track: Int)
    case noteOutsideLoop(track: Int)
    case invalidSectionTrack(section: Int)
}

/// On-disk (and later CloudKit) format. Decoding a schemaVersion other than 1 throws `SongError.unsupportedSchemaVersion`.
public struct Song: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maxTracks = 8
    public static let bpmRange = 60...160
    public static let allowedBars: Set<Int> = [1, 2, 4, 8]

    public private(set) var schemaVersion = Song.currentSchemaVersion
    public var bpm: Int
    public var key: Key
    public var progression: Progression
    public var tracks: [LoopTrack]
    public var sections: [Section]

    public init(bpm: Int, key: Key = Key(root: 0, mode: .major), progression: Progression = .cGAmF,
                tracks: [LoopTrack] = [], sections: [Section] = []) {
        self.bpm = bpm; self.key = key; self.progression = progression; self.tracks = tracks; self.sections = sections
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, bpm, key, progression, tracks, sections }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == Song.currentSchemaVersion else { throw SongError.unsupportedSchemaVersion(version) }
        bpm = try c.decode(Int.self, forKey: .bpm)
        key = try c.decode(Key.self, forKey: .key)
        progression = try c.decode(Progression.self, forKey: .progression)
        tracks = try c.decode([LoopTrack].self, forKey: .tracks)
        sections = try c.decode([Section].self, forKey: .sections)
    }

    public func validate() throws {
        guard tracks.count <= Song.maxTracks else { throw SongError.tooManyTracks(tracks.count) }
        guard Song.bpmRange.contains(bpm) else { throw SongError.bpmOutOfRange(bpm) }
        for (i, t) in tracks.enumerated() {
            guard Song.allowedBars.contains(t.bars) else { throw SongError.invalidBars(track: i) }
            guard t.notes.allSatisfy({ $0.tick >= 0 && $0.tick < t.loopTicks }) else { throw SongError.noteOutsideLoop(track: i) }
        }
        for (i, s) in sections.enumerated() where !s.tracks.allSatisfy(tracks.indices.contains) {
            throw SongError.invalidSectionTrack(section: i)
        }
    }

    /// AC9: turn one track on/off in one section; other sections are untouched.
    public mutating func setTrack(_ track: Int, on: Bool, inSection section: Int) {
        var set = Set(sections[section].tracks)
        if on { set.insert(track) } else { set.remove(track) }
        sections[section].tracks = set.sorted()
    }
}
