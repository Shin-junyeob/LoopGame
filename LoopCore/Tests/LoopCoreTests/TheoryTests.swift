import Testing
@testable import LoopCore

@Test func cMajorScaleMask() {
    let k = Key(root: 0, mode: .major)
    #expect(k.contains(60) && k.contains(67) && !k.contains(61))
    #expect(k.scaleMask == 0b101010110101)
}
@Test func aMinorScale() {
    let k = Key(root: 9, mode: .minor)
    #expect(k.contains(64) && !k.contains(66)) // E in, F# out
    #expect(!k.contains(68))                    // natural minor: no G# (harmonic-minor V)
}
@Test func chordTones() {
    let p = Progression.cGAmF
    #expect(p.chord(atTick: 0).contains(64))            // C: E
    #expect(!p.chord(atTick: 0).contains(62))           // C: no D
    #expect(p.chord(atTick: 2 * 4 * ppq).contains(72))  // Am: C
    #expect(p.chord(atTick: 4 * 4 * ppq).contains(60))  // wraps to C
    #expect(p.chord(atTick: 3 * 4 * ppq).contains(65))  // F: F
}
@Test func strongBeats() {
    #expect(isStrongBeat(0) && isStrongBeat(2 * ppq) && isStrongBeat(4 * ppq))
    #expect(!isStrongBeat(ppq) && !isStrongBeat(3 * ppq) && !isStrongBeat(120))
}
@Test func negativeTicksWrapToPreviousBar() {
    #expect(Progression.cGAmF.chord(atTick: -1).root == 5)  // F, last bar
    #expect(!isStrongBeat(-1))
    #expect(isStrongBeat(-Progression.ticksPerBar))
}

@Test func chordVoicingsSitBelowMelody() {
    let c = Chord(root: 0, quality: .major), g = Chord(root: 7, quality: .major)
    let am = Chord(root: 9, quality: .minor), f = Chord(root: 5, quality: .major)
    #expect(c.voicing == [60, 64, 67] && g.voicing == [55, 59, 62] && am.voicing == [57, 60, 64] && f.voicing == [53, 57, 60])
    let diatonic = [c, Chord(root: 2, quality: .minor), Chord(root: 4, quality: .minor), f, g, am]
    for ch in diatonic {
        let v = ch.voicing
        #expect(v.count == 3 && v.allSatisfy(ch.contains) && Set(v.map { $0 % 12 }).count == 3, "\(ch)")
        #expect((53...60).contains(v[0]) && v == v.sorted() && v[2] <= 67, "\(ch)")
    }
}
