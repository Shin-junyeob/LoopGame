import LoopCore
import SwiftUI
import UIKit

extension SongRole {
    var title: String { ["드럼", "베이스", "코드", "멜로디"][SongRole.allCases.firstIndex(of: self)!] }
    var uiColor: UIColor {
        switch self {
        case .drums: UIColor(red: 0.93, green: 0.36, blue: 0.20, alpha: 1)
        case .bass: UIColor(red: 0.17, green: 0.38, blue: 0.85, alpha: 1)
        case .chords: UIColor(red: 0.16, green: 0.66, blue: 0.42, alpha: 1)
        case .melody: UIColor(red: 0.95, green: 0.36, blue: 0.62, alpha: 1)
        }
    }
    var color: Color { Color(uiColor: uiColor) }
}

private let timbreNames = ["kit": "어쿠스틱", "electronic": "전자", "bass": "플럭", "synth": "신스",
                           "piano": "피아노", "epiano": "일렉 피아노", "bell": "벨", "square": "8비트"]
private let drumNames = ["킥", "스네어", "닫힌\n하이햇", "열린\n하이햇", "탐", "크래시"]
private let solfege = ["도", "도♯", "레", "레♯", "미", "파", "파♯", "솔", "솔♯", "라", "라♯", "시"]
private let letters = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

private func noteName(_ midi: Int) -> (solfege: String, letter: String) {
    (solfege[midi % 12], "\(letters[midi % 12])\(midi / 12 - 1)")
}

/// One pad: `notes` are live-hit pad indices sent together (three for a chord).
private struct Pad: Identifiable {
    let id: Int
    let title: String
    var accessibility: String? = nil
    let color: UIColor
    let notes: [Int]
}

/// US-302 free play (G8): pads by default, 12-note keyboard for pitched roles when Settings says so.
struct FreePlayView: View {
    let host: AudioHost
    @AppStorage("keyboardMode") private var keyboardMode = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// `-role melody` (launch argument) preselects an instrument, for simulator screenshots.
    @State private var role = UserDefaults.standard.string(forKey: "role").flatMap(SongRole.init) ?? .drums
    @State private var timbres = Timbres.ids.mapValues { $0[0] }
    @State private var bpm = 120
    @State private var metronome = false
    // ponytail: free play has no song yet, so it plays in the Song defaults (C major, C-G-Am-F).
    private let key = Key(root: 0, mode: .major)
    private let progression = Progression.cGAmF

    private var wide: Bool { sizeClass == .regular }
    private var range: ClosedRange<Int> { Timbres.range[role] ?? 0...0 }

    var body: some View {
        VStack(spacing: 16) {
            controls
            pads.frame(maxHeight: .infinity)
        }
        .padding()
        .background(stage)
        .navigationTitle("자유 연주")
        .toolbar {
            NavigationLink(value: Screen.settings) { Image(systemName: "gearshape.fill") }
                .accessibilityLabel("설정")
        }
        .onAppear(perform: apply)
        .onChange(of: role, apply)
        .onChange(of: timbres, apply)
        .onChange(of: bpm, apply)
        .onChange(of: metronome, apply)
        .onDisappear { host.setTempo(bpm: bpm, metronome: false) }
    }

    private func apply() {
        host.setInstrument(role: role, timbre: timbres[role]!)
        host.setTempo(bpm: bpm, metronome: metronome)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let instrument = chips(SongRole.allCases, selection: $role, label: \.title, color: { $0.color })
        let sound = chips(Timbres.ids[role]!, selection: Binding { timbres[role]! } set: { timbres[role] = $0 },
                          label: { timbreNames[$0] ?? $0 }, color: { _ in role.color })
        let tempo = HStack {
            Stepper(value: $bpm, in: Song.bpmRange, step: 5) {
                Text("빠르기 \(bpm)").font(.headline).monospacedDigit()
            }
            .accessibilityValue("BPM \(bpm)")
            Toggle(isOn: $metronome) { Label("메트로놈", systemImage: "metronome.fill").font(.headline) }
                .fixedSize()
                .tint(role.color)
        }
        if wide {
            Grid(horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow { instrument; sound }
                GridRow { tempo.gridCellColumns(2) }
            }
        } else {
            VStack(spacing: 12) { instrument; sound; tempo }
        }
    }

    private func chips<T: Hashable>(_ options: [T], selection: Binding<T>, label: @escaping (T) -> String,
                                    color: @escaping (T) -> Color) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = selection.wrappedValue == option
                Button { selection.wrappedValue = option } label: {
                    Text(label(option))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? color(option) : .white.opacity(0.08), in: .rect(cornerRadius: 12))
                        .foregroundStyle(on ? .white : .white.opacity(0.8))
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: Pads

