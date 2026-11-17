import Foundation

struct RecurringBudgetData: Identifiable, Hashable {
    var id: UUID
    var categoryName: String
    var amount: Int
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil

    init(
        id: UUID = UUID(),
        categoryName: String,
        amount: Int,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryName = categoryName
        self.amount = amount
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
