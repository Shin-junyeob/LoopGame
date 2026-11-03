import Testing
@testable import LoopCore

// bpm 120: one beat = 500 ms = 480 ticks; note k at tick 480*k*2 -> 1000*k ms.
private func notes(_ n: Int, pitch: Int = 36) -> [Note] {
    (0..<n).map { Note(tick: Int64($0) * 960, pitch: pitch) }
}
private func hits(_ n: Int, delta: Double, pitch: Int = 36) -> [InputHit] {
    (0..<n).map { InputHit(ms: Double($0) * 1000 + delta, pitch: pitch) }
}
private func judge(_ e: [Note], _ i: [InputHit], off: Double = 0) -> JudgeResult {
    Timing.judge(expected: e, inputs: i, bpm: 120, userOffsetMs: off)
}

@Suite struct TimingTests {
    @Test func windowBoundaries() {
        #expect(judge(notes(1), hits(1, delta: 50)).verdicts == [.perfect])
        #expect(judge(notes(1), hits(1, delta: -50)).verdicts == [.perfect])
        #expect(judge(notes(1), hits(1, delta: 51)).verdicts == [.good])
        #expect(judge(notes(1), hits(1, delta: 100)).verdicts == [.good])
        #expect(judge(notes(1), hits(1, delta: 101)).verdicts == [.miss])
    }

    @Test func wrongPitchIsMiss() {
        #expect(judge(notes(1), hits(1, delta: 0, pitch: 38)).verdicts == [.miss])
    }

    @Test func oneInputOneNote() {
        let e = [Note(tick: 0, pitch: 36), Note(tick: 48, pitch: 36)]  // 0 ms and 50 ms
        let r = judge(e, [InputHit(ms: 25, pitch: 36)])
        #expect(r.verdicts.filter { $0 != .miss }.count == 1)
    }

    @Test func passThreshold() {
        // 70 of 100 hit -> pass; 69 of 100 -> fail
        func run(_ ok: Int) -> Bool {
            judge(notes(100), Array(hits(100, delta: 0).prefix(ok))).passed
        }
        #expect(run(70))
        #expect(!run(69))
        #expect(!judge([], []).passed)
    }

    @Test func calibrationClamp() {
        let e = notes(3)
        func cal(_ d: Double) -> Double { Timing.calibrate(taps: hits(3, delta: d).map(\.ms), expected: e, bpm: 120) }
        #expect(cal(149) == 149)
        #expect(cal(150) == 150)
        #expect(cal(151) == 150)
        #expect(cal(-149) == -149)
        #expect(cal(-151) == -150)
        #expect(Timing.calibrate(taps: [], expected: e, bpm: 120) == 0)
    }

    @Test func calibrationMedianIgnoresOutlier() {
        let taps: [Double] = [80, 1082, 2400]
        #expect(Timing.calibrate(taps: taps, expected: notes(3), bpm: 120) == 82)
    }

    @Test func offsetShiftsJudgement() {
        let e = notes(10), late = hits(10, delta: 80)
        #expect(!judge(e, late).verdicts.contains(.perfect))       // 80 ms = good only
        let far = hits(10, delta: 120)
        #expect(!judge(e, far).passed)                              // before calibration
        let off = Timing.calibrate(taps: far.map(\.ms), expected: e, bpm: 120)
        #expect(judge(e, far, off: off).passed)
        #expect(judge(e, far, off: off).verdicts.allSatisfy { $0 == .perfect })
    }
}
