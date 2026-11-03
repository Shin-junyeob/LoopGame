import Testing
@testable import LoopCore

private let roles: [SongRole] = [.drums, .bass, .chords, .melody, .melody, .chords, .bass, .drums]
private let barsCycle = [1, 4, 2, 8, 1, 2, 4, 1]

private func song(bpm: Int, count: Int, roles: [SongRole] = roles) -> Song {
    Song(bpm: bpm, tracks: (0..<count).map {
        LoopTrack(role: roles[$0], bars: barsCycle[$0], notes: [Note(tick: 0, pitch: 0)])
    })
}

private func seconds(_ sections: [Section], bpm: Int) -> Double {
    Double(Arranger.totalTicks(sections)) / Double(ppq) * 60 / Double(bpm)
}

@Test(arguments: [60, 110, 160], [1, 2, 4, 8])
func arrangementIsLongEnoughAndWellFormed(bpm: Int, count: Int) throws {
    var s = song(bpm: bpm, count: count)
    let sections = Arranger.arrange(s)
    let unit = s.tracks.map(\.bars).max()!
    let all = Array(0..<count)

    #expect(seconds(sections, bpm: bpm) >= 60)
    #expect(sections.allSatisfy { $0.bars > 0 && $0.bars % unit == 0 })

    // intro = drums + bass tracks
    #expect(sections[0].kind == .intro)
    #expect(sections[0].tracks == all.filter { [.drums, .bass].contains(s.tracks[$0].role) })
    #expect(sections[1].kind == .main && sections[1].tracks == all)
    // outro: one track fewer per section, down to one; drums dropped last
    let outros = Array(sections.dropFirst(2))
    #expect(outros.map(\.kind).allSatisfy { $0 == .outro })
    #expect(outros.map(\.tracks.count) == Array((1..<count).reversed()))
    for (prev, next) in zip([all] + outros.map(\.tracks), outros.map(\.tracks)) {
        #expect(Set(next).isSubset(of: Set(prev)))
    }
    if let last = outros.last { #expect(s.tracks[last.tracks[0]].role == .drums) }

    // main repeats minimally: one repeat fewer would drop below 60 s (unless already at 1)
    var shorter = sections
    shorter[1].bars -= unit
    #expect(shorter[1].bars == 0 || seconds(shorter, bpm: bpm) < 60)

    s.sections = sections
    try s.validate()
}

@Test func introFallsBackToFirstTracksWithoutDrumsOrBass() {
    let s = song(bpm: 100, count: 3, roles: [.chords, .melody, .melody])
    #expect(Arranger.arrange(s)[0].tracks == [0, 1])
    let one = song(bpm: 100, count: 1, roles: [.melody])
    #expect(Arranger.arrange(one)[0].tracks == [0])
    let bassOnly = song(bpm: 100, count: 2, roles: [.melody, .bass])
    #expect(Arranger.arrange(bassOnly)[0].tracks == [1])
}

@Test func emptySongHasNoSections() {
    #expect(Arranger.arrange(Song(bpm: 100)).isEmpty)
}

@Test func toggleChangesOnlyThatSection() throws {
    var s = song(bpm: 110, count: 4)
    s.sections = Arranger.arrange(s)
    let before = s.sections

    s.setTrack(3, on: true, inSection: 0)
    #expect(s.sections[0].tracks == [0, 1, 3])
    s.setTrack(0, on: false, inSection: 0)
    #expect(s.sections[0].tracks == [1, 3])
    #expect(Array(s.sections.dropFirst()) == Array(before.dropFirst()))
    try s.validate()

    s.setTrack(1, on: true, inSection: 0)  // already on: no duplicate
    #expect(s.sections[0].tracks == [1, 3])
}

@Test func totalFramesViaClock() {
    let s = song(bpm: 110, count: 4)  // longest loop 8 bars
    let sections = Arranger.arrange(s)
    let bars = Int64(sections.map(\.bars).reduce(0, +))
    #expect(Arranger.totalFrames(sections, sampleRate: 48_000, bpm: 110) == bars * 4 * 48_000 * 60 / 110)
    // intro + main×1 + 3 outros, 8 bars each (outros alone already reach 60 s)
    #expect(bars == 40)
}
