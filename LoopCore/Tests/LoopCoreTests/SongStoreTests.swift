import Foundation
import Testing
@testable import LoopCore

@Test func storeRoundTripsThroughFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SongStore(directory: dir)

    var a = Song(name: "first", modifiedAt: Date(timeIntervalSinceReferenceDate: 100), bpm: 90,
                 tracks: [LoopTrack(role: .drums, bars: 1, notes: [Note(tick: 0, pitch: 0)])])
    a.sections = Arranger.arrange(a)
    let b = Song(name: "second", modifiedAt: Date(timeIntervalSinceReferenceDate: 200), bpm: 120)
    try store.save(a)
    try store.save(b)
    try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
    #expect(store.loadAll() == [b, a])  // newest first, broken file skipped

    a.name = "renamed"
    try store.save(a)  // same id overwrites
    #expect(store.loadAll().map(\.name) == ["second", "renamed"])

    try store.delete(id: b.id)
    #expect(store.loadAll() == [a])
}
