import LoopCore
import SwiftUI

@main
struct LoopGameApp: App {
    @State private var host = AudioHost()

    var body: some Scene {
        WindowGroup {
            HomeView(host: host).preferredColorScheme(.dark)
        }
    }
}

enum Screen: String, Hashable {
    case newSong, mySongs, freePlay, settings, credits, spike
}

/// Dark stage background shared by every screen.
let stage = Color(red: 0.06, green: 0.06, blue: 0.09)

struct HomeView: View {
    let host: AudioHost
    /// `-screen freePlay` (launch argument) opens a screen directly, for simulator screenshots.
    @State private var path = UserDefaults.standard.string(forKey: "screen").flatMap(Screen.init).map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                Text("루프 게임")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("박자에 맞춰 치고, 겹쳐 쌓아 한 곡을 만들어요")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                homeButton("새 곡 만들기", "plus.circle.fill", SongRole.drums.color, .newSong)
                homeButton("내 곡", "music.note.list", SongRole.bass.color, .mySongs)
                homeButton("자유 연주", "hand.tap.fill", SongRole.chords.color, .freePlay)
                Label("스테이지 (곧)", systemImage: "flag.checkered")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
                    .foregroundStyle(.white.opacity(0.45))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("아직 준비 중이에요")
                Spacer()
                HStack {
                    NavigationLink("설정", value: Screen.settings)
                    Spacer()
                    NavigationLink("크레딧", value: Screen.credits)
                    #if DEBUG
                    Spacer()
                    NavigationLink("측정 도구", value: Screen.spike)
                    #endif
                }
                .font(.body.weight(.semibold))
                .tint(.white.opacity(0.85))
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(stage)
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .freePlay: FreePlayView(host: host)
                case .settings: SettingsView()
                case .credits: CreditsView()
                case .newSong, .mySongs:
                    ContentUnavailableView("준비 중이에요", systemImage: "hammer.fill",
                                           description: Text("루프 스테이션이 곧 여기에 들어와요"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(stage)
                case .spike:
                    #if DEBUG
                    SpikeView(host: host)
                    #else
                    EmptyView()
                    #endif
                }
            }
        }
    }

    private func homeButton(_ title: String, _ icon: String, _ color: Color, _ screen: Screen) -> some View {
        NavigationLink(value: screen) {
            Label(title, systemImage: icon)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(color.gradient, in: .rect(cornerRadius: 18))
                .foregroundStyle(.white)
        }
    }
}

struct SettingsView: View {
    @AppStorage("keyboardMode") private var keyboardMode = false

    var body: some View {
        Form {
            Section {
                Toggle("건반으로 연주하기", isOn: $keyboardMode)
            } footer: {
                Text("켜면 베이스·코드·멜로디를 12음 건반으로 쳐요. 끄면 지금 키의 음만 있는 패드로 쳐요.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(stage)
        .navigationTitle("설정")
    }
}
