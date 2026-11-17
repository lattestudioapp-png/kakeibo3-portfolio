import Foundation

// MARK: - 移行結果の記録(この段階では一時的なもの。本番昇格はPhase B2で行う)
//
// targetStoreIdentifierはPhase B2で本番ストアのNSStoreUUIDKeyを入れる想定のため、
// この段階ではnilのまま(まだ本番ストアが存在しない)。

struct MigrationBookSummary: Codable, Equatable {
    var bookId: UUID
    var entityCounts: [String: Int]
    var expenseTotal: Int
    var incomeTotal: Int
    var transferTotal: Int
}

struct MigrationManifest: Codable, Equatable {
    static let currentVersion = 1

    var migrationVersion: Int
    var completedAt: Date
    var sourceStoreFileSize: Int64
    var sourceStoreModifiedAt: Date
    var sourceBookIDs: [UUID]
    /// 直接移行した13 Entityの件数
    var entityCounts: [String: Int]
    /// 移行しなかった4モデル(再生成対象)の、旧ストア側での件数(参考情報のみ)
    var regeneratedModelSourceCounts: [String: Int]
    var bookSummaries: [MigrationBookSummary]
    /// 本番ストアのNSStoreUUIDKey。Phase B2で昇格が完了してから設定する
    var targetStoreIdentifier: String?
}
