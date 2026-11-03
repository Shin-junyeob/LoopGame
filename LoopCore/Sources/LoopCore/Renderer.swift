import CAtomic

public struct Track {
    public let samples: UnsafeMutableBufferPointer<Float>
    public let events: UnsafeMutableBufferPointer<Int64>  // ticks within the loop, sorted
    public let loopTicks: Int64
    public let gain: Float
}

/// Immutable snapshot read by the render thread. Built (and freed) on main only.
public struct RenderState {
    public static let maxTracks = 8
    public let sampleRate: Int64
    public let bpm: Int64
    public let tracks: UnsafeMutableBufferPointer<Track>

    public init(sampleRate: Int64, bpm: Int64, tracks specs: [(samples: [Float], events: [Int64], bars: Int64, gain: Float)]) {
        precondition(specs.count <= Self.maxTracks)
        self.sampleRate = sampleRate
        self.bpm = bpm
        tracks = .allocate(capacity: specs.count)
        for (i, spec) in specs.enumerated() {
            precondition([1, 2, 4, 8].contains(spec.bars))
            let loopTicks = spec.bars * 4 * ppq
            precondition(spec.events == spec.events.sorted() && spec.events.allSatisfy { $0 >= 0 && $0 < loopTicks })
            let samples = UnsafeMutableBufferPointer<Float>.allocate(capacity: spec.samples.count)
            _ = samples.initialize(from: spec.samples)
            let events = UnsafeMutableBufferPointer<Int64>.allocate(capacity: spec.events.count)
            _ = events.initialize(from: spec.events)
            tracks.initializeElement(at: i, to: Track(samples: samples, events: events, loopTicks: loopTicks, gain: spec.gain))
        }
    }

    public func deallocate() {
        for t in tracks {
            t.samples.deallocate()
            t.events.deallocate()
        }
        tracks.deallocate()
    }

    /// Heap copy for StateSwap; pair with `free`.
    public func boxed() -> UnsafeMutableRawPointer {
        let p = UnsafeMutablePointer<RenderState>.allocate(capacity: 1)
        p.initialize(to: self)
        return UnsafeMutableRawPointer(p)
    }

    public static func free(_ raw: UnsafeMutableRawPointer) {
        let p = raw.assumingMemoryBound(to: RenderState.self)
        p.pointee.deallocate()
        p.deallocate()
    }
}

struct Voice {
    var start: Int64 = 0
    var end: Int64 = .min
    var samples: UnsafePointer<Float>? = nil
    var gain: Float = 0
}

struct Cursor {
    var loop: Int64 = 0
    var index = 0
    var next: Int64 = .max
}

/// Render-thread object. Everything is preallocated in init; `render` does no allocation, locking,
/// ARC or dynamic dispatch. Per-frame sums run in voice-slot order and slots are assigned at the
/// trigger frame only, so output is independent of how the timeline is split into buffers.
public struct Renderer {
    public static let voiceCount = 64
    public var position: Int64 = 0
    private let slot: OpaquePointer
    private let voices: UnsafeMutableBufferPointer<Voice>
    private let cursors: UnsafeMutableBufferPointer<Cursor>
    private var lastState: UnsafeMutableRawPointer?

    public init(slot: OpaquePointer) {
        self.slot = slot
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice())
        cursors = .allocate(capacity: RenderState.maxTracks)
        cursors.initialize(repeating: Cursor())
    }

    public func deallocate() {
        voices.deallocate()
        cursors.deallocate()
    }

    public mutating func render(into out: UnsafeMutablePointer<Float>, frameCount: Int) {
        out.update(repeating: 0, count: frameCount)
        let base = position
        let end = base + Int64(frameCount)
        defer {
            position = end
            catomic_epoch_increment(slot)
        }
        guard let raw = catomic_load(slot) else { return }
        let state = raw.assumingMemoryBound(to: RenderState.self).pointee
        if raw != lastState {
            lastState = raw
            seek(state)
        }
        var a = base
        while a < end {
            var b = end
            for t in 0..<state.tracks.count {
                while cursors[t].next == a {
                    trigger(state.tracks[t], at: a)
                    advance(t, state)
                }
                b = min(b, cursors[t].next)
            }
            for i in 0..<Self.voiceCount {
                let v = voices[i]
                let hi = min(b, v.end)
                guard hi > a, let p = v.samples else { continue }
                for f in a..<hi {
                    out[Int(f - base)] += p[Int(f - v.start)] * v.gain
                }
            }
            a = b
        }
    }

    // ponytail: a state swap cuts all voices (old sample memory may be reclaimed); add per-voice
    // sample ownership if edits must not click.
    private func seek(_ state: RenderState) {
        for i in 0..<Self.voiceCount { voices[i] = Voice() }
        let tickNow = Clock.floorDiv(position * state.bpm * ppq, state.sampleRate * 60)
        for t in 0..<state.tracks.count {
            let track = state.tracks[t]
            cursors[t] = Cursor(loop: tickNow / track.loopTicks)
            guard track.events.count > 0 else { continue }
            cursors[t].next = Clock.frame(tick: cursors[t].loop * track.loopTicks + track.events[0], sampleRate: state.sampleRate, bpm: state.bpm)
            while cursors[t].next < position { advance(t, state) }
        }
    }

    private func advance(_ t: Int, _ state: RenderState) {
        let track = state.tracks[t]
        cursors[t].index += 1
        if cursors[t].index == track.events.count {
            cursors[t].index = 0
            cursors[t].loop += 1
        }
        let tick = cursors[t].loop * track.loopTicks + track.events[cursors[t].index]
        cursors[t].next = Clock.frame(tick: tick, sampleRate: state.sampleRate, bpm: state.bpm)
    }

    // ponytail: full pool drops the new note; add voice stealing if 64 ever overflows.
    private func trigger(_ track: Track, at frame: Int64) {
        guard track.samples.count > 0, let p = track.samples.baseAddress else { return }
        for i in 0..<Self.voiceCount where voices[i].end <= frame {
            voices[i] = Voice(start: frame, end: frame + Int64(track.samples.count), samples: UnsafePointer(p), gain: track.gain)
            return
        }
    }
}

/// Linear-interpolation resample (main thread, at sample load). Length = floor(count * to / from).
public func resampleLinear(_ x: [Float], from oldRate: Int, to newRate: Int) -> [Float] {
    let n = x.count * newRate / oldRate
    guard let last = x.indices.last else { return [] }
    return (0..<n).map { i in
        let pos = Double(i) * Double(oldRate) / Double(newRate)
        let i0 = min(Int(pos), last)
        let frac = Float(pos - Double(i0))
        return x[i0] * (1 - frac) + x[min(i0 + 1, last)] * frac
    }
}
