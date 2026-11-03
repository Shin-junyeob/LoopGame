import Foundation

/// Songs as JSON files, one per id (`<id>.json`) in `directory`, written atomically.
public struct SongStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    public func save(_ song: Song) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(song).write(to: url(song.id), options: .atomic)
    }

    /// Newest first. Files that don't decode (corrupt, newer schema) stay on disk but aren't listed.
    public func loadAll() -> [Song] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Song.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(id))
    }
}
