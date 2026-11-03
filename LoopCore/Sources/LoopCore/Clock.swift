public enum Clock {
    /// floor(tick * sr * 60 / (bpm * ppq)) in exact integer arithmetic, always from an absolute tick.
    public static func frame(tick: Int64, sampleRate: Int64, bpm: Int64) -> Int64 {
        floorDiv(tick * sampleRate * 60, bpm * ppq)
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
}
