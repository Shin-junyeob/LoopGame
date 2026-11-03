import Testing
@testable import LoopCore

@Test func emptySongStartsWithDrums() {
    #expect(Recommender.next(present: []) == .drums)
}

@Test func firstMissingRoleInOrder() {
    #expect(Recommender.next(present: [.drums]) == .bass)
    #expect(Recommender.next(present: [.drums, .bass]) == .chords)
    #expect(Recommender.next(present: [.drums, .bass, .chords]) == .melody)
    #expect(Recommender.next(present: [.bass, .melody]) == .drums)
}

@Test func allPresentPicksFewestTracksTieByOrder() {
    #expect(Recommender.next(present: Set(SongRole.allCases)) == .drums)
    #expect(Recommender.next(trackCounts: [.drums: 2, .bass: 1, .chords: 1, .melody: 3]) == .bass)
    #expect(Recommender.next(trackCounts: [.drums: 2, .bass: 2, .chords: 1, .melody: 1]) == .chords)
}
