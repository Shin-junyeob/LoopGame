/// Follow-along judgement (plan §5). Times in ms; note ticks converted with bpm (PPQ 480).
public enum Verdict: Equatable, Sendable { case perfect, good, miss }

public struct InputHit: Equatable, Sendable {
    public var ms: Double
    public var pitch: Int
    public init(ms: Double, pitch: Int) { self.ms = ms; self.pitch = pitch }
}

public struct JudgeResult: Equatable, Sendable {
    public var verdicts: [Verdict]   // one per expected note, same order
    public var passed: Bool          // (perfect+good)/total >= 0.70
}

public enum Timing {
    public static let maxOffsetMs = 150.0
    public static let perfectMs = 50.0
    public static let goodMs = 100.0
    public static let passRatio = 0.70

    public static func ms(tick: Int64, bpm: Double) -> Double {
        Double(tick) * 60000 / (bpm * 480)
    }

    public static func clampOffset(_ ms: Double) -> Double {
        min(max(ms, -maxOffsetMs), maxOffsetMs)
    }

    /// Matches as many notes as possible per pitch: notes in time order each take the EARLIEST unused
    /// same-pitch input within goodMs (input time minus clamped offset) — optimal for equal windows.
    /// Each match is then judged by |Δ|. Wrong pitch never matches unless `anyPitch` (stage 1: any pad).
    public static func judge(expected: [Note], inputs: [InputHit], bpm: Double,
                             userOffsetMs: Double = 0, anyPitch: Bool = false) -> JudgeResult {
        let offset = clampOffset(userOffsetMs)
        var used = Set<Int>()
        var verdicts = [Verdict](repeating: .miss, count: expected.count)
        for n in expected.indices.sorted(by: { expected[$0].tick < expected[$1].tick }) {
            let t = ms(tick: expected[n].tick, bpm: bpm)
            var best: (idx: Int, at: Double)?
            for (i, h) in inputs.enumerated() where !used.contains(i) && (anyPitch || h.pitch == expected[n].pitch) {
                let at = h.ms - offset
                if abs(at - t) <= goodMs, best == nil || at < best!.at { best = (i, at) }
            }
            guard let b = best else { continue }
            used.insert(b.idx)
            verdicts[n] = abs(b.at - t) <= perfectMs ? .perfect : .good
        }
        let hits = verdicts.filter { $0 != .miss }.count
        let passed = !expected.isEmpty && Double(hits) / Double(expected.count) >= passRatio
        return JudgeResult(verdicts: verdicts, passed: passed)
    }

    /// Stage-1 calibration: median of (tap − nearest expected note), clamped to ±150 ms.
    public static func calibrate(taps: [Double], expected: [Note], bpm: Double) -> Double {
        let times = expected.map { ms(tick: $0.tick, bpm: bpm) }
        let deltas = taps.compactMap { tap in
            times.map { tap - $0 }.min { abs($0) < abs($1) }
        }.sorted()
        guard !deltas.isEmpty else { return 0 }
        let n = deltas.count
        let med = n % 2 == 1 ? deltas[n / 2] : (deltas[n / 2 - 1] + deltas[n / 2]) / 2
        return clampOffset(med)
    }
}
