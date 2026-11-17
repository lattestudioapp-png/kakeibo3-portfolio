import Foundation

// MARK: - 受け取り方法データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDReceiveMethodData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`ReceiveMethodDataSync`が変換を担当する）。
// 現在はPaymentMethodSettingData(useForReceive=true)へ統合済みで、生きている呼び出し
// 箇所は「新規帳簿作成時の現金デフォルト作成」「バックアップ復元」「帳簿リセット」のみ。
struct ReceiveMethodData: Identifiable, Hashable {
    var id: UUID
    var methodName: String
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil

    init(
        id: UUID = UUID(),
        methodName: String,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.methodName = methodName
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
