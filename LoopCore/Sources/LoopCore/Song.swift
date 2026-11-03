import Foundation

/// One recorded loop. `notes` are ticks within the loop (0 ..< bars × ticksPerBar).
public struct LoopTrack: Codable, Equatable, Sendable {
    public var id: UUID
    public var role: SongRole
    public var timbre: String
    public var bars: Int
    public var notes: [Note]
    public init(id: UUID = UUID(), role: SongRole, timbre: String = "default", bars: Int, notes: [Note]) {
        self.id = id; self.role = role; self.timbre = timbre; self.bars = bars; self.notes = notes
    }
    public var loopTicks: Int64 { Int64(bars) * Progression.ticksPerBar }
}

/// A stretch of the arrangement playing `tracks` (`LoopTrack.id`s, in `Song.tracks` order) for `bars` bars.
public struct Section: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case intro, main, outro }
    public var kind: Kind
    public var bars: Int
    public var tracks: [UUID]
    public init(kind: Kind, bars: Int, tracks: [UUID]) { self.kind = kind; self.bars = bars; self.tracks = tracks }
}

public enum SongError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case tooManyTracks(Int)
    case bpmOutOfRange(Int)
    case invalidBars(track: Int)
    case noteOutsideLoop(track: Int)
    case invalidSectionTrack(section: Int)
    case invalidSectionBars(section: Int)
}

/// On-disk (and later CloudKit) format. Decoding a schemaVersion other than 1 throws `SongError.unsupportedSchemaVersion`;
/// decoding an invalid song throws the `validate()` error.
public struct Song: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maxTracks = 8
    public static let bpmRange = 60...160
    public static let allowedBars: Set<Int> = [1, 2, 4, 8]

    public private(set) var schemaVersion = Song.currentSchemaVersion
    public var id: UUID
    public var name: String
    public var modifiedAt: Date
    public var bpm: Int
    public var key: Key
    public var progression: Progression
    public var tracks: [LoopTrack]
    public var sections: [Section]

    public init(id: UUID = UUID(), name: String = "", modifiedAt: Date = Date(), bpm: Int,
                key: Key = Key(root: 0, mode: .major), progression: Progression = .cGAmF,
                tracks: [LoopTrack] = [], sections: [Section] = []) {
        self.id = id; self.name = name; self.modifiedAt = modifiedAt
        self.bpm = bpm; self.key = key; self.progression = progression; self.tracks = tracks; self.sections = sections
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, id, name, modifiedAt, bpm, key, progression, tracks, sections }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == Song.currentSchemaVersion else { throw SongError.unsupportedSchemaVersion(version) }
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        bpm = try c.decode(Int.self, forKey: .bpm)
        key = try c.decode(Key.self, forKey: .key)
        progression = try c.decode(Progression.self, forKey: .progression)
        tracks = try c.decode([LoopTrack].self, forKey: .tracks)
        sections = try c.decode([Section].self, forKey: .sections)
        try validate()
    }

    public func validate() throws {
        guard tracks.count <= Song.maxTracks else { throw SongError.tooManyTracks(tracks.count) }
        guard Song.bpmRange.contains(bpm) else { throw SongError.bpmOutOfRange(bpm) }
        for (i, t) in tracks.enumerated() {
            guard Song.allowedBars.contains(t.bars) else { throw SongError.invalidBars(track: i) }
            guard t.notes.allSatisfy({ $0.tick >= 0 && $0.tick < t.loopTicks }) else { throw SongError.noteOutsideLoop(track: i) }
        }
        let ids = Set(tracks.map(\.id))
        let unit = tracks.map(\.bars).max() ?? 1
        for (i, s) in sections.enumerated() {
            guard s.tracks.allSatisfy(ids.contains) else { throw SongError.invalidSectionTrack(section: i) }
            guard s.bars > 0 && s.bars % unit == 0 else { throw SongError.invalidSectionBars(section: i) }
        }
    }

    /// AC9: turn one track on/off in one section; other sections are untouched.
    public mutating func setTrack(_ track: UUID, on: Bool, inSection section: Int) {
        var set = Set(sections[section].tracks)
        if on { set.insert(track) } else { set.remove(track) }
        sections[section].tracks = tracks.map(\.id).filter(set.contains)
    }

    /// Delete a track and drop it from every section.
    public mutating func removeTrack(id: UUID) {
        tracks.removeAll { $0.id == id }
        for i in sections.indices { sections[i].tracks.removeAll { $0 == id } }
    }
}
