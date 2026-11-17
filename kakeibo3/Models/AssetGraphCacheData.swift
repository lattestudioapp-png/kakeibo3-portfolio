import Foundation

// MARK: - 資産推移グラフキャッシュ1点（日付 + その時点の総資産額）

struct AssetGraphCachePoint: Codable, Hashable {
    var date: Date
    var value: Int
}

// MARK: - 資産推移グラフキャッシュ
//
// 分析 > 資産 の資産推移グラフは、開くたびに元データから再計算すると
// 10年/20年分のデータで重くなるため、「更新」ボタンを押した時だけ計算し、
// この結果を保存しておいて普段はそれを表示する。
// ExpenseData/IncomeData/TransferDataの保存・編集・削除、支払い方法/口座の設定変更では
// 自動更新しない（SnapshotManager/AnalysisSnapshotManagerとは異なる方針）。

struct AssetGraphCacheData: Hashable {
    /// 帳簿ごとに1行（"totalAssets_<bookId>"）。複数帳簿対応により単一行では足りなくなったため、
    /// bookIdを含む複合キーにしている（cacheId(for:)参照）。
    var id: String
    var bookId: UUID?
    var updatedAt: Date
    var maxPointsUsed: Int
    /// "daily" | "weekly" | "monthly" | "yearly"
    var granularityUsed: String
    var firstDate: Date
    var lastDate: Date
    var points: [AssetGraphCachePoint]

    static func cacheId(for bookId: UUID) -> String {
        "totalAssets_\(bookId.uuidString)"
    }

    init(
        bookId: UUID,
        updatedAt: Date = Date(),
        maxPointsUsed: Int,
        granularityUsed: String,
        firstDate: Date,
        lastDate: Date,
        points: [AssetGraphCachePoint]
    ) {
        self.id = AssetGraphCacheData.cacheId(for: bookId)
        self.bookId = bookId
        self.updatedAt = updatedAt
        self.maxPointsUsed = maxPointsUsed
        self.granularityUsed = granularityUsed
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.points = points
    }
}
