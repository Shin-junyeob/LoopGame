import LoopCore
import SwiftUI

/// A finished take waiting for the user's pick; `options` is nil while the Corrector runs.
struct Compare: Identifiable {
    var take: LoopTrack
    var options: [Corrector.Candidate]?
    var id: UUID { take.id }
}

/// US-304 compare sheet (AC10, AC11): the take as played + up to 2 Metrics-passing AI versions, each auditioned
/// looping with the song. Only `Corrector.suggest` output reaches here, so nothing unfiltered is ever shown.
struct CompareSheet: View {
    let compare: Compare
    let host: AudioHost
    /// Unmuted song tracks the selected version plays along with.
    let song: [LoopTrack]
    let keep: (LoopTrack) -> Void
    @State private var selected = 0

    private var versions: [(title: String, detail: String, track: LoopTrack)] {
        var out = [("내 연주", "녹음한 그대로", compare.take)]
        var options = compare.options ?? []
        // Options come best-F1 first; two that differ by at most one note aren't worth comparing.
        if options.count == 2 && Self.differ(options[0].notes, options[1].notes) <= 1 { options.removeLast() }
        for c in options {
            var t = compare.take
            t.notes = c.notes.sorted { $0.tick < $1.tick }
            var title = c.strength == .weak ? "살짝 고침" : "많이 고침"
            if out.contains(where: { $0.0 == "AI 보정 · " + title }) { title += " 2" }
            out.append(("AI 보정 · " + title, changes(t.notes), t))
        }
        return out
    }

    /// Notes in one version but not the other (by tick and pitch), the larger side.
    private static func differ(_ a: [Note], _ b: [Note]) -> Int {
        let key = { (n: Note) in [n.tick, Int64(n.pitch)] }
        let sa = Set(a.map(key)), sb = Set(b.map(key))
        return max(sa.subtracting(sb).count, sb.subtracting(sa).count)
    }

    /// What the AI changed vs the take: each output note is compared with the take note nearest in time.
    private func changes(_ notes: [Note]) -> String {
        let take = compare.take.notes
        var pitch = 0, moved = 0
        for n in notes {
            guard let m = take.min(by: { abs($0.tick - n.tick) < abs($1.tick - n.tick) }) else { continue }
            if m.pitch != n.pitch { pitch += 1 }
            if m.tick != n.tick { moved += 1 }
        }
        var parts = ["바뀐 음 \(pitch)개", "박자 맞춤 \(moved)개"]
        if take.count > notes.count { parts.append("뺀 음 \(take.count - notes.count)개") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let versions = versions
        let role = compare.take.role
        VStack(spacing: 14) {
            Text("어떤 걸로 쌓을까요?").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
            Text("고르면 그 버전이 곡과 함께 반복 재생돼요").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(versions.indices, id: \.self) { i in
                        row(i, versions[i].title, versions[i].detail, versions[i].track)
                    }
                    if compare.options == nil {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("AI가 고쳐 보는 중…")
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    } else if compare.options?.isEmpty == true {
                        Text("이번엔 보정안이 없어요")
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Button {
                keep(versions[min(selected, versions.count - 1)].track)
            } label: {
                Text("이걸로 쌓기").font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(role.color, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .background(stage)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .onAppear(perform: audition)
        .onChange(of: selected, audition)
    }

    private func audition() {
        let v = versions
        host.setSongTracks(song + [v[min(selected, v.count - 1)].track])
    }

    private func row(_ i: Int, _ title: String, _ detail: String, _ track: LoopTrack) -> some View {
        let on = i == selected
        return Button {
            selected = i
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(detail).font(.caption).foregroundStyle(.white.opacity(0.7))
                    if on { Image(systemName: "speaker.wave.2.fill").accessibilityLabel("듣는 중") }
                }
                roll(track).frame(height: 64)
            }
            .padding(12)
            .foregroundStyle(.white)
            .background(.white.opacity(on ? 0.14 : 0.05), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? track.role.color : .clear, lineWidth: 2))
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Mini piano roll: this version's notes as dots over the take's notes as rings, on a 16th grid.
    private func roll(_ track: LoopTrack) -> some View {
        let all = versions.flatMap(\.track.notes).map(\.pitch)
        let lo = (all.min() ?? 0) - 1, hi = (all.max() ?? 0) + 1
        let span = Double(track.loopTicks)
        let color = track.role.color
        return Canvas { ctx, size in
            func point(_ n: Note) -> CGPoint {
                CGPoint(x: 4 + Double(n.tick) / span * (size.width - 8),
                        y: size.height * (1 - Double(n.pitch - lo) / Double(max(hi - lo, 1))))
            }
            for beat in stride(from: 0, to: track.loopTicks, by: Int(ppq)) {
                let x = 4 + Double(beat) / span * (size.width - 8)
                let bar = beat % Progression.ticksPerBar == 0
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(bar ? 0.25 : 0.08)))
            }
            for n in compare.take.notes {
                let p = point(n)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.35)))
            }
            for n in track.notes {
                let p = point(n)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
