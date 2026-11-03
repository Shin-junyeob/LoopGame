import Testing
@testable import LoopCore

@Test func stagesLoadInOrderWithPlanBPMsAndNames() throws {
    let stages = try Stage.loadAll()
    let expected: [(String, Int)] = [
        ("메트로놈 따라 탭", 70), ("킥 4비트", 70), ("킥+스네어", 75), ("하이햇 8비트", 75), ("첫 드럼 루프", 80),
        ("BPM 바꿔보기", 90), ("베이스 근음", 80), ("베이스 리듬", 85), ("베이스 루프", 85), ("코드 하나", 85),
        ("4코드 진행", 90), ("코드 루프", 90), ("음계 안에서 치기", 95), ("짧은 멜로디", 95), ("멜로디 루프 + AI", 100),
        ("음색 바꿔보기", 100), ("루프 길이 섞기", 105), ("곡 완성", 110),
    ]
    #expect(stages.count == 18)
    for (stage, (name, bpm)) in zip(stages, expected) {
        #expect(stage.name == name)
        #expect(stage.bpm == bpm)
        #expect(!stage.song.tracks.isEmpty && stage.song.tracks.allSatisfy { !$0.notes.isEmpty })
        try stage.song.validate()
    }
    #expect(stages.map(\.anyPad) == [true] + Array(repeating: false, count: 17))
}

/// G3: pitched follow-along notes all in C major; notes on beats 1·3 are chord tones of the stage progression.
@Test func pitchedPatternsAreG3Valid() throws {
    for stage in try Stage.loadAll() {
        #expect(stage.song.key.root == 0 && stage.song.key.mode == .major)
        for track in stage.song.tracks where track.role != .drums {
            #expect(Metrics.allInScale(track.notes, key: stage.song.key), "\(stage.name)")
            #expect(Metrics.strongBeatsAreChordTones(track.notes, progression: stage.song.progression), "\(stage.name)")
        }
    }
}

// MARK: build-task fixtures (one passing and one failing song per stage)

private func t(_ role: SongRole, _ bars: Int, _ notes: [(Int64, Int)], timbre: String = "default") -> LoopTrack {
    LoopTrack(role: role, timbre: timbre, bars: bars, notes: notes.map { Note(tick: $0.0, pitch: $0.1) })
}
private func quarters(_ pitch: Int, _ count: Int) -> [(Int64, Int)] { (0..<count).map { (Int64($0) * ppq, pitch) } }
private func song(_ tracks: LoopTrack..., bpm: Int = 100) -> Song { Song(bpm: bpm, tracks: tracks) }

private let drums = t(.drums, 1, [(0, 0), (480, 1), (960, 0), (1440, 1)])
private let bass1 = t(.bass, 1, quarters(36, 4))
private let chords1 = t(.chords, 1, [(0, 60)])
private let edited: Song = {
    var s = song(drums, bass1, t(.melody, 4, [(0, 60)]), bpm: 110)
    s.sections = Arranger.arrange(s)
    s.setTrack(2, on: true, inSection: 0)
    return s
}()
private let tooShort: Song = {  // edited but under 60 s
    var s = edited
    s.sections.removeLast(s.sections.count - 2)
    return s
}()

private struct Fixture: Sendable {
    let pass: Song, passContext: StageContext
    let fail: Song, failContext: StageContext
    init(_ pass: Song, _ fail: Song, ctx: StageContext = StageContext(), failCtx: StageContext? = nil) {
        self.pass = pass; passContext = ctx; self.fail = fail; failContext = failCtx ?? ctx
    }
}

private let fixtures: [Fixture] = [
    // 1 offset + 1-bar tap loop
    Fixture(song(t(.drums, 1, [(0, 3)])), song(t(.drums, 1, [(0, 3)])),
            ctx: StageContext(offsetSaved: true), failCtx: StageContext()),
    // 2 kick >= 4 in a 1-bar loop
    Fixture(song(t(.drums, 1, quarters(0, 4))), song(t(.drums, 1, quarters(0, 3) + [(1440, 1)]))),
    // 3 kick and snare >= 2 each
    Fixture(song(drums), song(t(.drums, 1, [(0, 0), (480, 1), (960, 0)]))),
    // 4 hat >= 8 (closed or open)
    Fixture(song(t(.drums, 2, (0..<7).map { (Int64($0) * 240, 2) } + [(1680, 3)])),
            song(t(.drums, 2, (0..<7).map { (Int64($0) * 240, 2) } + [(1680, 0)]))),
    // 5 kick+snare+hat 2-bar drum track
    Fixture(song(t(.drums, 2, [(0, 0), (480, 1), (240, 2)])), song(t(.drums, 1, [(0, 0), (480, 1), (240, 2)]))),
    // 6 BPM changed with a drum loop
    Fixture(song(drums), song(bass1), ctx: StageContext(bpmChanged: true)),
    // 7 bass 1-bar loop
    Fixture(song(bass1), song(t(.bass, 2, quarters(36, 4)))),
    // 8 bass 2 bars, >= 6 notes
    Fixture(song(t(.bass, 2, quarters(36, 6))), song(t(.bass, 2, quarters(36, 5)))),
    // 9 drums + 4-bar bass
    Fixture(song(drums, t(.bass, 4, quarters(36, 4))), song(t(.bass, 4, quarters(36, 4)))),
    // 10 chords 1-bar loop
    Fixture(song(chords1), song(t(.melody, 1, [(0, 60)]))),
    // 11 four different chords over 4 bars (stacked triads count once each)
    Fixture(song(t(.chords, 4, [(0, 60), (0, 64), (0, 67), (1920, 67), (3840, 69), (5760, 65)])),
            song(t(.chords, 4, [(0, 60), (0, 64), (0, 67), (1920, 67), (3840, 69), (5760, 67)]))),
    // 12 drums + bass + chords
    Fixture(song(drums, bass1, chords1), song(drums, bass1, t(.chords, 1, []))),
    // 13 1-bar lead, nothing outside the scale
    Fixture(song(t(.melody, 1, [(0, 60), (240, 62), (480, 71)])), song(t(.melody, 1, [(0, 60), (240, 61)]))),
    // 14 melody 2 bars, >= 4 notes
    Fixture(song(t(.melody, 2, quarters(64, 4))), song(t(.melody, 4, quarters(64, 4)))),
    // 15 AI suggestion picked and added
    Fixture(song(t(.melody, 4, [(0, 60)])), song(t(.melody, 4, [(0, 60)])),
            ctx: StageContext(suggestionAdded: true), failCtx: StageContext()),
    // 16 timbre changed
    Fixture(song(drums), song(drums), ctx: StageContext(timbreChanged: true), failCtx: StageContext()),
    // 17 two loop lengths
    Fixture(song(drums, t(.chords, 4, [(0, 60)])), song(drums, bass1)),
    // 18 auto arrangement edited, >= 60 s
    Fixture(edited, tooShort),
]

@Test(arguments: 0..<18)
func buildTaskPassesAndFails(_ i: Int) throws {
    let task = try Stage.loadAll()[i].task
    let f = fixtures[i]
    #expect(task.isMet(by: f.pass, context: f.passContext), "stage \(i + 1) pass fixture")
    #expect(!task.isMet(by: f.fail, context: f.failContext), "stage \(i + 1) fail fixture")
}

@Test func unEditedArrangementDoesNotClearFinalStage() throws {
    var s = edited
    s.sections = Arranger.arrange(s)
    #expect(!(try Stage.loadAll()[17].task.isMet(by: s)))
}
