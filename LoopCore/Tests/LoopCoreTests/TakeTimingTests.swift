import CAtomic
import Foundation
import Testing
@testable import LoopCore

// Loop-station take timing, stage by stage: hits on the beat (and ±20 ms) must stay on the beat from the
// touch through the AI compare sheet to playback, in phase with tracks of other lengths.

private let bpm: Int64 = 100, sr: Int64 = 48000
private let bar = Progression.ticksPerBar
private let jitter20ms: Int64 = 20 * bpm * ppq / 60_000  // 16 ticks at 100 bpm

/// Circular distance from `tick` to the nearest beat of a loop of `loopTicks`.
private func offBeat(_ tick: Int64, _ loopTicks: Int64) -> Int64 {
    let r = Clock.wrap(tick: tick, loopTicks: loopTicks) % ppq
    return min(r, ppq - r)
}

/// A 2-bar drum take as `AudioHost.record` stores it, from hits on every beat played early/on/late,
/// starting with an early downbeat (it wraps to the loop end, as the -16th record window allows).
private func take(start: Int64) -> LoopTrack {
    let loopTicks = 2 * bar
    let clock = HostClock(anchorHostTime: 240_000_000, anchorSampleTime: 96_000, sampleRate: sr, timebaseNumer: 125, timebaseDenom: 3)
    let latency = 0.012
    let notes = (0..<8).map { beat -> Note in
        let heard = start + Int64(beat) * ppq + [-jitter20ms, 0, jitter20ms][beat % 3]
        // Touch host time = when that tick is heard: frame offset from the anchor plus output latency.
        let seconds = Double(Clock.frame(tick: heard, sampleRate: sr, bpm: bpm) - 96_000) / Double(sr) + latency
        let tick = clock.tick(hostTime: UInt64(240_000_000 + (seconds * 24_000_000).rounded()), latency: latency, bpm: bpm)
        return Note(tick: Clock.wrap(tick: tick, loopTicks: loopTicks), pitch: beat % 2)
    }
    return LoopTrack(role: .drums, timbre: "kit", bars: 2, notes: notes.sorted { $0.tick < $1.tick })
}

@Test(arguments: [4, 5] as [Int64])  // take starting on an even and an odd bar
func recordedHitsLandOnTheBeat(startBar: Int64) {
    let t = take(start: startBar * bar)
    #expect(t.notes.count == 8)
    #expect(t.notes.allSatisfy { offBeat($0.tick, t.loopTicks) <= jitter20ms + 1 })
    // Early downbeat: just before where the take starts in loop phase (the loop end on an even bar), not shifted.
    #expect(t.notes.contains { $0.tick == Clock.wrap(tick: startBar * bar - jitter20ms, loopTicks: t.loopTicks) })
}

@Test(arguments: [4, 5] as [Int64])
func timingCorrectionSnapsToTheBeatNotAway(startBar: Int64) throws {
    let t = take(start: startBar * bar)
    let options = try Corrector.suggest(for: t, key: Key(root: 0, mode: .major), progression: .cGAmF)
    #expect(!options.isEmpty)
    for c in options {
        #expect(c.notes.allSatisfy { offBeat($0.tick, t.loopTicks) == 0 && $0.tick >= 0 && $0.tick < t.loopTicks },
                "\(c.notes.map(\.tick))")
    }
}

@Test func gridSnapWrapsAtTheLoopEnd() {
    let span = 2 * bar
    #expect(Corrector.nearestGrid(span - 16, span: span) == 0)
    #expect(Corrector.gridOptions(span - 16, span: span) == [0])
    #expect(Corrector.gridOptions(span - 60, span: span) == [0, span - Metrics.sixteenth])
    #expect(Corrector.nearestGrid(16, span: span) == 0 && Corrector.gridOptions(70, span: span) == [120])
}

