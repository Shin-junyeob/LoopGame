import AVFoundation

/// Placeholder one-shot samples synthesized in code at `baseRate`, resampled to the engine rate on main.
enum SampleBank {
    static let baseRate = 44_100.0
    static let names = ["kick", "click", "noise", "tone"]

    static let base: [[Float]] = {
        let sr = Float(baseRate)
        func make(_ seconds: Float, _ f: (Float) -> Float) -> [Float] {
            (0..<Int(seconds * sr)).map { f(Float($0) / sr) }
        }
        var seed: UInt32 = 1
        return [
            // Kick: sine sweeping 150 -> 50 Hz with exponential decay.
            make(0.35) { t in sin(2 * .pi * (50 * t + 100 * (1 - exp(-t * 20)) / 20)) * exp(-t * 9) },
            make(0.01) { t in exp(-t * 600) * (t < 0.0005 ? 1 : -0.5) },
            make(0.12) { t in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return (Float(seed >> 8) / Float(1 << 24) * 2 - 1) * exp(-t * 35) * 0.6
            },
            make(0.25) { t in sin(2 * .pi * 440 * t) * exp(-t * 12) * 0.5 },
        ]
    }()

    /// All samples at `rate`, via AVAudioConverter. Length ~= count * rate / baseRate.
    static func samples(at rate: Double) -> [[Float]] {
        guard rate != baseRate else { return base }
        return base.map { resample($0, to: rate) }
    }

    private static func resample(_ x: [Float], to rate: Double) -> [Float] {
        let inFormat = AVAudioFormat(standardFormatWithSampleRate: baseRate, channels: 1)!
        let outFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(x.count))!
        input.frameLength = input.frameCapacity
        x.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
        let capacity = AVAudioFrameCount(Double(x.count) * rate / baseRate) + 1
        let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity)!
        let converter = AVAudioConverter(from: inFormat, to: outFormat)!
        converter.primeMethod = .none
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
