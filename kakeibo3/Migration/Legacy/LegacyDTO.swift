import Foundation

// MARK: - 旧SwiftDataストアから読み出した値のプレーンな写し(Legacy DTO)
//
// SwiftDataへの依存はMigration層に隔離する方針のため、このファイルは
// import SwiftData をしない。LegacyModels.swift(@Model)から読み出した値を
// そのままコピーしただけの、Codable・依存なしの構造体のみを置く。
// 通常のView・Repository・Serviceからはこのファイルも直接参照しない
// (Migration層の内部でのみ使用する)。
//
// 全17モデルのうち13モデル(下記「直接移行」)がCore Data本番ストアへ移行される。
// 残り4モデル(スナップショット/キャッシュ系)は移行せず、既存の再生成の仕組み
// (SnapshotManager.backfillIfNeeded 等)に任せるため、DTOだけをここに持つ
// (件数把握・Manifest記録のためのみ使用し、Core Dataへは書き込まない)。

// MARK: - 直接移行(13モデル)

struct LegacyBookDataDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date?
    var sortOrder: Int
    var isArchived: Bool
    var isMain: Bool
}

struct LegacyCategoryDataDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String
    var type: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date?
    var isTestData: Bool
    var bookId: UUID?
    var isSuspended: Bool
    var isProtected: Bool
}

struct LegacyExpenseDataDTO: Codable, Equatable {
    var id: UUID
    var amount: Int
    var date: Date
    var paymentMethod: String
    var category: String
    var memo: String
    var createdAt: Date
    var updatedAt: Date?
    var bookId: UUID?
    var bankAccountId: UUID?
    var fixedExpenseId: UUID?
    var receiptImagePath: String?
    var isTestData: Bool
    var isInTrash: Bool
    var trashedAt: Date?
}

struct LegacyIncomeDataDTO: Codable, Equatable {
    var id: UUID
    var amount: Int
    var date: Date
    var receiveMethod: String
    var category: String
    var memo: String
    var createdAt: Date
    var updatedAt: Date?
    var bookId: UUID?
    var bankAccountId: UUID?
    var recurringIncomeId: UUID?
    var receiptImagePath: String?
    var isTestData: Bool
    var isInTrash: Bool
    var trashedAt: Date?
}

struct LegacyTransferDataDTO: Codable, Equatable {
    var id: UUID
    var date: Date
    var fromType: String
    var fromId: UUID?
    var fromName: String
    var toType: String
    var toId: UUID?
    var toName: String
    var amount: Int
    var feeAmount: Int
    var memo: String
    var receiptImagePath: String?
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool
    var recurringTransferSettingId: UUID?
    var bookId: UUID?
    var isInTrash: Bool
    var trashedAt: Date?
}

struct LegacyBankAccountDataDTO: Codable, Equatable {
    var id: UUID
    var accountName: String
    var initialBalance: Double?
    var memo: String?
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var initialBalanceIncomeId: UUID?
    var showAsPaymentMethod: Bool
    var showAsReceiveMethod: Bool
    var showInAnalysis: Bool
    var isAsset: Bool
    var recurringTransferSettingId: UUID?
    var recurringTransferSettingIds: [UUID]
    var isTestData: Bool
    var isLocked: Bool
    var bookId: UUID?
    var colorHex: String?
}

struct LegacyReceiveMethodDataDTO: Codable, Equatable {
    var id: UUID
    var methodName: String
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date?
    var bookId: UUID?
}

struct LegacyPaymentMethodSettingDataDTO: Codable, Equatable {
    var id: UUID
    var methodName: String
    var type: String
    var closingDay: Int?
    var withdrawalDay: Int?
    var adjustPaymentDateToNextBusinessDay: Bool
    var holidayAdjustment: String?
    var bankAccount: String?
    var withdrawalBankAccountId: UUID?
    var memo: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var isActive: Bool
    var isAsset: Bool
    var assetInitialBalance: Double?
    var includeInAnalysis: Bool
    var assetInitialBalanceIncomeId: UUID?
    var assetInitialBalanceExpenseId: UUID?
    var showInInputPicker: Bool
    var useForReceive: Bool
    var showInAnalysis: Bool
    var recurringTransferSettingId: UUID?
    var recurringTransferSettingIds: [UUID]
    var isTestData: Bool
    var isLocked: Bool
    var bookId: UUID?
    var colorHex: String?
}

struct LegacyBudgetDataDTO: Codable, Equatable {
    var id: UUID
    var year: Int
    var month: Int
    var categoryName: String
    var amount: Int
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool
    var bookId: UUID?
}

struct LegacyRecurringBudgetDataDTO: Codable, Equatable {
    var id: UUID
    var categoryName: String
    var amount: Int
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var bookId: UUID?
}

struct LegacyFixedExpenseDataDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryName: String
    var paymentMethodType: String
    var paymentMethodId: UUID?
    var dayOfMonth: Int
    var startDate: Date
    var memo: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool
    var isLocked: Bool
    var bookId: UUID?
    var holidayAdjustment: String
    var generatedScheduleMonths: [String]
}

struct LegacyRecurringIncomeDataDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryName: String
    var receiveMethodType: String
    var receiveMethodId: UUID?
    var dayOfMonth: Int
    var startDate: Date
    var memo: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool
    var isLocked: Bool
    var bookId: UUID?
    var holidayAdjustment: String
    var generatedScheduleMonths: [String]
}

struct LegacyRecurringTransferSettingDataDTO: Codable, Equatable {
    var id: UUID
    var fromMethodId: UUID
    var fromMethodName: String
    var fromType: String
    var toMethodId: UUID
    var toMethodName: String
    var toType: String
    var amount: Int
    var day: Int
    var startDate: Date
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isLocked: Bool
    var isTestData: Bool
    var bookId: UUID?
    var holidayAdjustment: String
    var generatedScheduleMonths: [String]
}

// MARK: - 再生成する派生データ(4モデル、Core Dataへは移行しない。件数把握のみに使用)

struct LegacyAnalysisCategoryAmountDTO: Codable, Equatable {
    var categoryId: UUID?
    var categoryName: String
    var amount: Int
    var percentage: Double
}

struct LegacyAnalysisMethodAmountDTO: Codable, Equatable {
    var methodId: UUID?
    var methodName: String
    var amount: Int
    var percentage: Double
}

struct LegacyAssetGraphCachePointDTO: Codable, Equatable {
    var date: Date
    var value: Int
}

struct LegacyDailySnapshotDTO: Codable, Equatable {
    var date: Date
    var bookId: UUID?
    var incomeTotal: Int
    var expenseTotal: Int
    var creditCardExpenseTotal: Int
    var transferFeeTotal: Int
    var transactionCount: Int
    var updatedAt: Date
}

struct LegacyMonthlySnapshotDTO: Codable, Equatable {
    var yearMonth: String
    var bookId: UUID?
    var year: Int
    var month: Int
    var incomeTotal: Int
    var expenseTotal: Int
    var creditCardExpenseTotal: Int
    var transferFeeTotal: Int
    var carryoverBalance: Int
    var rawCarryoverBalance: Int
    var updatedAt: Date
}

struct LegacyAnalysisMonthlySnapshotDTO: Codable, Equatable {
    var yearMonth: String
    var bookId: UUID?
    var year: Int
    var month: Int
    var incomeTotal: Int
    var expenseTotal: Int
    var creditCardExpenseTotal: Int
    var transferFeeTotal: Int
    var carryoverBalance: Int
    var updatedAt: Date
    var displayExpenseTotal: Int
    var displayIncomeTotal: Int
    var expenseCategoryTotals: [LegacyAnalysisCategoryAmountDTO]
    var incomeCategoryTotals: [LegacyAnalysisCategoryAmountDTO]
    var paymentMethodTotals: [LegacyAnalysisMethodAmountDTO]
    var receiveMethodTotals: [LegacyAnalysisMethodAmountDTO]
    var expenseTransactionCount: Int
    var incomeTransactionCount: Int
    var dailyExpenseTotals: [Int]
    var dailyIncomeTotals: [Int]
    var dailyCreditCardExpenseTotals: [Int]
    var dailyTransferFeeTotals: [Int]
}

struct LegacyAssetGraphCacheDataDTO: Codable, Equatable {
    var id: String
    var bookId: UUID?
    var updatedAt: Date
    var maxPointsUsed: Int
    var granularityUsed: String
    var firstDate: Date
    var lastDate: Date
    var points: [LegacyAssetGraphCachePointDTO]
}

// MARK: - 旧ストア全体の読み取り結果

struct LegacySnapshot {
    var books: [LegacyBookDataDTO] = []
    var categories: [LegacyCategoryDataDTO] = []
    var expenses: [LegacyExpenseDataDTO] = []
    var incomes: [LegacyIncomeDataDTO] = []
    var transfers: [LegacyTransferDataDTO] = []
    var bankAccounts: [LegacyBankAccountDataDTO] = []
    var receiveMethods: [LegacyReceiveMethodDataDTO] = []
    var paymentMethodSettings: [LegacyPaymentMethodSettingDataDTO] = []
    var budgets: [LegacyBudgetDataDTO] = []
    var recurringBudgets: [LegacyRecurringBudgetDataDTO] = []
    var fixedExpenses: [LegacyFixedExpenseDataDTO] = []
    var recurringIncomes: [LegacyRecurringIncomeDataDTO] = []
    var recurringTransferSettings: [LegacyRecurringTransferSettingDataDTO] = []

    // 以下4種は移行せず、件数把握・Manifest記録のみに使う(再生成する派生データ)
    var dailySnapshots: [LegacyDailySnapshotDTO] = []
    var monthlySnapshots: [LegacyMonthlySnapshotDTO] = []
    var analysisMonthlySnapshots: [LegacyAnalysisMonthlySnapshotDTO] = []
    var assetGraphCaches: [LegacyAssetGraphCacheDataDTO] = []
}
