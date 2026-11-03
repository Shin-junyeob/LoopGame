import Foundation
import Testing
@testable import LoopCore

private let modelDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/LoopCore/Resources/model")

@Test(arguments: ["drums", "bass", "chords", "melody"])
func modelLoadsAndIsNormalized(role: String) throws {
    let size = try FileManager.default.attributesOfItem(
        atPath: modelDir.appendingPathComponent("\(role).json").path)[.size] as! Int
    #expect(size <= 1_000_000)

    let m = try NGramModel.load(role: role)
    #expect(m.role == role && m.order == 3)
    // Backoff must yield a proper distribution, for seen and never-seen contexts alike.
    for ctx in [["<s>", "<s>"], ["15:+9", "1:-9"]] {
        let z = m.vocab.reduce(0.0) { $0 + exp(m.logProb($1, context: ctx)) }
        #expect(abs(z - 1) < 0.01, "\(role) \(ctx) sums to \(z)")
    }
    #expect(m.logProb("nope", context: []) == m.logProb("<unk>", context: []))
}
