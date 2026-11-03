import Foundation

/// Per-role n-gram weights written by tools/train/train.py (ARPA-style, natural log).
/// Tokens: pitched "pos:interval" (first note "pos:^degree"), drums "pos:pad"; context padded with "<s>".
public struct NGramModel: Decodable, Sendable {
    public let role: String
    public let order: Int
    public let vocab: [String]
    let logp: [String: Double]
    let backoff: [String: Double]

    /// Bundled model for "drums" | "bass" | "chords" | "melody".
    public static func load(role: String) throws -> NGramModel {
        guard let url = Bundle.module.url(forResource: role, withExtension: "json", subdirectory: "model")
            ?? Bundle.module.url(forResource: role, withExtension: "json")
        else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(NGramModel.self, from: Data(contentsOf: url))
    }

    /// ln P(token | context) with backoff; only the last order-1 context tokens are used.
    public func logProb(_ token: String, context: [String]) -> Double {
        var ctx = Array(context.suffix(order - 1))
        var bo = 0.0
        while true {
            if let p = logp[(ctx + [token]).joined(separator: " ")] { return bo + p }
            if ctx.isEmpty { return bo + (logp["<unk>"] ?? -.infinity) }
            bo += backoff[ctx.joined(separator: " ")] ?? 0
            ctx.removeFirst()
        }
    }
}
