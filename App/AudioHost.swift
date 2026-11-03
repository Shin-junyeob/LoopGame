import AVFoundation
import CAtomic
import LoopCore
import Observation

/// Everything the render block touches: raw pointers prepared on main, no Swift objects.
private struct RenderContext: @unchecked Sendable {
    let renderer: UnsafeMutablePointer<Renderer>
    /// Render-owned scratch, published to `record` every callback. Layout = `Field`.
    let stats: UnsafeMutablePointer<UInt64>
    let record: OpaquePointer
    let ticksPerFrame: Double
}

/// Indices into the per-callback record.
private enum Field {
    static let anchorHost = 0, anchorSample = 1, anchorPosition = 2, callbacks = 3
    static let renderTicks = 4, frames = 5, underruns = 6, nextSample = 7
}

/// Owns AVAudioSession/AVAudioEngine and the LoopCore renderer. Main-thread only; the render block
/// communicates through StateSwap (state), CLiveQueue (pad hits) and CRecord (anchor + timing).
// ponytail: lives for the app's lifetime, so nothing here is ever torn down.
@MainActor @Observable
final class AudioHost {
    static let tapTarget = 500

    /// Live-hit instrument: drums = pad index, pitched = note - Timbres.range[role].lowerBound.
    private(set) var role = SongRole.drums
    private(set) var timbre = "kit"
    private(set) var bpm = 120
    private(set) var metronome = false

