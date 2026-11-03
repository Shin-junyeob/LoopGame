import Testing
@testable import LoopCore

private let bpms: [Int64] = [60, 70, 97, 160]
private let rates: [Int64] = [44100, 48000]

private func gcd(_ a: Int64, _ b: Int64) -> Int64 { b == 0 ? a : gcd(b, a % b) }

/// Independent oracle: loop starts sit on whole beats, so seconds = beats * 60 / bpm exactly;
/// frame = floor(beats * 60 * sr / bpm) from a gcd-reduced fraction.
private func oracleFrame(beats: Int64, sampleRate: Int64, bpm: Int64) -> Int64 {
    var num = beats * 60
    var den = bpm
    let g = gcd(num, den)
    if g > 1 { num /= g; den /= g }
    return num * sampleRate / den
}

@Test(arguments: bpms, rates)
func loopStartsMatchOracleFor10Minutes(bpm: Int64, sampleRate: Int64) {
    let tenMin = 600 * sampleRate
    var mismatches = 0
    for bars: Int64 in [1, 2, 4, 8] {
        var k: Int64 = 0
        while true {
            let beats = k * bars * 4
            let f = Clock.frame(tick: beats * ppq, sampleRate: sampleRate, bpm: bpm)
            if f > tenMin { break }
            if f != oracleFrame(beats: beats, sampleRate: sampleRate, bpm: bpm) { mismatches += 1 }
            k += 1
        }
    }
    #expect(mismatches == 0)
}

@Test(arguments: bpms, rates)
func everyTickFrameIsExactFloor(bpm: Int64, sampleRate: Int64) {
    // f*den <= num < (f+1)*den, checked for off-beat ticks too.
    for tick in stride(from: Int64(0), through: 600 * bpm * ppq / 60, by: 37) {
        let f = Clock.frame(tick: tick, sampleRate: sampleRate, bpm: bpm)
        let num = tick * sampleRate * 60, den = bpm * ppq
        #expect(f * den <= num && num < (f + 1) * den)
    }
}

@Test func noOverflowAt10MinBpm160At48k() {
    let tick: Int64 = 10 * 160 * ppq
    let (_, overflow) = tick.multipliedReportingOverflow(by: 48000 * 60)
    #expect(!overflow)
    #expect(Clock.frame(tick: tick, sampleRate: 48000, bpm: 160) == 600 * 48000)
}

@Test func hostTimeToFrameAppleSiliconTimebase() {
    // 24 MHz host clock: numer/denom = 125/3 -> 24_000_000 ticks per second.
    let clock = HostClock(anchorHostTime: 1_000_000, anchorSampleTime: 5000, sampleRate: 48000, timebaseNumer: 125, timebaseDenom: 3)
    #expect(clock.frame(hostTime: 1_000_000, latency: 0, userOffset: 0) == 5000)
    #expect(clock.frame(hostTime: 25_000_000, latency: 0, userOffset: 0) == 53000)
    #expect(clock.frame(hostTime: 25_000_000, latency: 0.010, userOffset: 0) == 52520)
    #expect(clock.frame(hostTime: 25_000_000, latency: 0.010, userOffset: 0.002) == 52616)
    #expect(clock.frame(hostTime: 0, latency: 0, userOffset: 0) == 3000)  // before anchor
    #expect(clock.frame(hostTime: 1_000_500, latency: 0, userOffset: 0) == 5001)
    #expect(clock.frame(hostTime: 1_000_499, latency: 0, userOffset: 0) == 5000)
}

@Test func hostTimeToFrameNanosecondTimebase() {
    let clock = HostClock(anchorHostTime: 0, anchorSampleTime: 0, sampleRate: 44100, timebaseNumer: 1, timebaseDenom: 1)
    #expect(clock.frame(hostTime: 1_000_000_000, latency: 0, userOffset: 0) == 44100)
    #expect(clock.frame(hostTime: 500_000_000, latency: 0.010, userOffset: -0.001) == 22050 - 441 - 44)
}

@Test(arguments: bpms)
func reanchorPreservesTickPositionWithinOneFrame(bpm: Int64) {
    for (from, to) in [(Int64(44100), Int64(48000)), (48000, 44100)] {
        for tick in stride(from: Int64(0), through: 600 * bpm * ppq / 60, by: 113) {
            let old = Clock.frame(tick: tick, sampleRate: from, bpm: bpm)
            let new = Clock.rescale(frame: old, from: from, to: to)
            // |new - old*to/from| < 1 new-rate frame, compared without division.
            let diff = new * from - old * to
            #expect(diff <= 0 && -diff < from)
        }
    }
}
