import CAtomic
import Foundation
import Testing
@testable import LoopCore

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let sr: Int64 = 44100
private let tenMinutes = Int(600 * sr)

private func render(_ specs: [(samples: [Float], events: [Int64], bars: Int64, gain: Float)], bpm: Int64,
                    split seed: UInt64?, into out: UnsafeMutablePointer<Float>, count: Int) {
    let swap = StateSwap(free: RenderState.free)
    swap.swap(to: RenderState(sampleRate: sr, bpm: bpm, tracks: specs).boxed(), engineRunning: false)
    var renderer = Renderer(slot: swap.slot)
    defer { renderer.deallocate() }
    guard let seed else { return renderer.render(into: out, frameCount: count) }
    var rng = SplitMix64(state: seed)
    var done = 0
    while done < count {
        let n = min(Int.random(in: 64...4096, using: &rng), count - done)
        renderer.render(into: out + done, frameCount: n)
        done += n
    }
}

@Test(arguments: [60, 70, 97, 160] as [Int64])
func splitRenderIsBitIdenticalToOneShot(bpm: Int64) {
    var rng = SplitMix64(state: 42)
    let bars: [Int64] = [1, 2, 4, 8, 1, 2, 4, 8]
    let specs = (0..<8).map { t in
        let length = t == 7 ? 20000 : Int.random(in: 200...1500, using: &rng)  // track 7 overlaps itself
        let samples = (0..<length).map { _ in Float.random(in: -1...1, using: &rng) }
        let loopTicks = bars[t] * 4 * ppq
        let events = Set((0..<Int(bars[t]) * 4).map { _ in Int64.random(in: 0..<loopTicks, using: &rng) }).sorted()
        return (samples: samples, events: events, bars: bars[t], gain: Float(t + 1) / 8)
    }
    let oneShot = UnsafeMutablePointer<Float>.allocate(capacity: tenMinutes)
    let split = UnsafeMutablePointer<Float>.allocate(capacity: tenMinutes)
    defer { oneShot.deallocate(); split.deallocate() }
    render(specs, bpm: bpm, split: nil, into: oneShot, count: tenMinutes)
    render(specs, bpm: bpm, split: UInt64(bpm), into: split, count: tenMinutes)
    #expect(memcmp(oneShot, split, tenMinutes * MemoryLayout<Float>.size) == 0)
    #expect((0..<tenMinutes).contains { oneShot[$0] != 0 })
}

@Test(arguments: [60, 70, 97, 160] as [Int64])
func loopStartsLandOnClockFrames(bpm: Int64) {
    // Impulse at tick 0 per track; distinct power-of-two gains make overlapping starts decodable.
    let bars: [Int64] = [1, 2, 4, 8, 1, 2, 4, 8]
    let specs = (0..<8).map { t in (samples: [Float(1)], events: [Int64(0)], bars: bars[t], gain: Float(1 << t)) }
    var expected: [Int: Float] = [:]
    for t in 0..<8 {
        var k: Int64 = 0
        while true {
            let f = Int(Clock.frame(tick: k * bars[t] * 4 * ppq, sampleRate: sr, bpm: bpm))
            if f >= tenMinutes { break }
            expected[f, default: 0] += Float(1 << t)
            k += 1
        }
    }
    let out = UnsafeMutablePointer<Float>.allocate(capacity: tenMinutes)
    defer { out.deallocate() }
    render(specs, bpm: bpm, split: 7, into: out, count: tenMinutes)
    var actual: [Int: Float] = [:]
    for f in 0..<tenMinutes where out[f] != 0 { actual[f] = out[f] }
    #expect(actual == expected)
}

@Test(arguments: [(44100, 48000), (48000, 44100), (44100, 44100)], [1, 2, 997, 44100, 123_457])
func resampleLength(rates: (Int, Int), length: Int) {
    let x = (0..<length).map { Float($0 % 100) }
    let y = resampleLinear(x, from: rates.0, to: rates.1)
    let exact = Double(length) * Double(rates.1) / Double(rates.0)
    #expect(abs(Double(y.count) - exact) <= 1)
    if rates.0 == rates.1 { #expect(y == x) }
}

@Test func liveHitIsVoicedAtNextBufferStartAndReported() {
    let swap = StateSwap(free: RenderState.free)
    swap.swap(to: RenderState(sampleRate: sr, bpm: 120, tracks: [], pads: [[0.5, 0.25, 0.125]]).boxed(), engineRunning: false)
    let queue = catomic_live_create()
    defer { catomic_live_destroy(queue) }
    var renderer = Renderer(slot: swap.slot)
    renderer.live = queue
    defer { renderer.deallocate() }
    let out = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    defer { out.deallocate() }
    renderer.render(into: out, frameCount: 4)
    #expect((0..<4).allSatisfy { out[$0] == 0 })
    #expect(catomic_live_push(queue, 7 << 8 | 0))
    #expect(catomic_live_push(queue, 8 << 8 | 5))  // unknown pad: reported, not voiced
    #expect(catomic_live_result(queue, 7) == -1)
    renderer.render(into: out, frameCount: 4)
    #expect(Array(UnsafeBufferPointer(start: out, count: 4)) == [0.5, 0.25, 0.125, 0])
    #expect(catomic_live_result(queue, 7) == 4)
    #expect(catomic_live_result(queue, 8) == 4)
}
