/// Auto song structure: intro (drums+bass) -> main (all tracks, repeated) -> outro (drop one track per section).
/// Every section is a whole number of the longest loop; main repeats until the whole song is >= 60 s.
public enum Arranger {
    public static let minSeconds = 60

    public static func arrange(_ song: Song) -> [Section] {
        let all = Array(song.tracks.indices)
        guard let unit = song.tracks.map(\.bars).max() else { return [] }

        var intro = all.filter { [.drums, .bass].contains(song.tracks[$0].role) }
        if intro.isEmpty { intro = Array(all.prefix(2)) }

        // Outro drops melody first, drums last (later index first within a role).
        let order = SongRole.allCases
        let dropOrder = all.sorted {
            let a = order.firstIndex(of: song.tracks[$0].role)!, b = order.firstIndex(of: song.tracks[$1].role)!
            return a != b ? a > b : $0 > $1
        }
        let ids = { (idx: [Int]) in idx.sorted().map { song.tracks[$0].id } }
        let outros = (1..<max(all.count, 1)).map { n in
            Section(kind: .outro, bars: unit, tracks: ids(Array(dropOrder.dropFirst(n))))
        }

        // seconds = bars × 240 / bpm  ->  need bars >= bpm / 4.
        let neededUnits = (song.bpm + 4 * unit - 1) / (4 * unit)
        let repeats = max(1, neededUnits - 1 - outros.count)
        return [Section(kind: .intro, bars: unit, tracks: ids(intro)),
                Section(kind: .main, bars: unit * repeats, tracks: ids(all))] + outros
    }

    public static func totalTicks(_ sections: [Section]) -> Int64 {
        sections.reduce(0) { $0 + Int64($1.bars) * Progression.ticksPerBar }
    }

    public static func totalFrames(_ sections: [Section], sampleRate: Int64, bpm: Int) -> Int64 {
        Clock.frame(tick: totalTicks(sections), sampleRate: sampleRate, bpm: Int64(bpm))
    }
}
