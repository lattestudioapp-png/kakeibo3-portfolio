import Foundation

// MARK: - 支出データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDExpenseData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`ExpenseDataSync`が変換を担当する）。
struct ExpenseData: Identifiable, Hashable {
    var id: UUID
    var amount: Int
    var date: Date
    var paymentMethod: String
    var category: String
    var memo: String
    var createdAt: Date
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil
    // 紐づく BankAccountData の UUID（nil = 銀行口座以外の支払い方法）
    var bankAccountId: UUID? = nil
    // 固定費から自動生成された場合の固定費ID（nil = 手動入力）
    var fixedExpenseId: UUID? = nil
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
        paymentMethod: String,
        category: String,
        memo: String,
        bankAccountId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.paymentMethod = paymentMethod
        self.category = category
        self.memo = memo
        self.createdAt = createdAt
        self.bankAccountId = bankAccountId
    }
}
