public enum Clock {
    /// floor(tick * sr * 60 / (bpm * ppq)) in exact integer arithmetic, always from an absolute tick.
    public static func frame(tick: Int64, sampleRate: Int64, bpm: Int64) -> Int64 {
        floorDiv(tick * sampleRate * 60, bpm * ppq)
    }

    /// Nearest tick to `frame` (inverse of `frame(tick:)`, within half a tick).
    public static func tick(frame: Int64, sampleRate: Int64, bpm: Int64) -> Int64 {
        let den = sampleRate * 60
        return floorDiv(2 * frame * bpm * ppq + den, 2 * den)
    }

    /// `tick` folded into 0 ..< loopTicks; loops repeat from tick 0, so this is the tick relative to its loop start.
    public static func wrap(tick: Int64, loopTicks: Int64) -> Int64 {
        (tick % loopTicks + loopTicks) % loopTicks
    }

    /// Loop-phase tick for a recorded hit. A hit just before the take's downbeat was aimed at the downbeat,
    /// so it lands on the downbeat instead of wrapping to the loop end (where it would show and sound a loop late).
    // ponytail: early hits lose their few ms of earliness; keep a signed offset if raw takes must stay exact.
    public static func takeTick(hit: Int64, takeStart: Int64, loopTicks: Int64) -> Int64 {
        wrap(tick: max(hit, takeStart), loopTicks: loopTicks)
    }

    /// Where a loop-phase `tick` is drawn: ticks from the take's start phase, so a take's first note is at 0.
    public static func displayTick(_ tick: Int64, startPhase: Int64, loopTicks: Int64) -> Int64 {
        wrap(tick: tick - startPhase, loopTicks: loopTicks)
    }

    /// Same musical position at a new sample rate (error < 1 new-rate frame).
    public static func rescale(frame: Int64, from oldRate: Int64, to newRate: Int64) -> Int64 {
        floorDiv(frame * newRate, oldRate)
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let (q, r) = a.quotientAndRemainder(dividingBy: b)
        return r != 0 && (r < 0) != (b < 0) ? q - 1 : q
    }
}

/// A loop-station take started by its first hit: `start` is that hit's heard tick snapped to the nearest beat
/// (exactly between two beats: the later one), and the take lasts `loopTicks` from there. Notes are loop-phase ticks
/// on the absolute grid, so the take stays in phase with the other tracks; `startPhase` is where it began.
public struct TakeWindow: Equatable, Sendable {
    public let start: Int64, loopTicks: Int64
    public var end: Int64 { start + loopTicks }
    /// Also the first hit's note tick: the first hit is always stored at the take's start.
    public var startPhase: Int64 { Clock.wrap(tick: start, loopTicks: loopTicks) }

    public init(firstHit: Int64, bars: Int) {
        start = Clock.floorDiv(firstHit + ppq / 2, ppq) * ppq
        loopTicks = Int64(bars) * Progression.ticksPerBar
    }

    /// Loop-phase tick for a later hit, or nil outside the take. The window is shifted a 16th early so a hit just
    /// before the end (aimed at the next loop's downbeat) is ignored and one just before the start lands on it.
    public func tick(hit: Int64) -> Int64? {
        guard hit >= start - ppq / 4 && hit < end - ppq / 4 else { return nil }
        return Clock.takeTick(hit: hit, takeStart: start, loopTicks: loopTicks)
    }
}

/// Maps mach host time to an output frame, anchored at a render callback's (mHostTime, mSampleTime).
public struct HostClock {
    public var anchorHostTime: UInt64
    public var anchorSampleTime: Int64
    public var sampleRate: Int64
    /// mach_timebase_info: nanoseconds = hostTicks * numer / denom.
    public var timebaseNumer: Int64
    public var timebaseDenom: Int64

    public init(anchorHostTime: UInt64, anchorSampleTime: Int64, sampleRate: Int64, timebaseNumer: Int64, timebaseDenom: Int64) {
        self.anchorHostTime = anchorHostTime
        self.anchorSampleTime = anchorSampleTime
        self.sampleRate = sampleRate
        self.timebaseNumer = timebaseNumer
        self.timebaseDenom = timebaseDenom
    }

    /// Judged position = anchor frame + elapsed host time - latency + user offset (both in seconds).
    public func frame(hostTime: UInt64, latency: Double, userOffset: Double) -> Int64 {
        let dHost = Int64(bitPattern: hostTime &- anchorHostTime)
        let dFrames = Clock.floorDiv(dHost * timebaseNumer * sampleRate, timebaseDenom * 1_000_000_000)
        let sr = Double(sampleRate)
        return anchorSampleTime + dFrames - Int64((latency * sr).rounded()) + Int64((userOffset * sr).rounded())
    }

    /// Nearest tick heard at `hostTime`, when the anchor's sample time is the renderer position (tick 0 = frame 0)
    /// and `latency` is the output latency, so a hit lands where the user heard it. The one mapping for "where is the
    /// audible output at host time T": recorded hits (`AudioHost.record`) and the heard position ending a take
    /// (`AudioHost.advanceTake`) and the score's playhead (`Playhead.fraction`) all use it, so line and notes agree.
    public func tick(hostTime: UInt64, latency: Double, bpm: Int64) -> Int64 {
        Clock.tick(frame: frame(hostTime: hostTime, latency: latency, userOffset: 0), sampleRate: sampleRate, bpm: bpm)
    }
}

public enum Playhead {
    /// Audible position at `hostTime` as a fraction of the loop drawn from `loopStart`: 0 = its first bar line (a take's
    /// downbeat), 1 = its end. In playback it keeps counting past 1, so floor() is the loop cycle and the remainder the phase. Same `HostClock.tick` as recorded hits.
    public static func fraction(clock: HostClock, hostTime: UInt64, latency: Double, bpm: Int64,
                                loopStart: Int64, loopTicks: Int64) -> Double {
        Double(clock.tick(hostTime: hostTime, latency: latency, bpm: bpm) - loopStart) / Double(loopTicks)
    }
}
