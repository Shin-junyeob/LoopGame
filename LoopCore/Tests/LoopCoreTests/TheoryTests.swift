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
