import Foundation
import Testing
@testable import LoopCore

private let cMaj = Key(root: 0, mode: .major)
private func ctx(drums: Bool = false, bars: Int = 1) -> Corrector.Context {
    Corrector.Context(drums: drums, key: cMaj, progression: .cGAmF, bars: bars)
}
private func n(_ t: Int64, _ p: Int) -> Note { Note(tick: t, pitch: p) }

@Test func tokensMatchTrainPy() {
    let c = ctx()
    #expect(Corrector.degree(60, key: cMaj) == 35 && Corrector.degree(59, key: cMaj) == 34 && Corrector.degree(74, key: cMaj) == 43
           && Corrector.degree(57, key: Key(root: 9, mode: .minor)) == 28)
    #expect(Corrector.token(tick: 1920 + 240, pitch: 64, prevDegree: nil, context: c).0 == "2:^2")
    #expect(Corrector.token(tick: 480, pitch: 62, prevDegree: 37, context: c).0 == "4:-1")
    #expect(Corrector.token(tick: 480, pitch: 64, prevDegree: 37, context: c).0 == "4:+0")
    #expect(Corrector.token(tick: 120, pitch: 3, prevDegree: nil, context: ctx(drums: true)).0 == "1:3")
}

@Test func outputsAlwaysSatisfyHardConstraints() throws {
    let model = try NGramModel.load(role: "melody")
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<20 {
        let input = (0..<12).map { i in n(Int64(i) * 160 + Int64.random(in: -70...70, using: &rng), Int.random(in: 55...80, using: &rng)) }
            .map { var x = $0; x.tick = max(0, x.tick); return x }
        for c in Corrector.candidates(input, context: ctx(bars: 1), model: model) {
            #expect(Metrics.allInScale(c.notes, key: cMaj))
            #expect(Metrics.strongBeatsAreChordTones(c.notes, progression: .cGAmF))
            #expect(Metrics.countChange(candidate: c.notes, original: input) <= 0.2)
            #expect(c.notes.allSatisfy { $0.tick % Metrics.sixteenth == 0 })
        }
        for c in Corrector.suggest(input, context: ctx(bars: 1), model: model) {
            #expect(Corrector.passes(c, input: input, context: ctx(bars: 1)))
        }
    }
}

@Test func emptyWhenNothingPasses() throws {
    let model = try NGramModel.load(role: "melody")
    #expect(Corrector.suggest([], context: ctx(), model: model).isEmpty)
    // 10 copies of one note: only one survives the no-duplicate rule -> count change 90% -> no candidate
    #expect(Corrector.suggest(Array(repeating: n(0, 60), count: 10), context: ctx(), model: model).isEmpty)
    // a candidate under its F1 floor never passes the filter
    let input = [n(0, 60), n(480, 62), n(960, 64)]
    #expect(!Corrector.passes(.init(notes: [n(0, 60)], strength: .weak, f1: 0.5), input: input, context: ctx()))
}

@Test func ruleBaselineSnapsToGridAndMask() {
    let out = Corrector.ruleBaseline([n(50, 61), n(130, 61), n(130, 61)], context: ctx())
    #expect(out.map(\.tick) == [0, 120] && out[0].pitch == 60 && cMaj.contains(out[1].pitch))
}

@Test func melodyCorpusIsSingable() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data/corpus/melody/patterns.jsonl")
    struct P: Decodable { let notes: [[Int]] }
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count >= 100)
    for l in lines {
        let ps = try JSONDecoder().decode(P.self, from: Data(l.utf8)).notes.map { $0[2] }
        #expect(ps.allSatisfy { (60...81).contains($0) } && ps.max()! - ps.min()! <= 12)
    }
}

