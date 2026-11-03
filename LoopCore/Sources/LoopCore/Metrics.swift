public enum Metrics {
    public static let sixteenth: Int64 = ppq / 4  // 120 ticks

    // MARK: hard (pitched roles only)
    public static func allInScale(_ notes: [Note], key: Key) -> Bool {
        notes.allSatisfy { key.contains($0.pitch) }
    }
    public static func strongBeatsAreChordTones(_ notes: [Note], progression: Progression) -> Bool {
        notes.allSatisfy { !isStrongBeat($0.tick) || progression.chord(atTick: $0.tick).contains($0.pitch) }
    }
    /// |cand - orig| / orig. Pass (<= 0.20) is the caller's threshold.
    public static func countChange(candidate: [Note], original: [Note]) -> Double {
        guard !original.isEmpty else { return candidate.isEmpty ? 0 : .infinity }
        return Double(abs(candidate.count - original.count)) / Double(original.count)
    }

    // MARK: statistical (drums too)
    /// Mean |onset - nearest 16th grid line| in ticks.
    public static func gridError(_ notes: [Note]) -> Double {
        guard !notes.isEmpty else { return 0 }
        let sum = notes.reduce(Int64(0)) { acc, n in
            let r = n.tick % sixteenth
            return acc + min(r, sixteenth - r)
        }
        return Double(sum) / Double(notes.count)
    }
    /// candidate grid error / original grid error (weak <= 0.6, strong <= 0.2 at call site).
    public static func gridErrorRatio(candidate: [Note], original: [Note]) -> Double {
        let o = gridError(original), c = gridError(candidate)
        return o == 0 ? (c == 0 ? 0 : .infinity) : c / o
    }
    /// Rhythm-weighted similarity (plan-approved ±2 semitone tolerance); pitch correctness is enforced by the hard metrics.
    /// Greedy one-to-one onset matching within 120 ticks; pitched: |pitch diff| <= 2, drums: pad equal.
    public static func onsetF1(candidate: [Note], reference: [Note], drums: Bool,
                               tolerance: Int64 = sixteenth, pitchTolerance: Int = 2) -> Double {
        var used = Set<Int>()
        var tp = 0
        for c in candidate.sorted(by: { $0.tick < $1.tick }) {
            var best: (idx: Int, dt: Int64)?
            for (i, r) in reference.enumerated() where !used.contains(i) {
                let dt = abs(c.tick - r.tick)
                guard dt <= tolerance else { continue }
                guard drums ? c.pitch == r.pitch : abs(c.pitch - r.pitch) <= pitchTolerance else { continue }
                if best == nil || dt < best!.dt { best = (i, dt) }
            }
            if let b = best { used.insert(b.idx); tp += 1 }
        }
        guard !candidate.isEmpty, !reference.isEmpty else { return candidate.isEmpty && reference.isEmpty ? 1 : 0 }
        let p = Double(tp) / Double(candidate.count), r = Double(tp) / Double(reference.count)
        return p + r == 0 ? 0 : 2 * p * r / (p + r)
    }
}
