import Testing
@testable import LoopCore

/// 48 kHz, nanosecond host ticks, renderer at frame 0 = tick 0 at host 1 s; 120 BPM so a bar (1920 ticks) is 2 s.
nonisolated(unsafe) private let clock = HostClock(anchorHostTime: 1_000_000_000, anchorSampleTime: 0, sampleRate: 48_000,
                              timebaseNumer: 1, timebaseDenom: 1)
private let latency = 0.012, bar = Progression.ticksPerBar
private let start = 3 * bar, loop = 2 * bar  // a 2-bar take whose downbeat is bar 3

/// Host time at which tick `t` is heard: it was rendered `latency` earlier.
private func host(_ t: Int64) -> UInt64 { 1_000_000_000 + UInt64((Double(t) / Double(ppq) * 0.5 + latency) * 1e9) }
private func f(_ t: Int64) -> Double {
    Playhead.fraction(clock: clock, hostTime: host(t), latency: latency, bpm: 120, loopStart: start, loopTicks: loop)
}

@Test func countInIsNegativeLeadIn() {
    #expect(f(start - bar) == -0.5)  // count-in begins one bar (half this loop) before the left edge
    #expect(f(start - bar / 2) == -0.25)
    #expect(f(start - 1) < 0)
}

@Test func downbeatIsZeroAndEndIsOne() {
    #expect(f(start) == 0)
    #expect(f(start + bar) == 0.5)
    #expect(f(start + loop) == 1)
}

@Test func playbackKeepsCountingSoFloorIsCycleAndRemainderPhase() {
    let x = f(start + 2 * loop + loop / 4)
    #expect(x == 2.25)
    #expect(x - x.rounded(.down) == 0.25)
}

@Test func latencyIsTheSameTermAsRecordedHits() {
    // A hit at the same host time lands on the same tick the playhead shows.
    let t = clock.tick(hostTime: host(start + 700), latency: latency, bpm: 120)
    #expect(t == start + 700)
    #expect(f(start + 700) == Double(t - start) / Double(loop))
}
