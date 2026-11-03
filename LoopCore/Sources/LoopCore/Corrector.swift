/// S2 corrector, plan §3(b) B3b: the role's n-gram model decodes each note's grid position and pitch
/// inside the G3 mask (in scale; chord tone on beats 1·3; drums keep their pad), by beam search.
/// Runtime: 4 candidates (2 weak, 2 strong) -> Metrics filter -> top 2 by F1 vs the input, or none.
public enum Corrector {
    public struct Context: Sendable {
        public var drums: Bool
        public var key: Key
        public var progression: Progression
        public var bars: Int
        public init(drums: Bool, key: Key, progression: Progression, bars: Int) {
            self.drums = drums; self.key = key; self.progression = progression; self.bars = bars
        }
        var span: Int64 { Int64(bars) * Progression.ticksPerBar }
    }
    public enum Strength: Sendable { case weak, strong }
    public struct Candidate: Sendable {
        public var notes: [Note]
        public var strength: Strength
        public var f1: Double  // onset F1 vs the input
    }

    /// closeness: penalty per 16th / per semitone moved; deletion: penalty per dropped note (100 = off).
    /// Chosen on the train-internal validation split (tools/train/val), see .omc/reports/s2-ai.md.
    /// No insertion: deletions already lowered restoration F1 on validation, so adding notes was not tried.
    struct Setting { var strength: Strength; var closeness: Double; var deletion: Double }
    static let settings = [
        Setting(strength: .weak, closeness: 3.0, deletion: 100),
        Setting(strength: .weak, closeness: 1.5, deletion: 30),
        Setting(strength: .strong, closeness: 1.0, deletion: 16),
        Setting(strength: .strong, closeness: 0.5, deletion: 12),
    ]
    static let beamWidth = 8
    static let window: Int64 = ppq / 8        // ±1/8 beat
    static let pitchWindow = 2                // ±2 semitones
    static let maxCountChange = 0.2

    /// What the UI shows: filtered candidates, best F1 first, at most 2. Empty = "no suggestion this time".
    public static func suggest(_ input: [Note], context: Context, model: NGramModel) -> [Candidate] {
        suggest(input, context: context, model: model, settings: settings)
    }
    static func suggest(_ input: [Note], context: Context, model: NGramModel, settings: [Setting]) -> [Candidate] {
        Array(candidates(input, context: context, model: model, settings: settings)
            .filter { passes($0, input: input, context: context) }
            .enumerated().sorted { ($0.element.f1, $1.offset) > ($1.element.f1, $0.offset) }  // tie: gentler first
            .map(\.element)
            .prefix(2))
    }

    /// Unfiltered candidates. Never show these directly.
    public static func candidates(_ input: [Note], context: Context, model: NGramModel) -> [Candidate] {
        candidates(input, context: context, model: model, settings: settings)
    }
    static func candidates(_ input: [Note], context: Context, model: NGramModel, settings: [Setting]) -> [Candidate] {
        guard !input.isEmpty else { return [] }
        return settings.compactMap { s in
            decode(input, context: context, model: model, setting: s).map {
                Candidate(notes: $0, strength: s.strength,
                          f1: Metrics.onsetF1(candidate: $0, reference: input, drums: context.drums))
            }
        }
    }

    /// Hard metrics (G3 + count ±20%) and statistical thresholds (grid ratio, F1 vs input) per strength.
    public static func passes(_ c: Candidate, input: [Note], context: Context) -> Bool {
        if !context.drums {
            guard Metrics.allInScale(c.notes, key: context.key),
                  Metrics.strongBeatsAreChordTones(c.notes, progression: context.progression) else { return false }
        }
        guard Metrics.countChange(candidate: c.notes, original: input) <= maxCountChange else { return false }
        let (grid, f1) = c.strength == .weak ? (0.6, 0.85) : (0.2, 0.65)
        return Metrics.gridErrorRatio(candidate: c.notes, original: input) <= grid && c.f1 >= f1
    }

    /// Ablation baseline (no model): snap to nearest 16th, nearest allowed pitch, drop exact duplicates.
    public static func ruleBaseline(_ input: [Note], context: Context) -> [Note] {
        var seen = Set<[Int64]>()
        return sortedInput(input, context: context).compactMap { n in
            let g = nearestGrid(n.tick, span: context.span)
            let p = context.drums ? n.pitch
                : (0...pitchWindow).lazy.flatMap { [n.pitch - $0, n.pitch + $0] }
                    .first { allowed($0, at: g, context: context) }
            guard let p, seen.insert([g, Int64(p)]).inserted else { return nil }
            var out = n; out.tick = g; out.pitch = p
            return out
        }
    }