    private(set) var sampleRate = 0.0
    private(set) var ioBufferDuration = 0.0
    private(set) var outputLatency = 0.0
    private(set) var latenciesMs: [Double] = []
    private(set) var cpuRunning = false
    private(set) var cpuStatus = "not run"
    private(set) var log: [String] = []

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private let swap = StateSwap(free: RenderState.free)
    @ObservationIgnored private let liveQueue = catomic_live_create()
    @ObservationIgnored private let record = catomic_record_create()
    @ObservationIgnored private let renderer = UnsafeMutablePointer<Renderer>.allocate(capacity: 1)
    @ObservationIgnored private let stats = UnsafeMutablePointer<UInt64>.allocate(capacity: 8)
    @ObservationIgnored private let ticksPerSecond: Double
    @ObservationIgnored private var pads: [[Float]] = []
    @ObservationIgnored private var clicks: [[Float]] = []
    @ObservationIgnored private var nextHitID: UInt64 = 0
    @ObservationIgnored private var pending: [(id: UInt64, pad: Int, touchHost: UInt64, deliveryMs: Double)] = []
    @ObservationIgnored private var hitRows: [String] = []
    @ObservationIgnored private var cpuStart: [UInt64] = []
    @ObservationIgnored private var cpuEnd = Date.distantPast

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        renderer.initialize(to: Renderer(slot: swap.slot))
        renderer.pointee.live = liveQueue
        stats.initialize(repeating: 0, count: 8)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback)
            try session.setPreferredIOBufferDuration(128 / 48_000)
            try session.setActive(true)
        } catch {
            note("session setup failed: \(error)")
        }
        let center = NotificationCenter.default
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild(reason: "engine configuration change") }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
                || reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            MainActor.assumeIsolated { self?.rebuild(reason: "route change \(reason ?? 0)") }
        }
        rebuild(reason: "start")
        Task { [weak self] in
            while let self {
                self.tick()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    // MARK: Engine

    /// New engine at the current hardware rate. Musical position is preserved (Clock.rescale) and,
    /// if the rate changed, the SampleBank is rebuilt at it and a new RenderState swapped in.
    private func rebuild(reason: String) {
        engine.stop()  // render thread is quiet from here until start()
        engine = AVAudioEngine()
        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate <= 0 { rate = AVAudioSession.sharedInstance().sampleRate }
        if rate != sampleRate {
            if sampleRate > 0 {
                renderer.pointee.position = Clock.rescale(frame: renderer.pointee.position, from: Int64(sampleRate), to: Int64(rate))
            }
            sampleRate = rate
            loadPads()
            clicks = [SampleBank.click(accent: true, rate), SampleBank.click(accent: false, rate)]
            swapState()
        }
        stats[Field.nextSample] = .max  // timeline restarts; don't count it as a glitch

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let node = Self.makeSourceNode(format: format, context: RenderContext(
            renderer: renderer, stats: stats, record: record, ticksPerFrame: ticksPerSecond / rate))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            note("engine start failed: \(error)")
        }
        let session = AVAudioSession.sharedInstance()
        ioBufferDuration = session.ioBufferDuration
        outputLatency = session.outputLatency
        note(String(format: "%@: sampleRate %.0f Hz, ioBufferDuration %.2f ms (%.0f frames), outputLatency %.2f ms, position %lld",
                    reason, rate, ioBufferDuration * 1000, ioBufferDuration * rate, outputLatency * 1000, renderer.pointee.position))
    }

    /// Built outside the main actor so the block carries no actor isolation (it runs on the audio thread).
    private nonisolated static func makeSourceNode(format: AVAudioFormat, context c: RenderContext) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList in
            let t0 = mach_absolute_time()
            let s = c.stats
            let n = Int(frameCount)
            let sampleTime = UInt64(bitPattern: Int64(timestamp.pointee.mSampleTime))
            if s[Field.nextSample] != .max && s[Field.nextSample] != sampleTime { s[Field.underruns] &+= 1 }  // timeline gap
            s[Field.anchorHost] = timestamp.pointee.mHostTime
            s[Field.anchorSample] = sampleTime
            s[Field.anchorPosition] = UInt64(bitPattern: c.renderer.pointee.position)
            let out = UnsafeMutableAudioBufferListPointer(bufferList)[0].mData!.assumingMemoryBound(to: Float.self)
            c.renderer.pointee.render(into: out, frameCount: n)
            let dt = mach_absolute_time() &- t0
            if Double(dt) > Double(n) * c.ticksPerFrame { s[Field.underruns] &+= 1 }  // missed the deadline
            s[Field.callbacks] &+= 1
            s[Field.renderTicks] &+= dt
            s[Field.frames] &+= UInt64(n)
            s[Field.nextSample] = sampleTime &+ UInt64(n)
            catomic_record_write(c.record, s)
            return noErr
        }
    }

    private func swapState() {
        let tracks = cpuRunning ? Self.eightTracks(pads)
            : metronome ? [(clicks[0], [0], 1, 0.5), (clicks[1], [ppq, 2 * ppq, 3 * ppq], 1, 0.35)] : []
        let state = RenderState(sampleRate: Int64(sampleRate), bpm: Int64(bpm), tracks: tracks, pads: pads)
        swap.swap(to: state.boxed(), engineRunning: engine.isRunning)
    }

    private func loadPads() {
        pads = SampleBank.buffers(role: role, timbre: timbre, rate: sampleRate)
        if role == .chords { pads = pads.map { $0.map { $0 * 0.5 } } }  // three notes per chord pad sum without clipping
    }

    func setInstrument(role: SongRole, timbre: String) {
        guard role != self.role || timbre != self.timbre else { return }
        self.role = role
        self.timbre = timbre
        loadPads()
        swapState()
    }

    func setTempo(bpm: Int, metronome: Bool) {
        guard bpm != self.bpm || metronome != self.metronome else { return }
        self.bpm = bpm
        self.metronome = metronome
        swapState()
    }

    private static func eightTracks(_ pads: [[Float]]) -> [(samples: [Float], events: [Int64], bars: Int64, gain: Float)] {
        let bars: [Int64] = [1, 2, 4, 8, 1, 2, 4, 8]
        return (0..<8).map { t in
            let loopTicks = bars[t] * 4 * ppq
            let step = t % 2 == 0 ? ppq : ppq / 2
            return (pads[t % pads.count], Array(stride(from: Int64(t) * 30, to: loopTicks, by: Int(step))), bars[t], 0.12)
        }
    }

    private func readRecord() -> [UInt64] {
        var v = [UInt64](repeating: 0, count: 8)
        v.withUnsafeMutableBufferPointer { catomic_record_read(record, $0.baseAddress!) }
        return v
    }

    // MARK: Live hits

    /// UITouch.timestamp is seconds on the mach_absolute_time (systemUptime) base.
    func hit(pad: Int, touchTimestamp: TimeInterval) {
        let id = nextHitID
        nextHitID += 1
        guard catomic_live_push(liveQueue, id << 8 | UInt64(pad)) else { return note("live queue full, hit dropped") }
        let touchHost = UInt64(touchTimestamp * ticksPerSecond)
        pending.append((id, pad, touchHost, Double(mach_absolute_time() &- touchHost) / ticksPerSecond * 1000))
    }

    /// Proxy latency = (output host time of the buffer the hit was voiced in) - (touch host time), where
    /// output host time = anchor mHostTime + (triggerFrame - anchorPosition) / sr + outputLatency.
    private func resolveHits() {
        guard !pending.isEmpty else { return }
        let r = readRecord()
        let anchorHost = Double(r[Field.anchorHost])
        let anchorPosition = Int64(bitPattern: r[Field.anchorPosition])
        pending.removeAll { hit in
            let frame = catomic_live_result(liveQueue, hit.id)
            if frame == Int64(CLIVE_DROPPED) { note("hit \(hit.id) dropped (voice pool full or unknown pad), not in latency stats"); return true }
            guard frame >= 0 else { return false }
            let outputHost = anchorHost + (Double(frame - anchorPosition) / sampleRate + outputLatency) * ticksPerSecond
            let ms = (outputHost - Double(hit.touchHost)) / ticksPerSecond * 1000
            latenciesMs.append(ms)
            hitRows.append(String(format: "%llu,%d,%.3f,%.3f", hit.id, hit.pad, ms, hit.deliveryMs))
            return true
        }
    }

    func resetTaps() {
        latenciesMs = []
        hitRows = []
    }

    // MARK: CPU test

    func startCPUTest() {
        cpuRunning = true
        swapState()
        cpuStart = readRecord()
        cpuEnd = Date().addingTimeInterval(60)
    }

    private func tick() {
        swap.collect()
        resolveHits()
        guard cpuRunning else { return }
        let left = cpuEnd.timeIntervalSinceNow
        guard left <= 0 else {
            cpuStatus = String(format: "running, %.0f s left", left)
            return
        }
        let r = readRecord()
        let renderSeconds = Double(r[Field.renderTicks] &- cpuStart[Field.renderTicks]) / ticksPerSecond
        let audioSeconds = Double(r[Field.frames] &- cpuStart[Field.frames]) / sampleRate
        let callbacks = r[Field.callbacks] &- cpuStart[Field.callbacks]
        cpuStatus = String(format: "avg render CPU %.2f%% of buffer time, underruns %llu, callbacks %llu, %.1f frames/callback",
                           audioSeconds > 0 ? renderSeconds / audioSeconds * 100 : 0,
                           r[Field.underruns] &- cpuStart[Field.underruns], callbacks,
                           callbacks > 0 ? Double(r[Field.frames] &- cpuStart[Field.frames]) / Double(callbacks) : 0)
        note("8-track 60 s: " + cpuStatus)
        cpuRunning = false
        swapState()
    }

    // MARK: Log

    private func note(_ line: String) {
        let stamped = "\(Date().formatted(.iso8601)) \(line)"
        print(stamped)
        log.append(stamped)
    }

    var exportText: String {
        (log + ["", "hit_id,pad,proxy_latency_ms,touch_delivery_ms"] + hitRows).joined(separator: "\n")
    }
}
