import Foundation
import SwiftData

// MARK: - 旧SwiftDataストアを開くためだけの@Modelクラス群(Migration層専用)
//
// 通常のView・Repository・Serviceから参照している同名の型(BookData/ExpenseData等、
// 現在はCore Data時代のプレーンなdomain struct)と衝突しないよう、すべて Legacy 接頭辞で
// 定義する。フィールドは旧アプリのSwiftDataモデルと完全に1:1(型・オプショナリティ・
// デフォルト値まで含めて同一)にする必要がある。SwiftDataはディスク上のスキーマと
// ModelContainerに渡すSchemaが一致しないとストアを開けないため。
//
// import SwiftData はこのファイルと同じ Migration/Legacy 配下のみに限定する。

@Model
final class LegacyBookData {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date? = nil
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var isMain: Bool = false

    init() {}
}

@Model
final class LegacyCategoryData {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = ""
    var type: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date? = nil
    var isTestData: Bool = false
    var bookId: UUID? = nil
    var isSuspended: Bool = false
    var isProtected: Bool = false

    init() {}
}

@Model
final class LegacyExpenseData {
    @Attribute(.unique) var id: UUID = UUID()
    var amount: Int = 0
    var date: Date = Date()
    var paymentMethod: String = ""
    var category: String = ""
    var memo: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date? = nil
    var bookId: UUID? = nil
    var bankAccountId: UUID? = nil
    var fixedExpenseId: UUID? = nil
    var receiptImagePath: String? = nil
    var isTestData: Bool = false
    var isInTrash: Bool = false
    var trashedAt: Date? = nil

    init() {}
}

@Model
final class LegacyIncomeData {
    @Attribute(.unique) var id: UUID = UUID()
    var amount: Int = 0
    var date: Date = Date()
    var receiveMethod: String = ""
    var category: String = ""
    var memo: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date? = nil
    var bookId: UUID? = nil
    var bankAccountId: UUID? = nil
    var recurringIncomeId: UUID? = nil
    var receiptImagePath: String? = nil
    var isTestData: Bool = false
    var isInTrash: Bool = false
    var trashedAt: Date? = nil

    init() {}
}

@Model
final class LegacyTransferData {
    @Attribute(.unique) var id: UUID = UUID()
    var date: Date = Date()
    var fromType: String = ""
    var fromId: UUID? = nil
    var fromName: String = ""
    var toType: String = ""
    var toId: UUID? = nil
    var toName: String = ""
    var amount: Int = 0
    var feeAmount: Int = 0
    var memo: String = ""
    var receiptImagePath: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isTestData: Bool = false
    var recurringTransferSettingId: UUID? = nil
    var bookId: UUID? = nil
    var isInTrash: Bool = false
    var trashedAt: Date? = nil

    init() {}
}

@Model
final class LegacyBankAccountData {
    @Attribute(.unique) var id: UUID = UUID()
    var accountName: String = ""
    var initialBalance: Double? = nil
    var memo: String? = nil
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var initialBalanceIncomeId: UUID? = nil
    var showAsPaymentMethod: Bool = true
    var showAsReceiveMethod: Bool = true
    var showInAnalysis: Bool = true
    var isAsset: Bool = true
    var recurringTransferSettingId: UUID? = nil
    var recurringTransferSettingIds: [UUID] = []
    var isTestData: Bool = false
    var isLocked: Bool = false
    var bookId: UUID? = nil
    var colorHex: String? = nil

    init() {}
}

@Model
final class LegacyReceiveMethodData {
    var id: UUID = UUID()
    var methodName: String = ""
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date? = nil
    var bookId: UUID? = nil

    init() {}
}

@Model
final class LegacyPaymentMethodSettingData {
    var id: UUID = UUID()
    var methodName: String = ""
    var type: String = ""
    var closingDay: Int? = nil
    var withdrawalDay: Int? = nil
    var adjustPaymentDateToNextBusinessDay: Bool = true
    var holidayAdjustment: String? = nil
    var bankAccount: String? = nil
    var withdrawalBankAccountId: UUID? = nil
    var memo: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var isActive: Bool = true
    var isAsset: Bool = false
    var assetInitialBalance: Double? = nil
    var includeInAnalysis: Bool = true
    var assetInitialBalanceIncomeId: UUID? = nil
    var assetInitialBalanceExpenseId: UUID? = nil
    var showInInputPicker: Bool = true
    var useForReceive: Bool = false
    var showInAnalysis: Bool = true
    var recurringTransferSettingId: UUID? = nil
    var recurringTransferSettingIds: [UUID] = []
    var isTestData: Bool = false
    var isLocked: Bool = false
    var bookId: UUID? = nil
    var colorHex: String? = nil

    init() {}
}

@Model
final class LegacyBudgetData {
    var id: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var categoryName: String = ""
    var amount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isTestData: Bool = false
    var bookId: UUID? = nil

    init() {}
}

@Model
final class LegacyRecurringBudgetData {
    var id: UUID = UUID()
    var categoryName: String = ""
    var amount: Int = 0
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var bookId: UUID? = nil

    init() {}
}

@Model
final class LegacyFixedExpenseData {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Int = 0
    var categoryName: String = ""
    var paymentMethodType: String = ""
    var paymentMethodId: UUID? = nil
    var dayOfMonth: Int = 1
    var startDate: Date = Date()
    var memo: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isTestData: Bool = false
    var isLocked: Bool = false
    var bookId: UUID? = nil
    var holidayAdjustment: String = WeekendHolidayAdjustment.shiftLater.rawValue
    var generatedScheduleMonths: [String] = []

