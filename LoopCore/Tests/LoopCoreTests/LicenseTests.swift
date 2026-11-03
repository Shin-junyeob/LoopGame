import Foundation
import Testing

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private struct LicenseEntry: Decodable {
    let path: String
    let license: String
    let attribution: String?
}

/// Every corpus/resource/bundled-sample file needs a licenses.json entry with an allowed license (plan §3 principle 5).
@Test func everyDataFileIsLicensed() throws {
    let entries = try JSONDecoder().decode(
        [LicenseEntry].self, from: Data(contentsOf: repoRoot.appendingPathComponent("licenses.json")))
    let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    #expect(byPath.count == entries.count, "duplicate paths in licenses.json")

    for e in entries {
        #expect(["CC0", "CC-BY-4.0", "self"].contains(e.license), "\(e.path): license \(e.license) not allowed")
        if e.license == "CC-BY-4.0" { #expect(!(e.attribution ?? "").isEmpty, "\(e.path): CC-BY needs attribution") }
        #expect(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(e.path).path), "\(e.path): stale entry")
    }

    var walked = 0
    for dir in ["data/corpus", "LoopCore/Sources/LoopCore/Resources", "App/Resources/Samples"] {
        let base = repoRoot.appendingPathComponent(dir)
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in files where url.lastPathComponent != ".DS_Store" {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(repoRoot.standardizedFileURL.path.count + 1))
            #expect(byPath[rel] != nil, "\(rel) has no licenses.json entry")
            walked += 1
        }
    }
    #expect(walked >= 27)
}
