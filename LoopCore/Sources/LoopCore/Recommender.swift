/// Track roles of a song, in recommendation order.
public enum SongRole: String, Codable, CaseIterable, Sendable {
    case drums, bass, chords, melody
}

/// Fixed-order baseline recommender: drums -> bass -> chords -> melody.
///
/// Model-based recommender is blocked until the user provides >= 40 self-made songs;
/// per G6 v1 ships this baseline.
public enum Recommender {
    /// `trackCounts`: number of tracks per role already in the song (missing key = 0).
    /// Returns the first role with no tracks; if all present, the role with the fewest tracks (tie -> order).
    public static func next(trackCounts: [SongRole: Int]) -> SongRole {
        if let missing = SongRole.allCases.first(where: { (trackCounts[$0] ?? 0) == 0 }) { return missing }
        return SongRole.allCases.min { (trackCounts[$0] ?? 0) < (trackCounts[$1] ?? 0) }!
    }

    /// Convenience: roles present (one track each).
    public static func next(present: Set<SongRole>) -> SongRole {
        next(trackCounts: Dictionary(uniqueKeysWithValues: present.map { ($0, 1) }))
    }
}
