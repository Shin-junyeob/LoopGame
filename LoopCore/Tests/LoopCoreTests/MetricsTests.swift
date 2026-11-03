import Testing
@testable import LoopCore

private let cMaj = Key(root: 0, mode: .major)
private func n(_ t: Int64, _ p: Int) -> Note { Note(tick: t, pitch: p) }

@Test func scaleMetric() {
    #expect(Metrics.allInScale([n(0, 60), n(480, 67)], key: cMaj))
    #expect(!Metrics.allInScale([n(0, 60), n(480, 61)], key: cMaj))
}
@Test func chordToneMetric() {
    let p = Progression.cGAmF
    #expect(Metrics.strongBeatsAreChordTones([n(0, 64), n(480, 62)], progression: p)) // D on weak beat ok
    #expect(!Metrics.strongBeatsAreChordTones([n(0, 62)], progression: p))            // D on beat 1 over C
    #expect(!Metrics.strongBeatsAreChordTones([n(960, 62)], progression: p))          // beat 3
}
@Test func countChangeMetric() {
    let o = (0..<10).map { n(Int64($0) * 480, 60) }
    #expect(Metrics.countChange(candidate: Array(o.dropLast(2)), original: o) == 0.2)
    #expect(Metrics.countChange(candidate: Array(o.dropLast(3)), original: o) > 0.2)
}
@Test func gridRatioMetric() {
    let jittered = [n(10, 60), n(490, 60), n(950, 60), n(1450, 60)]  // errors 10,10,10,... 
    let snapped = [n(0, 60), n(480, 60), n(960, 60), n(1440, 60)]
    #expect(Metrics.gridError(snapped) == 0)
    #expect(Metrics.gridErrorRatio(candidate: snapped, original: jittered) == 0)
    #expect(Metrics.gridErrorRatio(candidate: jittered, original: jittered) == 1) // unchanged fails <= 0.6
    let half = [n(0, 60), n(485, 60), n(960, 60), n(1445, 60)] // errors 0,5,0,5 -> mean 2.5 vs 10
    #expect(Metrics.gridErrorRatio(candidate: half, original: jittered) < 0.6)
}
@Test func onsetF1Pitched() {
    let ref = [n(0, 60), n(480, 64), n(960, 67)]
    #expect(Metrics.onsetF1(candidate: ref, reference: ref, drums: false) == 1)
    // within 120 ticks and 2 semitones: match
    #expect(Metrics.onsetF1(candidate: [n(100, 62), n(480, 64), n(960, 67)], reference: ref, drums: false) == 1)
    // 3 semitones off and 121 ticks off: no match for those two -> tp 1 of 3
    let bad = [n(0, 63), n(601, 64), n(960, 67)]
    let f = Metrics.onsetF1(candidate: bad, reference: ref, drums: false)
    #expect(abs(f - 1.0 / 3.0) < 1e-9)
}
@Test func onsetF1OneToOne() {
    // two candidates near one reference: only one may match
    let f = Metrics.onsetF1(candidate: [n(0, 60), n(10, 60)], reference: [n(0, 60)], drums: false)
    #expect(abs(f - 2.0 / 3.0) < 1e-9)
}
@Test func drumsUsePadEqualityNotPitchTolerance() {
    let ref = [n(0, 36), n(480, 38)]
    #expect(Metrics.onsetF1(candidate: [n(0, 37), n(480, 38)], reference: ref, drums: false) == 1) // pitched tolerance would pass
    let f = Metrics.onsetF1(candidate: [n(0, 37), n(480, 38)], reference: ref, drums: true)
    #expect(abs(f - 0.5) < 1e-9)
}
