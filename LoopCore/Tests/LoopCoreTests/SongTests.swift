import Foundation
import Testing
@testable import LoopCore

private func validSong() -> Song {
    var s = Song(name: "demo", bpm: 100, tracks: [
        LoopTrack(role: .drums, timbre: "kit", bars: 1, notes: [Note(tick: 0, pitch: 0), Note(tick: 960, pitch: 1)]),
        LoopTrack(role: .bass, bars: 4, notes: [Note(tick: 7679, duration: 1, pitch: 36)]),
    ])
    s.sections = [Section(kind: .intro, bars: 4, tracks: s.tracks.map(\.id))]
    return s
}

@Test func songRoundTrips() throws {
    let song = validSong()
    let back = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
    #expect(back == song)
}

/// Format lock: this literal must keep decoding as schemaVersion 1.
@Test func fixedV1JSONDecodes() throws {
    let json = """
    {"schemaVersion":1,"id":"6F1C2A3B-0000-4000-8000-000000000001","name":"My Song","modifiedAt":0,
     "bpm":90,"key":{"root":0,"mode":"major"},
     "progression":{"chords":[{"root":0,"quality":"major"},{"root":9,"quality":"minor"}]},
     "tracks":[{"id":"6F1C2A3B-0000-4000-8000-0000000000A1","role":"bass","timbre":"default","bars":2,
                "notes":[{"tick":0,"duration":120,"pitch":36,"velocity":100}]}],
     "sections":[{"kind":"main","bars":2,"tracks":["6F1C2A3B-0000-4000-8000-0000000000A1"]}]}
    """
    let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
    let trackID = UUID(uuidString: "6F1C2A3B-0000-4000-8000-0000000000A1")!
    #expect(song.schemaVersion == 1)
    #expect(song.id == UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000001"))
    #expect(song.name == "My Song" && song.modifiedAt == Date(timeIntervalSinceReferenceDate: 0))
    #expect(song.bpm == 90)
    #expect(song.progression.chords[1].quality == .minor)
    #expect(song.tracks[0] == LoopTrack(id: trackID, role: .bass, bars: 2, notes: [Note(tick: 0, pitch: 36)]))
    #expect(song.sections == [Section(kind: .main, bars: 2, tracks: [trackID])])
    try song.validate()
}

@Test func invalidJSONFailsToDecode() throws {
    var s = validSong()
    s.bpm = 200
    #expect(throws: SongError.bpmOutOfRange(200)) {
        try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(s))
    }
}

@Test(arguments: [0, -4, 2, 6])
func validationRejectsSectionBars(_ bars: Int) {
    var s = validSong()  // longest loop: 4 bars
    s.sections[0].bars = bars
    #expect(throws: SongError.invalidSectionBars(section: 0)) { try s.validate() }
}

@Test func removeTrackDropsItFromEverySection() throws {
    var s = validSong()
    let drums = s.tracks[0].id, bass = s.tracks[1].id
    s.sections.append(Section(kind: .main, bars: 8, tracks: [drums]))
    s.removeTrack(id: drums)
    #expect(s.tracks.map(\.id) == [bass])
    #expect(s.sections.map(\.tracks) == [[bass], []])
    try s.validate()
}

@Test func unknownSchemaVersionThrows() throws {
    var json = String(decoding: try JSONEncoder().encode(validSong()), as: UTF8.self)
    json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
    #expect(throws: SongError.unsupportedSchemaVersion(2)) {
        try JSONDecoder().decode(Song.self, from: Data(json.utf8))
    }
}

@Test func validationAcceptsValidSong() throws {
    try validSong().validate()
    try Song(bpm: 60).validate()
    try Song(bpm: 160, tracks: Array(repeating: LoopTrack(role: .melody, bars: 8, notes: []), count: 8)).validate()
}

@Test func validationRejectsTooManyTracks() {
    let s = Song(bpm: 100, tracks: Array(repeating: LoopTrack(role: .drums, bars: 1, notes: []), count: 9))
    #expect(throws: SongError.tooManyTracks(9)) { try s.validate() }
}

@Test(arguments: [59, 161, 0])
func validationRejectsBPM(_ bpm: Int) {
    #expect(throws: SongError.bpmOutOfRange(bpm)) { try Song(bpm: bpm).validate() }
}

@Test(arguments: [0, 3, 5, 16])
func validationRejectsBars(_ bars: Int) {
    var s = validSong()
    s.tracks[1].bars = bars
    #expect(throws: SongError.invalidBars(track: 1)) { try s.validate() }
}

@Test(arguments: [Int64(-1), Int64(4 * 480)])
func validationRejectsNoteOutsideLoop(_ tick: Int64) {
    var s = validSong()
    s.tracks[0].notes.append(Note(tick: tick, pitch: 2))
    #expect(throws: SongError.noteOutsideLoop(track: 0)) { try s.validate() }
}

@Test func validationRejectsSectionPointingAtMissingTrack() {
    var s = validSong()
    s.sections[0].tracks = [s.tracks[0].id, UUID()]
    #expect(throws: SongError.invalidSectionTrack(section: 0)) { try s.validate() }
}
