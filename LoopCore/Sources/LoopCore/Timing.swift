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

    /// Greedy in note-time order: each note takes the nearest unused input with the same
    /// pitch within goodMs (input time minus clamped offset). Wrong pitch never matches.
    /// ponytail: greedy, not optimal assignment; fine for sparse loop notes.
    public static func judge(expected: [Note], inputs: [InputHit], bpm: Double,
                             userOffsetMs: Double = 0) -> JudgeResult {
        let offset = clampOffset(userOffsetMs)
        var used = Set<Int>()
        let verdicts: [Verdict] = expected.map { note in
            let t = ms(tick: note.tick, bpm: bpm)
            var best: (idx: Int, d: Double)?
            for (i, h) in inputs.enumerated() where !used.contains(i) && h.pitch == note.pitch {
                let d = abs(h.ms - offset - t)
                if d <= goodMs, best == nil || d < best!.d { best = (i, d) }
            }
            guard let b = best else { return .miss }
            used.insert(b.idx)
            return b.d <= perfectMs ? .perfect : .good
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
