import LoopCore
import SwiftUI

/// Saved songs (AC18): Application Support/Songs, one JSON file per song id.
let songStore = SongStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Songs"))

/// US-305 "내 곡": name, modified date and length; tap to keep editing, swipe to rename or delete.
struct MySongsView: View {
    let host: AudioHost
    @State private var songs: [Song] = []
    @State private var renaming: Song?
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(songs, id: \.id) { song in
                NavigationLink {
                    LoopStationView(host: host, song: song)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.name).font(.headline)
                        Text("\(song.modifiedAt.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "ko_KR")))) · \(length(song)) · 트랙 \(song.tracks.count)개")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions {
                    Button("삭제", role: .destructive) { delete(song) }
                    Button("이름 바꾸기") { newName = song.name; renaming = song }.tint(.indigo)
                }
                .contextMenu {
                    Button("이름 바꾸기", systemImage: "pencil") { newName = song.name; renaming = song }
                    Button("삭제", systemImage: "trash", role: .destructive) { delete(song) }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView("아직 저장된 곡이 없어요", systemImage: "music.note.list",
                                       description: Text("새 곡을 만들면 자동으로 여기에 저장돼요"))
            }
        }
        .background(stage)
        .navigationTitle("내 곡")
        .onAppear { songs = songStore.loadAll() }
        .alert("이름 바꾸기", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
            TextField("곡 이름", text: $newName)
            Button("취소", role: .cancel) {}
            Button("저장") {
                guard var song = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                song.name = newName
                song.modifiedAt = .now
                try? songStore.save(song)
                songs = songStore.loadAll()
            }
        }
    }

    /// Arrangement length (the saved one, else what the Arranger would make).
    private func length(_ song: Song) -> String {
        let sections = song.sections.isEmpty ? Arranger.arrange(song) : song.sections
        let s = Int(Double(Arranger.totalTicks(sections)) / Double(ppq) * 60 / Double(song.bpm))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func delete(_ song: Song) {
        try? songStore.delete(id: song.id)
        songs.removeAll { $0.id == song.id }
    }
}
