import AVFoundation

/// Offline export: the same Renderer the engine uses, run from frame 0 into one buffer, then written by AVAudioFile.
public enum Exporter {
    public static func render(sampleRate: Int64, bpm: Int64,
                              songTracks: [(sounds: [[Float]], events: [Int64], eventSounds: [Int], bars: Int64, gain: Float)],
                              frameCount: Int) -> [Float] {
        let swap = StateSwap(free: RenderState.free)
        swap.swap(to: RenderState(sampleRate: sampleRate, bpm: bpm, songTracks: songTracks).boxed(), engineRunning: false)
        var renderer = Renderer(slot: swap.slot)
        defer { renderer.deallocate() }
        var out = [Float](repeating: 0, count: frameCount)
        out.withUnsafeMutableBufferPointer { renderer.render(into: $0.baseAddress!, frameCount: frameCount) }
        return out
    }

    /// Mono file: `.m4a` -> AAC 128 kbps, anything else (`.wav`) -> 16-bit PCM.
    public static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let settings: [String: Any] = url.pathExtension == "m4a"
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }
}