    // MARK: beam search

    struct State {
        var score = 0.0
        var context: [String]
        var prevDegree: Int?
        var lastTick: Int64 = -1
        var lastPitch = Int.min
        var delta = 0  // output count - consumed input count
        var notes: [Note] = []
        var key: String { "\(context)|\(prevDegree ?? -99)|\(lastTick)|\(lastPitch)|\(delta)" }
    }

    static func decode(_ input: [Note], context ctx: Context, model: NGramModel, setting s: Setting) -> [Note]? {
        let notes = sortedInput(input, context: ctx)
        let maxDelta = Int(Double(notes.count) * maxCountChange)
        var beam = [State(context: Array(repeating: "<s>", count: model.order - 1))]
        for n in notes {
            var next: [String: State] = [:]
            func push(_ st: State) {
                let k = st.key
                if let old = next[k], old.score >= st.score { return }
                next[k] = st
            }
            for st in beam {
                if abs(st.delta - 1) <= maxDelta {
                    var d = st; d.delta -= 1; d.score -= s.deletion; push(d)
                }
                for g in gridOptions(n.tick, span: ctx.span) where g >= st.lastTick {
                    for p in pitchOptions(n.pitch, at: g, context: ctx) where g > st.lastTick || p > st.lastPitch {
                        let (tok, deg) = token(tick: g, pitch: p, prevDegree: st.prevDegree, context: ctx)
                        var k = st
                        k.score += model.logProb(tok, context: st.context)
                            - s.closeness * (Double(abs(g - n.tick)) / Double(Metrics.sixteenth) + Double(abs(p - n.pitch)))
                        k.context = Array((st.context + [tok]).suffix(model.order - 1))
                        k.prevDegree = deg
                        k.lastTick = g; k.lastPitch = p
                        var out = n; out.tick = g; out.pitch = p
                        k.notes.append(out)
                        push(k)
                    }
                }
            }
            beam = Array(next.values.sorted { $0.score > $1.score }.prefix(beamWidth))
            if beam.isEmpty { return nil }
        }
        return beam.max { a, b in
            a.score + model.logProb("</s>", context: a.context) < b.score + model.logProb("</s>", context: b.context)
        }?.notes
    }

    // MARK: helpers (token definition mirrors tools/train/train.py `tokens`)

    static func sortedInput(_ input: [Note], context: Context) -> [Note] {
        input.sorted { (nearestGrid($0.tick, span: context.span), $0.pitch) < (nearestGrid($1.tick, span: context.span), $1.pitch) }
    }
    static func nearestGrid(_ t: Int64, span: Int64) -> Int64 {
        let q = Metrics.sixteenth
        return min(max(0, (t + q / 2) / q * q), span - q)
    }
    /// 16th-grid lines within ±1/8 beat (clamped into the loop).
    static func gridOptions(_ t: Int64, span: Int64) -> [Int64] {
        let q = Metrics.sixteenth
        let lo = (t - window + q - 1) / q * q, hi = (t + window) / q * q
        let gs = Set(stride(from: max(0, lo), through: hi, by: Int(q)).map { min($0, span - q) })
        return gs.isEmpty ? [nearestGrid(t, span: span)] : gs.sorted()
    }
    static func pitchOptions(_ x: Int, at g: Int64, context: Context) -> [Int] {
        context.drums ? [x] : (x - pitchWindow...x + pitchWindow).filter { allowed($0, at: g, context: context) }
    }
    /// G3 mask: in scale, and a chord tone on beats 1·3.
    static func allowed(_ p: Int, at g: Int64, context: Context) -> Bool {
        context.key.contains(p) && (!isStrongBeat(g) || context.progression.chord(atTick: g).contains(p))
    }
    static func token(tick: Int64, pitch: Int, prevDegree: Int?, context: Context) -> (String, Int?) {
        let pos = (tick % Progression.ticksPerBar) / Metrics.sixteenth
        if context.drums { return ("\(pos):\(pitch)", nil) }
        let d = degree(pitch, key: context.key)
        guard let prev = prevDegree else { return ("\(pos):^\(((d % 7) + 7) % 7)", d) }
        let step = max(-14, min(14, d - prev))
        return ("\(pos):\(step >= 0 ? "+" : "")\(step)", d)
    }
    /// Scale degree counted from the key root (7 per octave); pitch must be in scale.
    static func degree(_ pitch: Int, key: Key) -> Int {
        let steps = key.mode == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        let rel = pitch - key.root
        let oct = rel >= 0 ? rel / 12 : -((-rel + 11) / 12)
        return oct * 7 + steps.firstIndex(of: rel - oct * 12)!
    }
}