    @ViewBuilder private var pads: some View {
        switch role {
        case .drums:
            grid((0..<Timbres.drumPads).map { i in
                Pad(id: i, title: drumNames[i], color: UIColor(hue: 0.0 + 0.022 * CGFloat(i), saturation: 0.78,
                                                               brightness: 0.88, alpha: 1), notes: [i])
            }, columns: wide ? 3 : 2)
        case _ where keyboardMode:
            keyboard
        case .chords:
            grid(chordPads, columns: wide ? 3 : 2)
        default:
            let notes = range.filter(key.contains)
            let columns = wide ? 7 : 4
            // Rows low -> high from the bottom, like a pitch ladder; left -> right within a row.
            let rows = stride(from: 0, to: notes.count, by: columns).map { Array(notes[$0..<min($0 + columns, notes.count)]) }
            grid(rows.reversed().flatMap { $0 }.map { n in
                let name = noteName(n)
                let tonic = n % 12 == key.root
                return Pad(id: n, title: "\(name.solfege)\n\(name.letter)", accessibility: "\(name.solfege), \(name.letter)",
                           color: role.uiColor.withAlphaComponent(tonic ? 1 : 0.78), notes: [n - range.lowerBound])
            }, columns: columns, rowSizes: rows.reversed().map(\.count))
        }
    }

    /// Diatonic triads of the key (vii° omitted: Chord is major/minor only); progression chords are bright and numbered.
    private var chordPads: [Pad] {
        let shape: [(Int, Chord.Quality)] = key.mode == .major
            ? [(0, .major), (2, .minor), (4, .minor), (5, .major), (7, .major), (9, .minor)]
            : [(0, .minor), (3, .major), (5, .minor), (7, .minor), (8, .major), (10, .major)]
        return shape.enumerated().map { i, s in
            let chord = Chord(root: (key.root + s.0) % 12, quality: s.1)
            let name = letters[chord.root] + (chord.quality == .minor ? "m" : "")
            let step = progression.chords.firstIndex(of: chord).map { "\($0 + 1) · " } ?? ""
            return Pad(id: i, title: "\(step)\(name)\n\(chord.voicing.map { solfege[$0 % 12] }.joined(separator: " "))",
                       accessibility: "\(name) 코드" + (step.isEmpty ? "" : ", 진행 \(step.prefix(1))번"),
                       color: role.uiColor.withAlphaComponent(step.isEmpty ? 0.5 : 1),
                       notes: chord.voicing.map { $0 - range.lowerBound })
        }
    }

    /// Rows of pads filling the space; no ScrollView (delaysContentTouches, S1).
    private func grid(_ pads: [Pad], columns: Int, rowSizes: [Int]? = nil) -> some View {
        let sizes = rowSizes ?? stride(from: 0, to: pads.count, by: columns).map { min(columns, pads.count - $0) }
        let starts = sizes.indices.map { sizes[..<$0].reduce(0, +) }
        return VStack(spacing: 10) {
            ForEach(sizes.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(pads[starts[r]..<starts[r] + sizes[r]]) { pad($0) }
                    ForEach(sizes[r]..<columns, id: \.self) { _ in Color.clear }
                }
            }
        }
    }

    private func pad(_ p: Pad, text: UIColor = .white, flash: UIColor = .white, bottom: Bool = false) -> some View {
        TouchPadView(title: p.title, color: p.color, textColor: text, flashColor: flash, accessibilityName: p.accessibility,
                     labelAtBottom: bottom) { t in
            for n in p.notes { host.hit(pad: n, touchTimestamp: t) }
        }
    }

    // MARK: Keyboard (12 notes per octave, G8)

    private var keyboard: some View {
        let octaves = Set(range.map { $0 / 12 }).sorted(by: >)
        return VStack(spacing: 12) {
            ForEach(octaves, id: \.self) { octave in
                GeometryReader { geo in
                    let gap: CGFloat = 4
                    let w = (geo.size.width - 6 * gap) / 7
                    let bw = w * 0.62
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: gap) {
                            ForEach([0, 2, 4, 5, 7, 9, 11], id: \.self) { key(octave * 12 + $0, black: false) }
                        }
                        ForEach([(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)], id: \.0) { offset, after in
                            key(octave * 12 + offset, black: true)
                                .frame(width: bw, height: geo.size.height * 0.58)
                                .offset(x: CGFloat(after + 1) * (w + gap) - gap / 2 - bw / 2)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func key(_ n: Int, black: Bool) -> some View {
        if range.contains(n) {
            let name = noteName(n)
            pad(Pad(id: n, title: black ? "" : "\(name.solfege)\n\(name.letter)", accessibility: "\(name.solfege), \(name.letter)",
                    color: black ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.94, alpha: 1), notes: [n - range.lowerBound]),
                text: .black, flash: role.uiColor, bottom: true)
        } else {
            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(black ? 0 : 0.06))
                .accessibilityHidden(true)
        }
    }
}
