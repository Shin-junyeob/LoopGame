import Foundation
import Testing
@testable import LoopCore

@Test func sampleMappingPicksNearestRootAndRatio() {
    let roots = [48, 55, 60, 67]
    #expect(Timbres.sample(for: 60, roots: roots) == (60, 1))
    let up = Timbres.sample(for: 62, roots: roots)
    #expect(up.root == 60 && abs(up.ratio - pow(2, 2.0 / 12)) < 1e-12)
    let down = Timbres.sample(for: 65, roots: roots)
    #expect(down.root == 67 && abs(down.ratio - pow(2, -2.0 / 12)) < 1e-12)
    #expect(Timbres.sample(for: 50, roots: [48, 52]).root == 48)  // tie -> lower root
    #expect(Timbres.sample(for: 30, roots: roots) == (48, pow(2, -18.0 / 12)))
}

/// Bundled multisamples (App/Resources/Samples/keys/<timbre>/<root>.caf) cover every note of every role
/// that uses them within 3 semitones, and every timbre a stage uses exists for its role.
@Test func bundledRootsCoverRolesAndStagesUseKnownTimbres() throws {
    let keys = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Samples/keys")
    for timbre in ["piano", "epiano"] {
        let roots = try FileManager.default.contentsOfDirectory(atPath: keys.appendingPathComponent(timbre).path)
            .compactMap { Int($0.replacingOccurrences(of: ".caf", with: "")) }
        #expect(roots.count >= 4)
        for role in [SongRole.chords, .melody] where Timbres.ids[role]!.contains(timbre) {
            for note in Timbres.range[role]! {
                #expect(abs(note - Timbres.sample(for: note, roots: roots).root) <= 3, "\(timbre) \(note)")
            }
        }
    }
    for stage in try Stage.loadAll() {
        for t in stage.song.tracks { #expect(Timbres.ids[t.role]!.contains(t.timbre), "\(stage.name): \(t.timbre)") }
    }
}
