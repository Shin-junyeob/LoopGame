import LoopCore
import SwiftUI

/// US-303 loop station: record loops over a 1-bar count-in and stack up to 8 of them in a Song (AC5, AC6, AC12).
/// US-305: every change is saved to `songStore`; "곡 완성하기" opens the arrangement.
struct LoopStationView: View {
    let host: AudioHost
    @State private var song: Song
    @State private var muted: Set<UUID> = []
    @State private var role = SongRole.drums
    @State private var timbres = Timbres.ids.mapValues { $0[0] }
    @State private var bars = 2
    @State private var compare: Compare?
    @State private var arranging = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(host: AudioHost, song: Song? = nil) {
        self.host = host
        _song = State(initialValue: song ?? Self.initialSong)
    }

    private var recording: Bool { host.take != nil }
    private var full: Bool { song.tracks.count >= Song.maxTracks }

    var body: some View {
        VStack(spacing: 12) {
            controls.disabled(recording)
            trackList
            recordButton
            LiveScore(host: host, role: role, bars: bars, tracks: song.tracks.filter { !muted.contains($0.id) })
                .frame(height: sizeClass == .regular ? 200 : 96)
            PadGrid(host: host, role: role).frame(maxHeight: .infinity)
        }
        .padding()
        .background(stage)
        .navigationTitle("루프 스테이션")
        .toolbar {
            Button("곡 완성하기") { arranging = true }
                .disabled(song.tracks.isEmpty || recording)
        }
        .navigationDestination(isPresented: $arranging) { ArrangeView(host: host, song: $song) }
        .onAppear {
            apply()
            play()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demoCompare") { startCompare(Self.demoTake) }
            if UserDefaults.standard.bool(forKey: "demoArrange") { arranging = true }
            #endif
        }
        .onChange(of: role, apply)
        .onChange(of: timbres, apply)
        .onChange(of: song.bpm) {
            song.sections = []  // the Arranger's length depends on tempo; re-arrange on the next visit
            apply()
        }
        .onChange(of: song.tracks) {
            song.sections = []
            play()
        }
        .onChange(of: song, save)
        .onChange(of: muted, play)
        .onChange(of: host.finishedTake) { _, take in
            guard let take, !full else { return }
            startCompare(take)
        }
        .sheet(item: $compare, onDismiss: play) { c in
            CompareSheet(compare: c, host: host, song: song.tracks.filter { !muted.contains($0.id) }) { kept in
                song.tracks.append(kept)
                role = next
                compare = nil
            }
        }
        .onDisappear {
            host.cancelRecording()
            host.setSongTracks([])
        }
    }

    private func apply() {
        host.setInstrument(role: role, timbre: timbres[role]!)
        host.setTempo(bpm: song.bpm, metronome: false)
    }

    private func play() {
        host.setSongTracks(song.tracks.filter { !muted.contains($0.id) })
    }

    /// AC18 auto-save, once the song has a track. Naming it re-triggers this through `onChange(of: song)`.
    private func save() {
        guard !song.tracks.isEmpty else { return }
        guard !song.name.isEmpty else {
            song.name = "곡 " + Date.now.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR")))
            return
        }
        var s = song
        s.modifiedAt = .now
        do { try songStore.save(s) } catch { print("song save failed: \(error)") }
    }

    /// AC10: the sheet runs the Corrector off main and shows the take (auditioning) with a progress row meanwhile.
    private func startCompare(_ take: LoopTrack) {
        compare = Compare(take: take, key: song.key, progression: song.progression)
    }

    private var next: SongRole {
        Recommender.next(trackCounts: Dictionary(grouping: song.tracks, by: \.role).mapValues(\.count))
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let instrument = chips(SongRole.allCases, selection: $role, label: \.title, color: { $0.color })
        let sound = chips(Timbres.ids[role]!, selection: Binding { timbres[role]! } set: { timbres[role] = $0 },
                          label: { timbreNames[$0] ?? $0 }, color: { _ in role.color })
        let length = chips([1, 2, 4, 8], selection: $bars, label: { "\($0)마디" }, color: { _ in role.color })
        let tempo = Stepper(value: $song.bpm, in: Song.bpmRange, step: 5) {
            Text("빠르기 \(song.bpm)").font(.headline).monospacedDigit()
        }
        .accessibilityValue("BPM \(song.bpm)")
        if sizeClass == .regular {
            Grid(horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow { instrument; sound }
                GridRow { length; tempo }
            }
        } else {
            VStack(spacing: 10) { instrument; sound; length; tempo }
        }
    }

    // MARK: Tracks

