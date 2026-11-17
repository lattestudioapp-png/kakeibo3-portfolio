import Foundation

struct BudgetData: Identifiable, Hashable {
    var id: UUID
    var year: Int
    var month: Int
    var categoryName: String
    var amount: Int
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool = false
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil

    init(
        id: UUID = UUID(),
        year: Int,
        month: Int,
        categoryName: String,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.year = year
        self.month = month
        self.categoryName = categoryName
        self.amount = amount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
