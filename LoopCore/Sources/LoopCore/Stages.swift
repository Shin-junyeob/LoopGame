import Foundation

/// One of the 18 stages (plan §5): follow along `song`, then clear `task` in your own song.
/// Progress only orders the stages; free creation is open from the start (G5) and nothing here locks it.
///
/// Drum pads (tools/train/groove.py): 0 kick, 1 snare, 2 closed hat, 3 open hat, 4 tom, 5 crash/ride.
/// `song` is the follow-along pattern at the stage BPM, as loop tracks (shorter loops repeat to the longest).
/// Chords role: one note per chord-pad hit, pitch = the chord root (one input matches one note).
public struct Stage: Codable, Equatable, Sendable {
    public var name: String
    /// Stage 1: any pad counts as the right pad.
    public var anyPad: Bool
    public var song: Song
    public var task: BuildTask
    public var bpm: Int { song.bpm }

    public static func loadAll() throws -> [Stage] {
        let url = Bundle.module.url(forResource: "stages", withExtension: "json")!
        return try JSONDecoder().decode([Stage].self, from: Data(contentsOf: url))
    }
}

/// Facts about how the song got here that the song itself can't show.
public struct StageContext: Sendable {
    public var offsetSaved = false
    public var bpmChanged = false
    public var timbreChanged = false
    public var suggestionAdded = false
    public init(offsetSaved: Bool = false, bpmChanged: Bool = false, timbreChanged: Bool = false, suggestionAdded: Bool = false) {
        self.offsetSaved = offsetSaved; self.bpmChanged = bpmChanged
        self.timbreChanged = timbreChanged; self.suggestionAdded = suggestionAdded
    }
}

public struct PadCount: Codable, Equatable, Sendable {
    public var pads: [Int]
    public var min: Int
}

public struct TrackSpec: Codable, Equatable, Sendable {
    public var role: SongRole
    public var bars: Int?
    public var minNotes: Int
}

/// Build-task clear predicates. JSON: {"<case>": {<params>}}.
public enum BuildTask: Codable, Equatable, Sendable {
    /// Latency offset saved + a 1-bar loop with notes.
    case offsetAndLoop
    /// A drum track (of `bars`, if set) meeting every pad count.
    case drumPads(bars: Int?, counts: [PadCount])
    /// BPM was changed and a drum loop is there to play.
    case bpmChangedWithDrums
    /// Every spec is met by some track.
    case tracks(all: [TrackSpec])
    /// A chords track of `bars` with at least `min` different chords (same-tick notes = one chord).
    case chordChanges(bars: Int, min: Int)
    /// A `role` track of `bars` with notes, all in the song key's scale.
    case inScale(role: SongRole, bars: Int)
    /// An AI suggestion was picked and added as a melody track.
    case suggestionAdded
    /// A track's timbre was changed.
    case timbreChanged
    /// At least `min` different loop lengths among tracks.
    case mixedBarLengths(min: Int)
    /// Sections differ from the auto arrangement (edited) and last >= `minSeconds`.
    case arranged(minSeconds: Int)

    public func isMet(by song: Song, context: StageContext = StageContext()) -> Bool {
        let t = song.tracks.filter { !$0.notes.isEmpty }
        func has(_ role: SongRole, bars: Int? = nil, where ok: (LoopTrack) -> Bool = { _ in true }) -> Bool {
            t.contains { $0.role == role && (bars == nil || $0.bars == bars) && ok($0) }
        }
        switch self {
        case .offsetAndLoop:
            return context.offsetSaved && t.contains { $0.bars == 1 }
        case let .drumPads(bars, counts):
            return has(.drums, bars: bars) { tr in
                counts.allSatisfy { c in tr.notes.filter { c.pads.contains($0.pitch) }.count >= c.min }
            }
        case .bpmChangedWithDrums:
            return context.bpmChanged && has(.drums)
        case let .tracks(specs):
            return specs.allSatisfy { s in has(s.role, bars: s.bars) { $0.notes.count >= s.minNotes } }
        case let .chordChanges(bars, min):
            return has(.chords, bars: bars) { tr in
                Set(Dictionary(grouping: tr.notes, by: \.tick).values.map { Set($0.map { $0.pitch % 12 }) }).count >= min
            }
        case let .inScale(role, bars):
            return has(role, bars: bars) { Metrics.allInScale($0.notes, key: song.key) }
        case .suggestionAdded:
            return context.suggestionAdded && has(.melody)
        case .timbreChanged:
            return context.timbreChanged && !t.isEmpty
        case let .mixedBarLengths(min):
            return Set(t.map(\.bars)).count >= min
        case let .arranged(minSeconds):
            let seconds = Arranger.totalTicks(song.sections) * 60 / (ppq * Int64(song.bpm))
            return !song.sections.isEmpty && song.sections != Arranger.arrange(song) && seconds >= Int64(minSeconds)
        }
    }
}
