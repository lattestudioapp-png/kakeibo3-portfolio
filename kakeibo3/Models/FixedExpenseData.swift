import Foundation

// MARK: - 固定費データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDFixedExpenseData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`FixedExpenseDataSync`が変換を担当する）。
struct FixedExpenseData: Identifiable, Hashable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryName: String
    var paymentMethodType: String  // "bankAccount" | "paymentMethod" | ""
    var paymentMethodId: UUID?
    var dayOfMonth: Int            // 1-31
    var startDate: Date
    var memo: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool = false
    // 無料版の上限超過によりロックされているか（データは保持したまま利用制限する）
    var isLocked: Bool = false
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil
    // 支払い日が金融機関の休業日と重なった場合の調整方法（WeekendHolidayAdjustment.rawValue）。
    // 支払い方法が銀行口座の場合のみ編集画面に表示・適用する。
    var holidayAdjustment: String = WeekendHolidayAdjustment.shiftLater.rawValue
    // 生成済みスケジュール月（"yyyy-M"）。休日調整で実際の反映日が前後の月にずれても、
    // ExpenseData.dateから逆算せずここで「本来の予定月」を追跡することで、
    // RecurringEntryGeneratorが同じ月を二重生成しないようにする。
    var generatedScheduleMonths: [String] = []

    init(
        id: UUID = UUID(),
        name: String,
        amount: Int,
        categoryName: String = "",
        paymentMethodType: String = "",
        paymentMethodId: UUID? = nil,
        dayOfMonth: Int = 1,
        startDate: Date = Date(),
        memo: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryName = categoryName
        self.paymentMethodType = paymentMethodType
        self.paymentMethodId = paymentMethodId
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.memo = memo
        self.isActive = true
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