@Test func meanGridOffsetIsSignedAndCircular() {
    let notes = [Note(tick: 2 * bar - 16, pitch: 0), Note(tick: 16, pitch: 0), Note(tick: ppq + 30, pitch: 0)]
    #expect(Metrics.meanGridOffset(notes) == 10)  // (-16 + 16 + 30) / 3
    #expect(Metrics.meanGridOffset([]) == 0)
    #expect(Metrics.meanGridOffset([Note(tick: ppq + 200, pitch: 0)], grid: ppq) == 200)  // 200 late: beat grid sees it
    #expect(Metrics.meanGridOffset([Note(tick: ppq + 200, pitch: 0)]) == -40)  // the 16th grid aliases it to the next 16th
}

/// Frames where each track's impulse fires (gain marks the track) over `frames` frames.
private func fired(_ specs: [(samples: [Float], events: [Int64], bars: Int64, gain: Float)], frames: Int, originTick: Int64 = 0)
    -> [Float: [Int64]] {
    let swap = StateSwap(free: RenderState.free)
    let state = RenderState(sampleRate: sr, bpm: bpm, songTracks: specs.map {
        (sounds: [$0.samples], events: $0.events, eventSounds: [Int](repeating: 0, count: $0.events.count), bars: $0.bars, gain: $0.gain)
    }, originTick: originTick)
    swap.swap(to: state.boxed(), engineRunning: false)
    var renderer = Renderer(slot: swap.slot)
    defer { renderer.deallocate() }
    let out = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { out.deallocate() }
    var done = 0
    while done < frames {  // device-like 128-frame buffers
        let n = min(128, frames - done)
        renderer.render(into: out + done, frameCount: n)
        done += n
    }
    var hits: [Float: [Int64]] = [:]
    for f in 0..<frames where out[f] != 0 { hits[out[f], default: []].append(Int64(f)) }
    return hits
}

@Test func takePlaysInPhaseWithLongerTrackAndMetronome() {
    // 4-bar song track on every downbeat, a 2-bar take on every beat, the 1-bar metronome: all from tick 0.
    let song = (samples: [Float(1)], events: (0..<4).map { $0 * bar }, bars: Int64(4), gain: Float(1))
    let takeTrack = (samples: [Float(1)], events: (0..<8).map { $0 * ppq }, bars: Int64(2), gain: Float(2))
    let click = (samples: [Float(1)], events: [0, ppq, 2 * ppq, 3 * ppq], bars: Int64(1), gain: Float(4))
    let frames = Int(Clock.frame(tick: 8 * bar, sampleRate: sr, bpm: bpm))
    let hits = fired([song, takeTrack, click], frames: frames)
    let beats = (0..<32).map { Clock.frame(tick: $0 * ppq, sampleRate: sr, bpm: bpm) }
    #expect(hits[7] == beats.enumerated().filter { $0.offset % 4 == 0 }.map(\.element))  // all three on downbeats
    #expect(hits[6] == beats.enumerated().filter { $0.offset % 4 != 0 }.map(\.element))  // take + click on 2·3·4
    #expect(hits.keys.sorted() == [6, 7])
}

/// Regression: a hit a few ms before the take's downbeat was wrapped to the loop end
/// (shown at the far right of the score and heard a loop late). It must land on the downbeat.
@Test(arguments: [4, 5] as [Int64])
func earlyDownbeatHitLandsOnDownbeat(startBar: Int64) {
    let bar = Progression.ticksPerBar, loop = 2 * bar
    let start = startBar * bar
    let downbeat = Clock.wrap(tick: start, loopTicks: loop)
    #expect(Clock.takeTick(hit: start - 10, takeStart: start, loopTicks: loop) == downbeat)
    #expect(Clock.takeTick(hit: start - ppq / 4 + 1, takeStart: start, loopTicks: loop) == downbeat)
    #expect(Clock.takeTick(hit: start + 30, takeStart: start, loopTicks: loop) == Clock.wrap(tick: start + 30, loopTicks: loop))
    // The last beat of the take is untouched.
    #expect(Clock.takeTick(hit: start + loop - ppq, takeStart: start, loopTicks: loop) == Clock.wrap(tick: start + loop - ppq, loopTicks: loop))
}
