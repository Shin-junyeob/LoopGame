import LoopCore
import SwiftUI

/// Karaoke-style score above the loop station pads. The playhead is `AudioHost.playhead` (`HostClock.tick`, the same
/// mapping recorded hits use) evaluated every display frame, so the line and the dots it writes agree. Left of the first
/// bar line is a one-bar lead-in the playhead crosses during the count-in, with the beats 4·3·2·1 counted down.
struct LiveScore: View {
    let host: AudioHost
    let role: SongRole
    let bars: Int
    /// Unmuted song tracks: this role's are drawn faint in the rows (bold when idle), the others as ticks on the bottom strip.
    let tracks: [LoopTrack]
    // ponytail: C major like PadGrid; pass the song's key when songs get one.
    private let key = Key(root: 0, mode: .major)

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in draw(&ctx, size) }
        }
        .background(.black.opacity(0.3), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)  // the metronome counts in audibly; the record button carries the state
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let take = host.take
        let bar = Progression.ticksPerBar
        let loop = Int64(take?.bars ?? bars) * bar
        let lead = size.width * 0.16, width = size.width - lead - 6
        let raw = host.playhead(loopStart: take?.start ?? 0, loopTicks: loop) ?? 0
        // Recording: the take's window, playhead -bar/loop ..< 1. Playback: the current loop cycle, playhead = its phase.
        let start = take?.start ?? Int64(raw.rounded(.down)) * loop
        let now = take == nil ? raw - raw.rounded(.down) : raw
        func x(_ t: Int64) -> CGFloat { lead + CGFloat(t) / CGFloat(loop) * width }
        func line(_ x: CGFloat, _ w: CGFloat, _ color: Color) {
            ctx.fill(Path(CGRect(x: x - w / 2, y: 0, width: w, height: size.height)), with: .color(color))
        }

        // Rows: drum pads, or the scale notes of the role's range; low at the bottom.
        let rows = role == .drums ? Array(0..<Timbres.drumPads) : (Timbres.range[role] ?? 0...0).filter(key.contains)
        let strip: CGFloat = 10
        let rowH = (size.height - strip - 6) / CGFloat(rows.count)
        func y(_ pitch: Int) -> CGFloat {
            size.height - strip - (CGFloat(rows.firstIndex { $0 >= pitch } ?? rows.count - 1) + 0.5) * rowH
        }
        for r in rows {
            if role == .drums {
                ctx.draw(Text(drumNames[r].replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: min(rowH * 0.75, 11))).foregroundStyle(.white.opacity(0.4)),
                         at: CGPoint(x: 4, y: y(r)), anchor: .leading)
            } else if r % 12 == key.root {
                ctx.fill(Path(CGRect(x: lead, y: y(r) - rowH / 2, width: width, height: rowH)), with: .color(.white.opacity(0.06)))
            }
        }

        // Grid: bar lines strong, beats lighter, 16ths faint; the lead-in shows the count-in beats.
        for t in stride(from: 0, through: loop, by: Int(ppq / 4)) {
            let opacity = t % bar == 0 ? 0.5 : t % ppq == 0 ? 0.2 : 0.07
            line(x(t), t % bar == 0 ? 1.5 : 1, .white.opacity(opacity))
        }
        for b in 1..<4 { line(lead * CGFloat(b) / 4, 1, .white.opacity(0.1)) }

        // Notes in the window [start, start + loop): each loop repeats from tick 0 every `loopTicks`.
        func each(_ notes: [Note], every period: Int64, _ body: (Int64, Note) -> Void) {
            for n in notes {
                var rel = Clock.wrap(tick: n.tick - start, loopTicks: period)
                while rel < loop { body(rel, n); rel += period }
            }
        }
        func dot(_ t: Int64, _ pitch: Int, _ r: CGFloat, _ color: Color) {
            ctx.fill(Path(ellipseIn: CGRect(x: x(t) - r, y: y(pitch) - r, width: 2 * r, height: 2 * r)), with: .color(color))
        }
        let dotR = max(2.5, min(rowH * 0.42, 6))
        for track in tracks {
            if track.role == role {
                each(track.notes, every: track.loopTicks) { t, n in dot(t, n.pitch, dotR, role.color.opacity(take == nil ? 0.9 : 0.3)) }
            } else {
                each(track.notes, every: track.loopTicks) { t, _ in
                    ctx.fill(Path(CGRect(x: x(t) - 1, y: size.height - strip + 1, width: 2, height: strip - 3)),
                             with: .color(track.role.color.opacity(0.7)))
                }
            }
        }
        if let take {  // live hits, at their stored tick
            each(take.notes, every: loop) { t, n in dot(t, n.pitch, dotR + 1, role.color) }
        }

        // Playhead, and the count-in: beats left until the downbeat, from the same clock.
        let lead0 = -Double(bar) / Double(loop)
        if take != nil, now < 0 {
            let left = -now * Double(loop)
            if now >= lead0 {
                line(lead * CGFloat(1 - now / lead0), 3, .red)
                ctx.draw(Text("\(min(4, Int((left / Double(ppq)).rounded(.up))))")
                    .font(.system(size: size.height * 0.55, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9)), at: CGPoint(x: lead + width / 2, y: size.height / 2))
            } else {
                ctx.draw(Text("준비…").font(.title2.bold()).foregroundStyle(.white.opacity(0.8)),
                         at: CGPoint(x: lead + width / 2, y: size.height / 2))
            }
        } else {
            line(x(Int64(min(now, 1) * Double(loop))), take == nil ? 2 : 3, take == nil ? .white.opacity(0.8) : .red)
        }
    }
}
