import Foundation

// MARK: - 本番ストア昇格の途中経過を記録するジャーナル
//
// クラッシュ・電源断・強制終了が昇格の途中で起きても「旧ストアまたは新ストアの
// どちらかが必ず残る」ことを保証するための仕組み。本番パスを一切触る前に
// ジャーナルを書き込み、各フェーズが完了するたびに更新する。次回起動時
// (実際にはPhase B3でKakeibo3Appに接続してから)、ジャーナルが残っていれば
// 「前回の昇格が中断された」と分かり、記録されたフェーズから復旧・巻き戻しを行う。
//
// フェーズの意味:
//   .stagingReady      : .incoming一式(検証済み一時ストアのコピー)を本番ディレクトリに
//                        置いただけ。本番パス(sqlite/wal/shm)はまだ一切触れていない。
//                        このフェーズでの中断は「何もしていない」のと同じで安全。
//   .legacyEvacuated   : 既存の本番ファイル(あれば)を.pre-migration-backupへ退避した。
//                        本番パスは一時的に空。.incoming一式はまだ残っている。
//                        このフェーズでの中断は「.incomingを本番名へ昇格し直す」だけで復旧できる。
//   .incomingPromoted  : .incomingを本番名へrenameし、新ストアが本番パスに存在する状態。
//                        最終検証(Manifest突合)だけが残っている。

struct PromotionJournal: Codable, Equatable {
    enum Phase: String, Codable {
        case stagingReady
        case legacyEvacuated
        case incomingPromoted
    }

    var phase: Phase
    var startedAt: Date
    var tempStoreSourcePath: String

    static let fileName = "MigrationPromotion.journal.json"

    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func load(from directory: URL) -> PromotionJournal? {
        let url = url(in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PromotionJournal.self, from: data)
    }

    func write(to directory: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.url(in: directory), options: .atomic)
    }

    static func delete(from directory: URL) {
        try? FileManager.default.removeItem(at: url(in: directory))
    }
}
