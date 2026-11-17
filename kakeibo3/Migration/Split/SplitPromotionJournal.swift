import Foundation

// MARK: - Cloud/Local2ストア昇格の途中経過を記録するジャーナル(Step 2B専用)
//
// 既存PromotionJournal(単一ストア用)と同じ3フェーズ設計を、Cloud/Local2ストアの
// ペアに拡張したもの。クラッシュ・電源断が2ストアどちらかの昇格の途中で起きても、
// 「Cloud/Localそれぞれが必ず旧ストアまたは新ストアのどちらかである」ことを保証する。

struct SplitPromotionJournal: Codable, Equatable {
    enum Phase: String, Codable {
        case stagingReady
        case legacyEvacuated
        case incomingPromoted
    }

    var phase: Phase
    var startedAt: Date
    var tempCloudStoreSourcePath: String
    var tempLocalStoreSourcePath: String

    static let fileName = "SplitMigrationPromotion.journal.json"

    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func load(from directory: URL) -> SplitPromotionJournal? {
        let url = url(in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SplitPromotionJournal.self, from: data)
    }

    func write(to directory: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.url(in: directory), options: .atomic)
    }

    static func delete(from directory: URL) {
        try? FileManager.default.removeItem(at: url(in: directory))
    }
}