/// US-304 compare model: only Metrics-passing candidates for every role, empty when none pass (AC10, AC11).
@Test func compareExposesOnlyPassingCandidates() throws {
    var rng = SystemRandomNumberGenerator()
    for role in SongRole.allCases {
        let drums = role == .drums
        for _ in 0..<10 {
            let notes = (0..<12).map { i in
                n(max(0, Int64(i) * 160 + Int64.random(in: -70...70, using: &rng)), drums ? Int.random(in: 0..<6, using: &rng)
                    : Int.random(in: Timbres.range[role] ?? 60...81, using: &rng))
            }
            let take = LoopTrack(role: role, bars: 1, notes: notes)
            let options = try Corrector.suggest(for: take, key: cMaj, progression: .cGAmF)
            #expect(options.count <= 2)
            for c in options {
                #expect(Corrector.passes(c, input: notes, context: ctx(drums: drums)))
                #expect(Metrics.countChange(candidate: c.notes, original: notes) <= 0.2)
                if !drums {
                    #expect(Metrics.allInScale(c.notes, key: cMaj) && Metrics.strongBeatsAreChordTones(c.notes, progression: .cGAmF))
                }
            }
        }
    }
    let stuck = LoopTrack(role: .melody, bars: 1, notes: Array(repeating: n(0, 60), count: 10))
    #expect(try Corrector.suggest(for: stuck, key: cMaj, progression: .cGAmF).isEmpty)
}

/// G9: timing-only never changes a pitch, pitch-only never moves an onset, neither -> nothing.
@Test func correctionOptionsSplitTimingAndPitch() throws {
    var rng = SystemRandomNumberGenerator()
    let key = { (n: Note) in [n.tick, Int64(n.pitch)] }
    for role in SongRole.allCases {
        let drums = role == .drums
        for _ in 0..<10 {
            let notes = (0..<12).map { i in
                n(max(0, Int64(i) * 160 + Int64.random(in: -70...70, using: &rng)), drums ? Int.random(in: 0..<6, using: &rng)
                    : Int.random(in: Timbres.range[role] ?? 60...81, using: &rng))
            }
            let take = LoopTrack(role: role, bars: 1, notes: notes)
            let ticks = Set(notes.map(\.tick)), pitches = Set(notes.map(\.pitch))
            let model = try NGramModel.load(role: role.rawValue)
            let timing = Corrector.Context(drums: drums, key: cMaj, progression: .cGAmF, bars: 1, options: .init(timing: true, pitch: false))
            for c in Corrector.candidates(notes, context: timing, model: model) {
                // every output note keeps the pitch of an input note it came from: the multiset of pitches only shrinks
                var left = notes.map(\.pitch)
                for p in c.notes.map(\.pitch) {
                    #expect(left.firstIndex(of: p).map { left.remove(at: $0) } != nil)
                }
                #expect(c.notes.allSatisfy { $0.tick % Metrics.sixteenth == 0 })
            }
            let pitchOnly = Corrector.Context(drums: drums, key: cMaj, progression: .cGAmF, bars: 1, options: .init(timing: false, pitch: true))
            for c in Corrector.candidates(notes, context: pitchOnly, model: model) {
                #expect(c.notes.allSatisfy { ticks.contains($0.tick) })
                if drums { #expect(c.notes.allSatisfy { pitches.contains($0.pitch) }) }
            }
            for c in try Corrector.suggest(for: take, key: cMaj, progression: .cGAmF, options: .init(timing: false, pitch: true)) {
                #expect(Set(c.notes.map(key)) != Set(notes.map(key)))
                #expect(c.notes.allSatisfy { ticks.contains($0.tick) })
            }
            #expect(try Corrector.suggest(for: take, key: cMaj, progression: .cGAmF, options: .init(timing: false, pitch: false)).isEmpty)
        }
    }
    // timing-only also passes takes with out-of-scale notes through, pitches untouched (G3 not applied)
    let offKey = (0..<8).map { n(Int64($0) * 240 + 40, [61, 63, 66, 68][$0 % 4]) }
    let take = LoopTrack(role: .melody, bars: 1, notes: offKey)
    for c in try Corrector.suggest(for: take, key: cMaj, progression: .cGAmF, options: CorrectionOptions()) {
        #expect(c.notes.allSatisfy { [61, 63, 66, 68].contains($0.pitch) })
    }
}
