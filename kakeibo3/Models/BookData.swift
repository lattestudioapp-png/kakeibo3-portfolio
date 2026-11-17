import Foundation

// MARK: - 帳簿データ

/**
 複数帳簿（個人用/事業用/旅行用など）を表すドメインモデル（Core Data移行 Phase 1）。
 「ほぼ別アプリ」として、収入・支出・振替・カテゴリー・支払い方法・受け取り方法・
 銀行口座・予算・固定費・定期収入・定期振替・各種スナップショットがすべてこのIDで完全分離される。

 永続化はCore Data（`CDBookData`）が担い、このstructは画面・ロジック層が触る
 フレームワーク非依存のドメイン表現（`BookDataSync`がCDBookDataとの変換を担当する）。
 */
struct BookData: Identifiable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int
    var isArchived: Bool
    // メイン帳簿判定用。名前変更されても固定費/定期収入/定期振替の自動生成先を見失わないため、
    // 名前ではなくこのフラグで判定する（BookResolver.mainBook参照）
    var isMain: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sortOrder: Int,
        isArchived: Bool = false,
        isMain: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.isMain = isMain
    }
}
