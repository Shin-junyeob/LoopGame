import AVFoundation
import Foundation
import Testing
@testable import LoopCore

private func arrangedSong() -> Song {
    var s = Song(bpm: 110, tracks: [
        LoopTrack(role: .drums, bars: 1, notes: [Note(tick: 0, pitch: 0), Note(tick: 960, pitch: 1)]),
        LoopTrack(role: .bass, bars: 2, notes: [Note(tick: 0, pitch: 36), Note(tick: 2000, pitch: 43)]),
        LoopTrack(role: .melody, bars: 4, notes: [Note(tick: 100, pitch: 72)]),
    ])
    s.sections = Arranger.arrange(s)
    return s
}

/// Impulse per event; gain picks the track, so the rendered buffer shows which track sounded where.
private func specs(_ tracks: [LoopTrack]) -> [(sounds: [[Float]], events: [Int64], eventSounds: [Int], bars: Int64, gain: Float)] {
    tracks.enumerated().map { i, t in
        ([[1]], t.notes.map(\.tick).sorted(), [Int](repeating: 0, count: t.notes.count), Int64(t.bars), Float(1 << i))
    }
}

@Test func flattenPlaysEachTrackOnlyInItsSections() throws {
    var s = arrangedSong()
    let melody = s.tracks[2].id
    s.setTrack(melody, on: false, inSection: 1)  // main without melody
    let flat = Arranger.flatten(s)
    let total = s.sections.map(\.bars).reduce(0, +)
    #expect(flat.allSatisfy { $0.bars == total })

    var start: Int64 = 0
    for section in s.sections {
        let end = start + Int64(section.bars) * Progression.ticksPerBar
        for (i, t) in s.tracks.enumerated() {
            let inSection = flat[i].notes.filter { $0.tick >= start && $0.tick < end }
            #expect(inSection.count == (section.tracks.contains(t.id) ? t.notes.count * section.bars / t.bars : 0))
        }
        start = end
    }
}

@Test func renderStartsAtOriginTick() {
    let origin: Int64 = 3 * ppq
    let swap = StateSwap(free: RenderState.free)
    swap.swap(to: RenderState(sampleRate: 48_000, bpm: 120, songTracks: [([[1]], [0], [0], 1, 1)], originTick: origin).boxed(),
              engineRunning: false)
    var renderer = Renderer(slot: swap.slot)
    defer { renderer.deallocate() }
    let n = 48_000 * 4
    var out = [Float](repeating: 0, count: n)
    out.withUnsafeMutableBufferPointer { renderer.render(into: $0.baseAddress!, frameCount: n) }
    let hits = out.indices.filter { out[$0] != 0 }
    let first = Int(Clock.frame(tick: origin, sampleRate: 48_000, bpm: 120))
    #expect(hits == [first, first + 96_000])  // nothing before the origin, then one per 2 s bar
}

@Test func exportLengthMatchesArrangementFrames() throws {
    let s = arrangedSong()
    let rate: Int64 = 44_100
    let frames = Arranger.totalFrames(s.sections, sampleRate: rate, bpm: s.bpm)
    let samples = Exporter.render(sampleRate: rate, bpm: Int64(s.bpm), songTracks: specs(Arranger.flatten(s)), frameCount: Int(frames))
    #expect(Int64(samples.count) == frames)
    #expect(samples[0] == 1 + 2)  // intro: drums + bass at tick 0

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    for ext in ["m4a", "wav"] {
        let url = dir.appendingPathComponent("song.\(ext)")
        try Exporter.write(samples, sampleRate: Double(rate), to: url)
        let length = try AVAudioFile(forReading: url).length
        #expect(abs(length - frames) <= (ext == "m4a" ? 2112 : 0), "\(ext): \(length) vs \(frames)")
    }
}
