import LoopCore
import SwiftUI

/// US-302 free play (G8): pads by default, 12-note keyboard for pitched roles when Settings says so.
struct FreePlayView: View {
    let host: AudioHost
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// `-role melody` (launch argument) preselects an instrument, for simulator screenshots.
    @State private var role = UserDefaults.standard.string(forKey: "role").flatMap(SongRole.init) ?? .drums
    @State private var timbres = Timbres.ids.mapValues { $0[0] }
    @State private var bpm = 120
    @State private var metronome = false

    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        VStack(spacing: 16) {
            controls
            PadGrid(host: host, role: role).frame(maxHeight: .infinity)
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
}
