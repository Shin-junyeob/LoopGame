import SwiftUI

@main
struct LoopGameApp: App {
    @State private var host = AudioHost()

    var body: some Scene {
        WindowGroup {
            SpikeView(host: host)
        }
    }
}

/// S1 spike measurement screen: live-hit proxy latency, 8-track CPU, audio config, log export.
struct SpikeView: View {
    let host: AudioHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "sampleRate %.0f Hz · ioBuffer %.2f ms · outputLatency %.2f ms",
                            host.sampleRate, host.ioBufferDuration * 1000, host.outputLatency * 1000))
                    .font(.footnote.monospaced())

                LazyVGrid(columns: [GridItem(), GridItem()]) {
                    ForEach(0..<SampleBank.names.count, id: \.self) { pad in
                        TouchPadView(title: SampleBank.names[pad]) { host.hit(pad: pad, touchTimestamp: $0) }
                            .frame(height: 110)
                    }
                }

                GroupBox("\(AudioHost.tapTarget)-tap latency test (\(host.latenciesMs.count)/\(AudioHost.tapTarget))") {
                    Text(latencySummary).font(.body.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Reset taps", action: host.resetTaps)
                }

                GroupBox("8-track CPU test (60 s)") {
                    Text(host.cpuStatus).font(.body.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Start", action: host.startCPUTest).disabled(host.cpuRunning)
                }

                ShareLink("Export log", item: host.exportText)
            }
            .padding()
        }
    }

    private var latencySummary: String {
        let sorted = host.latenciesMs.sorted()
        guard let max = sorted.last else { return "tap the pads" }
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        return String(format: "P50 %.2f ms  P95 %.2f ms  max %.2f ms", pct(0.5), pct(0.95), max)
    }
}