    init() {}
}

@Model
final class LegacyRecurringIncomeData {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Int = 0
    var categoryName: String = ""
    var receiveMethodType: String = ""
    var receiveMethodId: UUID? = nil
    var dayOfMonth: Int = 1
    var startDate: Date = Date()
    var memo: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isTestData: Bool = false
    var isLocked: Bool = false
    var bookId: UUID? = nil
    var holidayAdjustment: String = WeekendHolidayAdjustment.shiftLater.rawValue
    var generatedScheduleMonths: [String] = []

    init() {}
}

@Model
final class LegacyRecurringTransferSettingData {
    @Attribute(.unique) var id: UUID = UUID()
    var fromMethodId: UUID = UUID()
    var fromMethodName: String = ""
    var fromType: String = TransferAccountType.paymentMethod.rawValue
    var toMethodId: UUID = UUID()
    var toMethodName: String = ""
    var toType: String = TransferAccountType.paymentMethod.rawValue
    var amount: Int = 0
    var day: Int = 1
    var startDate: Date = Date()
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isLocked: Bool = false
    var isTestData: Bool = false
    var bookId: UUID? = nil
    var holidayAdjustment: String = WeekendHolidayAdjustment.shiftLater.rawValue
    var generatedScheduleMonths: [String] = []

    init() {}
}

// MARK: - 再生成する派生データ(4モデル)。データそのものは移行しないが、
// 旧ストアのスキーマ全体を過不足なく開くためにはこれらの@Modelも必要
// (ModelContainerに渡すSchemaがディスク上のスキーマと一致しないと開けないため)。

struct LegacyAnalysisCategoryAmount: Codable, Equatable {
    var categoryId: UUID?
    var categoryName: String
    var amount: Int
    var percentage: Double
}

struct LegacyAnalysisMethodAmount: Codable, Equatable {
    var methodId: UUID?
    var methodName: String
    var amount: Int
    var percentage: Double
}

struct LegacyAssetGraphCachePoint: Codable, Equatable {
    var date: Date
    var value: Int
}

@Model
final class LegacyDailySnapshot {
    var date: Date = Date()
    var bookId: UUID? = nil
    var incomeTotal: Int = 0
    var expenseTotal: Int = 0
    var creditCardExpenseTotal: Int = 0
    var transferFeeTotal: Int = 0
    var transactionCount: Int = 0
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class LegacyMonthlySnapshot {
    var yearMonth: String = ""
    var bookId: UUID? = nil
    var year: Int = 0
    var month: Int = 0
    var incomeTotal: Int = 0
    var expenseTotal: Int = 0
    var creditCardExpenseTotal: Int = 0
    var transferFeeTotal: Int = 0
    var carryoverBalance: Int = 0
    var rawCarryoverBalance: Int = 0
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class LegacyAnalysisMonthlySnapshot {
    var yearMonth: String = ""
    var bookId: UUID? = nil
    var year: Int = 0
    var month: Int = 0
    var incomeTotal: Int = 0
    var expenseTotal: Int = 0
    var creditCardExpenseTotal: Int = 0
    var transferFeeTotal: Int = 0
    var carryoverBalance: Int = 0
    var updatedAt: Date = Date()
    var displayExpenseTotal: Int = 0
    var displayIncomeTotal: Int = 0
    var expenseCategoryTotals: [LegacyAnalysisCategoryAmount] = []
    var incomeCategoryTotals: [LegacyAnalysisCategoryAmount] = []
    var paymentMethodTotals: [LegacyAnalysisMethodAmount] = []
    var receiveMethodTotals: [LegacyAnalysisMethodAmount] = []
    var expenseTransactionCount: Int = 0
    var incomeTransactionCount: Int = 0
    var dailyExpenseTotals: [Int] = []
    var dailyIncomeTotals: [Int] = []
    var dailyCreditCardExpenseTotals: [Int] = []
    var dailyTransferFeeTotals: [Int] = []

    init() {}
}

@Model
final class LegacyAssetGraphCacheData {
    @Attribute(.unique) var id: String = ""
    var bookId: UUID? = nil
    var updatedAt: Date = Date()
    var maxPointsUsed: Int = 0
    var granularityUsed: String = ""
    var firstDate: Date = Date()
    var lastDate: Date = Date()
    var points: [LegacyAssetGraphCachePoint] = []

    init() {}
}

// MARK: - Schema

enum LegacySchema {
    static let modelTypes: [any PersistentModel.Type] = [
        LegacyBookData.self,
        LegacyCategoryData.self,
        LegacyExpenseData.self,
        LegacyIncomeData.self,
        LegacyTransferData.self,
        LegacyBankAccountData.self,
        LegacyReceiveMethodData.self,
        LegacyPaymentMethodSettingData.self,
        LegacyBudgetData.self,
        LegacyRecurringBudgetData.self,
        LegacyFixedExpenseData.self,
        LegacyRecurringIncomeData.self,
        LegacyRecurringTransferSettingData.self,
        LegacyDailySnapshot.self,
        LegacyMonthlySnapshot.self,
        LegacyAnalysisMonthlySnapshot.self,
        LegacyAssetGraphCacheData.self
    ]
}