    @ViewBuilder private var trackList: some View {
        if song.tracks.isEmpty {
            Text("아직 트랙이 없어요. 녹음해서 첫 루프를 쌓아보세요")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 56)
        } else {
            ScrollView(.horizontal) {  // track cards only; pads stay outside any ScrollView (S1)
                HStack(spacing: 8) {
                    ForEach(song.tracks, id: \.id) { trackCard($0) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func trackCard(_ track: LoopTrack) -> some View {
        let off = muted.contains(track.id)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.role.title).font(.headline)
                Text("\(timbreNames[track.timbre] ?? track.timbre) · \(track.bars)마디").font(.caption)
            }
            .accessibilityElement(children: .combine)
            Button {
                if off { muted.remove(track.id) } else { muted.insert(track.id) }
            } label: {
                Image(systemName: off ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 36, height: 44)
            }
            .accessibilityLabel(off ? "소리 켜기" : "음소거")
            Button {
                song.removeTrack(id: track.id)
                muted.remove(track.id)
            } label: {
                Image(systemName: "trash").frame(width: 36, height: 44)
            }
            .accessibilityLabel("트랙 삭제")
            .disabled(recording)
        }
        .padding(.leading, 12)
        .foregroundStyle(.white.opacity(off ? 0.5 : 1))
        .background(track.role.color.opacity(off ? 0.2 : 0.55), in: .rect(cornerRadius: 12))
    }

    // MARK: Record

    private var recordButton: some View {
        VStack(spacing: 6) {
            if !full {
                Text("\(song.tracks.isEmpty ? "먼저" : "다음엔") \(["드럼을", "베이스를", "코드를", "멜로디를"][SongRole.allCases.firstIndex(of: next)!]) 쌓아보세요")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(next.color)
            }
            Button {
                if recording { host.cancelRecording() } else { host.startRecording(bars: bars) }
            } label: {
                Label(recordTitle, systemImage: recording ? "stop.circle.fill" : "record.circle")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(recording ? Color.red : role.color, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .disabled(full)
            .opacity(full ? 0.4 : 1)
            .accessibilityHint(recording ? "탭하면 녹음을 취소해요" : "한 마디 카운트 뒤에 녹음해요")
            #if DEBUG
            if let t = host.finishedTake {  // timing report: mean signed onset offset of the last raw take, + = late
                let ms = { (ticks: Double) in ticks * 60_000 / (Double(host.bpm) * Double(ppq)) }
                Text(String(format: "DEBUG 마지막 녹음 평균 어긋남: 16분 %+.0f ms · 박 %+.0f ms (%d음)",
                            ms(Metrics.meanGridOffset(t.notes)), ms(Metrics.meanGridOffset(t.notes, grid: ppq)), t.notes.count))
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            #endif
        }
    }

    /// Count-in and progress are on the score (audio clock), not here.
    private var recordTitle: String {
        if recording { return "녹음 중 · 탭하면 취소" }
        return full ? "트랙이 가득 찼어요 (8개)" : "녹음 · \(role.title) \(bars)마디"
    }

    // MARK: Screenshot seed

    /// `-demoSong YES` (DEBUG launch argument) starts with a drum and a bass loop, for simulator screenshots.
    private static var initialSong: Song {
        var song = Song(bpm: 100)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoSong") {
            let drums = [0, 2].map { Note(tick: $0 * ppq, pitch: 0) } + [1, 3].map { Note(tick: $0 * ppq, pitch: 1) }
                + (0..<8).map { Note(tick: $0 * ppq / 2, pitch: 2) }
            let bass = [36, 43, 45, 41].enumerated().flatMap { bar, pitch in
                (0..<4).map { Note(tick: Int64(bar) * Progression.ticksPerBar + $0 * ppq, pitch: pitch) }
            }
            song.tracks = [LoopTrack(role: .drums, timbre: "kit", bars: 1, notes: drums.sorted { $0.tick < $1.tick }),
                           LoopTrack(role: .bass, timbre: "bass", bars: 4, notes: bass)]
        }
        #endif
        return song
    }

    #if DEBUG
    /// `-demoCompare YES`: a jittered 2-bar melody take (off-grid, a few notes outside C major) opens the compare sheet.
    private static var demoTake: LoopTrack {
        let pitches = [60, 63, 67, 64, 61, 67, 71, 68, 64, 69, 73, 70, 65, 70, 72, 66]
        let jitter: [Int64] = [35, -60, 70, -40, 55, -65, 30, 60, -50, 40, -70, 50, 65, -45, 60, -30]
        return LoopTrack(role: .melody, timbre: "piano", bars: 2, notes: pitches.indices.map {
            Note(tick: max(0, Int64($0) * ppq / 2 + jitter[$0]), pitch: pitches[$0])
        })
    }
    #endif
}
