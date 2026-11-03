import SwiftUI

/// Lists every CC-BY item of the bundled licenses.json (AC4), plus a thank-you to VCSL (CC0).
struct CreditsView: View {
    private struct Item: Decodable, Hashable {
        let path: String
        let license: String
        let attribution: String
    }

    private let ccBy: [Item] = {
        let url = Bundle.main.url(forResource: "licenses", withExtension: "json")!
        let items = try! JSONDecoder().decode([Item].self, from: Data(contentsOf: url))  // bundled file: a bad one is a build error
        return items.filter { $0.license.hasPrefix("CC-BY") }
    }()

    var body: some View {
        List {
            Section("CC BY 저작자 표시") {
                ForEach(ccBy, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.attribution)
                        Text("\(item.license) · \(item.path)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("악기 소리") {
                Text("Versilian Community Sample Library (Versilian Studios LLC), CC0 1.0 — 피아노, 일렉 피아노, 드럼 킷 샘플. 감사합니다!")
            }
        }
        .scrollContentBackground(.hidden)
        .background(stage)
        .navigationTitle("크레딧")
    }
}
