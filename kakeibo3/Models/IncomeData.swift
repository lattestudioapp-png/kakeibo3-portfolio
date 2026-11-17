import Foundation

// MARK: - 収入データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDIncomeData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`IncomeDataSync`が変換を担当する）。
struct IncomeData: Identifiable, Hashable {
    var id: UUID
    var amount: Int
    var date: Date
    var receiveMethod: String
    var category: String
    var memo: String
    var createdAt: Date
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil
    // 紐づく BankAccountData の UUID（nil = 銀行口座以外の受け取り方法）
    var bankAccountId: UUID? = nil
    // 定期収入から自動生成された場合の定期収入ID（nil = 手動入力）
    var recurringIncomeId: UUID? = nil
    // 添付写真のファイル名（Documents/receipts/ 以下に保存）
    var receiptImagePath: String? = nil
    var isTestData: Bool = false
    // ゴミ箱（ソフトデリート）。trueの間は通常画面・集計から除外され、30日後に完全削除される
    var isInTrash: Bool = false
    var trashedAt: Date? = nil

    init(
        id: UUID = UUID(),
        amount: Int,
        date: Date,
        receiveMethod: String,
        category: String,
        memo: String,
        bankAccountId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.receiveMethod = receiveMethod
        self.category = category
        self.memo = memo
        self.createdAt = createdAt
        self.bankAccountId = bankAccountId
    }
}
