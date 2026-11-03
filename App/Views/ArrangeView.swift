import LoopCore
import SwiftUI

/// US-305 arrange screen (AC8, AC9, AC19): the Arranger's intro / main / outro as a timeline, per-section track
/// chips, playback from the intro, and m4a + wav export.
struct ArrangeView: View {
    let host: AudioHost
    @Binding var song: Song
    @State private var playing = false
    @State private var exported: [URL]?
    @State private var exporting = false
    @State private var exportError: String?

    private var seconds: Double { Double(Arranger.totalTicks(song.sections)) / Double(ppq) * 60 / Double(song.bpm) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("총 \(Self.time(seconds))").font(.title2.bold()).monospacedDigit()
                Spacer()
                Button {
                    playing.toggle()
                    host.setArrangement(playing ? song : nil, restart: true)
                } label: {
                    Label(playing ? "멈추기" : "처음부터 듣기", systemImage: playing ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(.white.opacity(0.14), in: .capsule)
                }
                .foregroundStyle(.white)
            }
            timeline
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(song.sections.indices, id: \.self, content: sectionRow)
                }
            }
            exportBar
        }
        .padding()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(stage)
        .navigationTitle("곡 완성하기")
        .onAppear {
            if song.sections.isEmpty { song.sections = Arranger.arrange(song) }
            host.setSongTracks([])
        }
        .onChange(of: song.sections) {
            exported = nil
            if playing { host.setArrangement(song, restart: false) }
        }
        .onDisappear { host.setArrangement(nil, restart: false) }
        .alert("내보내지 못했어요", isPresented: Binding { exportError != nil } set: { _ in exportError = nil }) {
        } message: {
            Text(exportError ?? "")
        }
    }

    private static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    private func title(_ i: Int) -> String {
        let kind = song.sections[i].kind
        let name = ["intro": "인트로", "main": "본론", "outro": "아웃트로"][kind.rawValue]!
        let same = song.sections.indices.filter { song.sections[$0].kind == kind }
        return same.count > 1 ? "\(name) \(same.firstIndex(of: i)! + 1)" : name
    }

    private func color(_ section: LoopCore.Section) -> Color {
        [.intro: SongRole.drums.color, .main: SongRole.chords.color, .outro: SongRole.bass.color][section.kind]!
    }

    /// Section widths proportional to their bars.
    private var timeline: some View {
        GeometryReader { geo in
            let total = max(song.sections.map(\.bars).reduce(0, +), 1)
            HStack(spacing: 2) {
                ForEach(song.sections.indices, id: \.self) { i in
                    let s = song.sections[i]
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color(s).opacity(0.3 + 0.7 * Double(s.tracks.count) / Double(max(song.tracks.count, 1))))
                        .frame(width: max(geo.size.width * Double(s.bars) / Double(total) - 2, 4))
                }
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private func sectionRow(_ i: Int) -> some View {
        let section = song.sections[i]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(i)).font(.headline)
                Spacer()
                Text("\(section.bars)마디 · \(Self.time(Double(section.bars) * 240 / Double(song.bpm)))")
                    .font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(song.tracks, id: \.id) { track in chip(track, section: i) }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private func chip(_ track: LoopTrack, section i: Int) -> some View {
        let on = song.sections[i].tracks.contains(track.id)
        return Button {
            song.setTrack(track.id, on: !on, inSection: i)
        } label: {
            Text("\(track.role.title) · \(timbreNames[track.timbre] ?? track.timbre)")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(track.role.color.opacity(on ? 0.75 : 0.12), in: .capsule)
                .overlay(Capsule().stroke(track.role.color.opacity(on ? 0 : 0.6), lineWidth: 1))
                .foregroundStyle(.white.opacity(on ? 1 : 0.55))
        }
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("\(title(i))에서 켜고 끄기")
    }

    @ViewBuilder private var exportBar: some View {
        if let exported {
            ShareLink(items: exported) {
                Label("공유하기 (m4a · wav)", systemImage: "square.and.arrow.up")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(SongRole.chords.color, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        } else {
            Button {
                exporting = true
                Task {
                    do { exported = try await host.export(song) } catch { exportError = error.localizedDescription }
                    exporting = false
                }
            } label: {
                HStack(spacing: 10) {
                    if exporting { ProgressView().tint(.white) }
                    Text(exporting ? "만드는 중…" : "오디오로 내보내기")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(SongRole.drums.color, in: .rect(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(exporting)
        }
    }
}
