import Foundation
import Testing
@testable import LoopCore

private func validSong() -> Song {
    Song(bpm: 100, tracks: [
        LoopTrack(role: .drums, timbre: "kit", bars: 1, notes: [Note(tick: 0, pitch: 0), Note(tick: 960, pitch: 1)]),
        LoopTrack(role: .bass, bars: 4, notes: [Note(tick: 7679, duration: 1, pitch: 36)]),
    ], sections: [Section(kind: .intro, bars: 4, tracks: [0, 1])])
}

@Test func songRoundTrips() throws {
    let song = validSong()
    let back = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
    #expect(back == song)
}

/// Format lock: this literal must keep decoding as schemaVersion 1.
@Test func fixedV1JSONDecodes() throws {
    let json = """
    {"schemaVersion":1,"bpm":90,"key":{"root":0,"mode":"major"},
     "progression":{"chords":[{"root":0,"quality":"major"},{"root":9,"quality":"minor"}]},
     "tracks":[{"role":"bass","timbre":"default","bars":2,
                "notes":[{"tick":0,"duration":120,"pitch":36,"velocity":100}]}],
     "sections":[{"kind":"main","bars":2,"tracks":[0]}]}
    """
    let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
    #expect(song.schemaVersion == 1)
    #expect(song.bpm == 90)
    #expect(song.progression.chords[1].quality == .minor)
    #expect(song.tracks[0] == LoopTrack(role: .bass, bars: 2, notes: [Note(tick: 0, pitch: 36)]))
    #expect(song.sections == [Section(kind: .main, bars: 2, tracks: [0])])
    try song.validate()
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
    s.sections[0].tracks = [0, 2]
    #expect(throws: SongError.invalidSectionTrack(section: 0)) { try s.validate() }
}
