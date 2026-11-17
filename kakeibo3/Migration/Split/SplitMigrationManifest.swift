import Foundation

// MARK: - Cloud/Local分割移行の結果記録(Step 2B)
//
// B1/B2のMigrationManifestと同じ「JSON永続化 + UserDefaultsフラグ + ストアUUID一致確認」の
// 3点検証パターンを踏襲するが、対象が「単一の本番ストア」から「Cloud/Local 2ストア」に
// 変わるため、フィールドを独立した新しい型として定義する(既存MigrationManifestはB1/B2の
// 「13直接移行+4再生成」という別の意味を持つため、意味を変えずに使い回さない)。

struct SplitMigrationBookSummary: Codable, Equatable {
    var bookId: UUID
    var cloudEntityCounts: [String: Int]
    var localEntityCounts: [String: Int]
    var expenseTotal: Int
    var incomeTotal: Int
    var transferTotal: Int
}

enum SplitMigrationState: String, Codable {
    /// 一時Cloud/Localストアへの書き込み・検証まで成功(本番昇格はまだ)
    case tempStoreVerified
    /// 本番Cloud/Localストアへの昇格・旧ストア退避まで完全に完了
    case promoted
}

struct SplitMigrationManifest: Codable, Equatable {
    static let currentVersion = 1

    var migrationVersion: Int
    var completedAt: Date

    /// 移行元(旧Kakeibo3.sqlite、分割前の単一ストア)の識別情報
    var sourceStoreIdentifier: String?
    var sourceStoreFileSize: Int64
    var sourceStoreModifiedAt: Date

    /// Cloud対象13 Entityの、旧ストア側での件数(移行元の実測値)
    var cloudEntityCounts: [String: Int]
    /// Local対象4 Entityの、旧ストア側での件数(移行元の実測値)
    var localEntityCounts: [String: Int]

    var sourceBookIDs: [UUID]
    var bookSummaries: [SplitMigrationBookSummary]

    /// 昇格完了後、本番Cloud/LocalストアそれぞれのNSStoreUUIDKey
    var cloudStoreIdentifier: String?
    var localStoreIdentifier: String?

    /// entityName毎の内容チェックサム(例: "cloud.ExpenseData" -> SHA256相当のhex文字列)。
    /// UUID集合+主要な金額フィールドから決定的に計算し、コピー・書き込み・再オープンの
    /// 各段階で再計算して一致を確認する(件数一致だけでは検出できない入れ替わり等の検知用)。
    var checksums: [String: String]

    /// 致命的ではないが記録しておくべき警告(例: Local派生データの一部が再生成対象として
    /// スキップされた等)。空配列なら警告無し。
    var migrationWarnings: [String]

    var migrationState: SplitMigrationState
}
