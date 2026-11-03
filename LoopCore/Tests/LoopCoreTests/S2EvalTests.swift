import Foundation
import Testing
@testable import LoopCore

/// Plan §6 S2 go/no-go on the 300-item holdout. Opt-in: `S2_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter S2Eval`.
private struct Fixture: Decodable {
    struct Item: Decodable {
        struct K: Decodable { let root: Int; let mode: String }
        struct C: Decodable { let root: Int; let quality: String }
        let role: String; let key: K?; let progression: [C]?; let bars: Int
        let original: [[Int]]; let jittered: [[Int]]
    }
    let items: [Item]
}
private func notes(_ a: [[Int]]) -> [Note] { a.map { Note(tick: Int64($0[0]), duration: Int64($0[1]), pitch: $0[2], velocity: $0[3]) } }
private func mean(_ x: [Double]) -> Double { x.isEmpty ? .nan : x.reduce(0, +) / Double(x.count) }
private func f(_ x: Double) -> String { String(format: "%.3f", x) }

private struct SplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15; var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
/// Paired bootstrap 95% CI of mean(d).
private func bootstrapCI(_ d: [Double], resamples: Int = 2000, seed: UInt64 = 2026) -> (Double, Double) {
    var rng = SplitMix(s: seed)
    let means = (0..<resamples).map { _ in mean((0..<d.count).map { _ in d[Int.random(in: 0..<d.count, using: &rng)] }) }.sorted()
    return (means[Int(0.025 * Double(resamples))], means[Int(0.975 * Double(resamples)) - 1])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["S2_EVAL"] != nil))
func S2Eval() throws {
    // S2_SET=val: tune on the train-internal split (tools/train/val), never on holdout.
    let env = ProcessInfo.processInfo.environment, val = env["S2_SET"] == "val"
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let valDir = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tools/train/val")
    let url = val ? valDir.appendingPathComponent("val.json") : here.appendingPathComponent("Fixtures/holdout.json")
    let items = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).items
    let roles = ["drums", "bass", "chords", "melody"]
    let models = try Dictionary(uniqueKeysWithValues: roles.map { r in
        (r, val ? try JSONDecoder().decode(NGramModel.self, from: Data(contentsOf: valDir.appendingPathComponent("\(r).json")))
                : try NGramModel.load(role: r))
    })
    // S2_SETTINGS="w:4:12,w:2:8,s:0.8:5,s:0.3:3" (strength:closeness:deletion) overrides for sweeps.
    let settings = env["S2_SETTINGS"].map { $0.split(separator: ",").map { p in
        let a = p.split(separator: ":")
        return Corrector.Setting(strength: a[0] == "w" ? .weak : .strong, closeness: Double(a[1])!, deletion: Double(a[2])!)
    } } ?? Corrector.settings

    struct Row { var role: String; var hard: [Bool] = []; var stat: [Bool] = []; var f1w: [Double] = []; var f1s: [Double] = []
        var none = 0; var n = 0; var b3b: [Double] = []; var rule: [Double] = []; var lat: [Double] = [] }
    var rows = Dictionary(uniqueKeysWithValues: (roles + ["all"]).map { ($0, Row(role: $0)) })
    for it in items {
        let drums = it.role == "drums"
        let key = it.key.map { Key(root: $0.root, mode: $0.mode == "major" ? .major : .minor) } ?? Key(root: 0, mode: .major)
        let prog = it.progression.map { Progression($0.map { Chord(root: $0.root, quality: $0.quality == "major" ? .major : .minor) }) } ?? .cGAmF
        let ctx = Corrector.Context(drums: drums, key: key, progression: prog, bars: it.bars)
        let input = notes(it.jittered), clean = notes(it.original), model = models[it.role]!

        let t0 = ContinuousClock.now
        let shown = Corrector.suggest(input, context: ctx, model: model, settings: settings)
        let el = (ContinuousClock.now - t0).components; let ms = Double(el.seconds) * 1000 + Double(el.attoseconds) / 1e15
        let raw = Corrector.candidates(input, context: ctx, model: model, settings: settings)
        let rule = Corrector.ruleBaseline(input, context: ctx)
        if ProcessInfo.processInfo.environment["S2_DIAG"] != nil {
            print("DIAG", it.role, raw.map { f(Metrics.onsetF1(candidate: $0.notes, reference: clean, drums: drums)) }.joined(separator: " "),
                  f(Metrics.onsetF1(candidate: rule, reference: clean, drums: drums)), f(Metrics.onsetF1(candidate: input, reference: clean, drums: drums)), shown.map { f($0.f1) })
        }
        let best = shown.first?.notes ?? input  // no suggestion -> user keeps the input
        for r in [it.role, "all"] {
            var row = rows[r]!
            row.n += 1; row.lat.append(ms)
            if shown.isEmpty { row.none += 1 }
            for c in raw {
                row.hard.append((drums || (Metrics.allInScale(c.notes, key: key) && Metrics.strongBeatsAreChordTones(c.notes, progression: prog)))
                                && Metrics.countChange(candidate: c.notes, original: input) <= 0.2)
                row.stat.append(Corrector.passes(c, input: input, context: ctx))
                if c.strength == .weak { row.f1w.append(c.f1) } else { row.f1s.append(c.f1) }
            }
            row.b3b.append(Metrics.onsetF1(candidate: best, reference: clean, drums: drums))
            row.rule.append(Metrics.onsetF1(candidate: rule, reference: clean, drums: drums))
            rows[r] = row
        }
    }
    let modelDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/LoopCore/Resources/model")
    let sizes = try roles.map { try FileManager.default.attributesOfItem(atPath: modelDir.appendingPathComponent("\($0).json").path)[.size] as! Int }
    var out = "| role | n | hard | stat(cand) | F1 weak | F1 strong | none | restore B3b | restore rule | diff [95% CI] | lat mean/p95 ms |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
    for r in roles + ["all"] {
        let w = rows[r]!
        let d = zip(w.b3b, w.rule).map { $0 - $1 }, ci = bootstrapCI(d), lat = w.lat.sorted()
        func rate(_ b: [Bool]) -> String { f(Double(b.filter { $0 }.count) / Double(b.count)) }
        out += "| \(r) | \(w.n) | \(rate(w.hard)) | \(rate(w.stat)) | \(f(mean(w.f1w))) | \(f(mean(w.f1s))) | \(f(Double(w.none) / Double(w.n))) | \(f(mean(w.b3b))) | \(f(mean(w.rule))) | \(f(mean(d))) [\(f(ci.0)), \(f(ci.1))] | \(f(mean(w.lat))) / \(f(lat[Int(0.95 * Double(lat.count)) - 1])) |\n"
    }
    out += "\nmodel sizes (bytes): " + zip(roles, sizes).map { "\($0)=\($1)" }.joined(separator: ", ") + "\n"
    print("S2EVAL_BEGIN\n" + out + "S2EVAL_END")
}
