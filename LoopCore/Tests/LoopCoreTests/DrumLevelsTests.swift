import AVFoundation
import Testing
@testable import LoopCore

private let samples = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/Samples/drums/kit")

private func load(_ pad: Int) throws -> [Float] {
    let file = try AVAudioFile(forReading: samples.appendingPathComponent("\(pad).caf"))
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

/// Loudness order kick ≥ snare > open hat > closed hat, kick ≥ closed hat + 4 dB, every single hit ≤ 0 dBFS.
private func expectBalanced(_ kit: [[Float]], rate: Double) {
    let gains = DrumLevels.gains(kit, rate: rate)
    let mixed = zip(kit, gains).map { pad, g in pad.map { $0 * g } }
    let db = mixed.map { DrumLevels.loudness($0, rate: rate) }
    #expect(db[0] >= db[1] && db[1] > db[3] && db[3] > db[2], "\(db)")
    #expect(db[0] - db[2] >= 4, "\(db)")
    #expect(mixed.allSatisfy { ($0.map(abs).max() ?? 0) <= 1 })
}

/// The shipped "kit": synthesized kick + VCSL snare/hats/tom/crash, at the files' 44.1 kHz.
@Test func acousticKitIsBalanced() throws {
    let rate = 44_100.0
    expectBalanced([DrumLevels.kick(rate: rate)] + (try (1..<Timbres.drumPads).map(load)), rate: rate)
}

/// The failure that was reported: peak-normalized sub-heavy kick (50 Hz) against a bright full-scale hat.
@Test func boomyKickIsLiftedAboveBrightHats() {
    let rate = 48_000.0
    var seed: UInt32 = 7
    let noise = (0..<Int(rate)).map { _ -> Float in
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24) * 1.8 - 0.9
    }
    let boom = (0..<Int(rate / 2)).map { sin(2 * .pi * 50 * Float($0) / Float(rate)) * 0.89 }
    expectBalanced([boom, noise, Array(noise.prefix(4_800)), noise, boom, noise], rate: rate)
}
