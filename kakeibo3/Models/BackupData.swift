import Foundation

// MARK: - ルートバックアップ構造体

struct BackupData: Codable {
    static let currentVersion = 2

    let version: Int
    let createdAt: Date
    // nil = 帳簿単位対応前の旧バックアップ（アプリ全体の丸ごとバックアップ）。
    // 復元時、nilなら全帳簿を丸ごと置き換える旧方式、non-nilなら対象帳簿だけを
    // 置き換える新方式で処理を分岐する（BackupManager.restore参照）。
    // varにしているのは、let+デフォルト値だとCodableの自動デコードで値が
    // 無視されてしまうため（他の新規追加フィールドも同様の理由でvarにしている）。
    var sourceBookId: UUID? = nil
    // 旧バックアップ（帳簿機能導入前）には存在しないため Optional にし、復元時は空配列扱いにする。
    // 新方式（sourceBookIdがnon-nil）では常にその帳簿1件のみが入る。
    var books: [BookBackupItem]?
    var expenses: [ExpenseBackupItem]
    var incomes: [IncomeBackupItem]
    var transfers: [TransferBackupItem]
    var categories: [CategoryBackupItem]
    var paymentMethods: [PaymentMethodBackupItem]
    var receiveMethods: [ReceiveMethodBackupItem]
    var bankAccounts: [BankAccountBackupItem]
    var budgets: [BudgetBackupItem]
    var recurringBudgets: [RecurringBudgetBackupItem]
    var fixedExpenses: [FixedExpenseBackupItem]
    var recurringIncomes: [RecurringIncomeBackupItem]
    var recurringTransfers: [RecurringTransferBackupItem]
    let settings: BackupSettings
}

// MARK: - 帳簿

struct BookBackupItem: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let sortOrder: Int
    let isArchived: Bool
    let isMain: Bool
}

// MARK: - 設定

struct BackupSettings: Codable {
    let themeColorHex: String?
    let analysisSegmentOrder: String?
    let showPreviousMonthCarryover: Bool
    let creditCardAssetReflectionTiming: String?
    let accountingMonthStartDay: Int?
    let accountingMonthWeekendHolidayAdjustment: String?
    let accountingMonthLabelBasis: String?
    let calendarWeekStartWeekday: Int?
}

// MARK: - 支出

struct ExpenseBackupItem: Codable {
    let id: UUID
    let amount: Int
    let date: Date
    let paymentMethod: String
    let category: String
    let memo: String
    let createdAt: Date
    let bankAccountId: UUID?
    let fixedExpenseId: UUID?
    let receiptImagePath: String?
    let isTestData: Bool
    let bookId: UUID?
    // 以下2件は旧バックアップに無いため Optional にし、復元時はそれぞれ false/nil 扱いにする
    var isInTrash: Bool? = nil
    var trashedAt: Date? = nil
}

// MARK: - 収入

struct IncomeBackupItem: Codable {
    let id: UUID
    let amount: Int
    let date: Date
    let receiveMethod: String
    let category: String
    let memo: String
    let createdAt: Date
    let bankAccountId: UUID?
    let recurringIncomeId: UUID?
    let receiptImagePath: String?
    let isTestData: Bool
    let bookId: UUID?
    // 以下2件は旧バックアップに無いため Optional にし、復元時はそれぞれ false/nil 扱いにする
    var isInTrash: Bool? = nil
    var trashedAt: Date? = nil
}

// MARK: - 振替

struct TransferBackupItem: Codable {
    let id: UUID
    let date: Date
    let fromType: String
    let fromId: UUID?
    let fromName: String
    let toType: String
    let toId: UUID?
    let toName: String
    let amount: Int
    let feeAmount: Int
    let memo: String
    let receiptImagePath: String?
    let createdAt: Date
    let updatedAt: Date
    let recurringTransferSettingId: UUID?
    let bookId: UUID?
    // 以下3件は旧バックアップに無いため Optional にし、復元時はそれぞれ false/false/nil 扱いにする
    var isTestData: Bool? = nil
    var isInTrash: Bool? = nil
    var trashedAt: Date? = nil
}

// MARK: - カテゴリー

struct CategoryBackupItem: Codable {
    // 旧バックアップにはこのフィールドが無いため Optional にし、復元時は新規UUIDを生成する
    var id: UUID? = nil
    let name: String
    let colorHex: String
    let type: String
    let sortOrder: Int
    let createdAt: Date
    let bookId: UUID?
    // 以下3件は旧バックアップに無いため Optional にし、復元時はそれぞれ false 扱いにする
    var isTestData: Bool? = nil
    var isSuspended: Bool? = nil
    var isProtected: Bool? = nil
}

// MARK: - 支払い方法

struct PaymentMethodBackupItem: Codable {
    let id: UUID
    let methodName: String
    let type: String
    let closingDay: Int?
    let withdrawalDay: Int?
    // 旧バックアップにはこのフィールドが無いため Optional にし、復元時は true 扱いにする
    let adjustPaymentDateToNextBusinessDay: Bool?
    let bankAccount: String?
    let withdrawalBankAccountId: UUID?
    var memo: String? = nil
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Int
    let isActive: Bool
    let isAsset: Bool
    let assetInitialBalance: Double?
    let includeInAnalysis: Bool
    let assetInitialBalanceIncomeId: UUID?
    var assetInitialBalanceExpenseId: UUID? = nil
    let showInInputPicker: Bool
    let useForReceive: Bool
    let showInAnalysis: Bool
    let recurringTransferSettingId: UUID?
    let recurringTransferSettingIds: [UUID]
    let isTestData: Bool
    let bookId: UUID?
    // 以下3件は旧バックアップに無いため Optional にし、復元時はそれぞれ false/nil/nil 扱いにする
    var isLocked: Bool? = nil
    var colorHex: String? = nil
    var holidayAdjustment: String? = nil
}

// MARK: - 受け取り方法

struct ReceiveMethodBackupItem: Codable {
    let id: UUID
    let methodName: String
    let isActive: Bool
    let sortOrder: Int
    let createdAt: Date
    let bookId: UUID?
}

// MARK: - 銀行口座

struct BankAccountBackupItem: Codable {
    let id: UUID
    let accountName: String
    let initialBalance: Double?
    let memo: String?
    let isActive: Bool
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let initialBalanceIncomeId: UUID?
    let showAsPaymentMethod: Bool
    let showAsReceiveMethod: Bool
    let showInAnalysis: Bool
    let recurringTransferSettingId: UUID?
    let recurringTransferSettingIds: [UUID]
    let isTestData: Bool
    let bookId: UUID?
    // 以下3件は旧バックアップに無いため Optional にし、復元時はそれぞれ true/false/nil 扱いにする
    // （isAssetのドメイン側デフォルトはtrueのため、欠落時はtrue扱いが既存挙動との整合性が高い）
    var isAsset: Bool? = nil
    var isLocked: Bool? = nil
    var colorHex: String? = nil
}

// MARK: - 予算

struct BudgetBackupItem: Codable {
    let id: UUID
    let year: Int
    let month: Int
    let categoryName: String
    let amount: Int
    let createdAt: Date
    let updatedAt: Date
    let isTestData: Bool
    let bookId: UUID?
}

// MARK: - 定期予算

struct RecurringBudgetBackupItem: Codable {
    let id: UUID
    let categoryName: String
    let amount: Int
    let isEnabled: Bool
    let createdAt: Date
    let updatedAt: Date
    let bookId: UUID?
}

// MARK: - 固定費

struct FixedExpenseBackupItem: Codable {
    let id: UUID
    let name: String
    let amount: Int
    let categoryName: String
    let paymentMethodType: String
    let paymentMethodId: UUID?
    let dayOfMonth: Int
    let startDate: Date
    let memo: String
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let isTestData: Bool
    let bookId: UUID?
    // 旧バックアップには無いため Optional にし、復元時は false 扱いにする
    var isLocked: Bool? = nil
    // 以下2件は旧バックアップに無いため Optional にし、復元時はそれぞれ
    // WeekendHolidayAdjustment.shiftLater.rawValue / 空配列 扱いにする
    var holidayAdjustment: String? = nil
    var generatedScheduleMonths: [String]? = nil
}

// MARK: - 定期収入

struct RecurringIncomeBackupItem: Codable {
    let id: UUID
    let name: String
    let amount: Int
    let categoryName: String
    let receiveMethodType: String
    let receiveMethodId: UUID?
    let dayOfMonth: Int
    let startDate: Date
    let memo: String
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let isTestData: Bool
    let bookId: UUID?
    // 旧バックアップには無いため Optional にし、復元時は false 扱いにする
    var isLocked: Bool? = nil
    // 以下2件は旧バックアップに無いため Optional にし、復元時はそれぞれ
    // WeekendHolidayAdjustment.shiftLater.rawValue / 空配列 扱いにする
    var holidayAdjustment: String? = nil
    var generatedScheduleMonths: [String]? = nil
}

// MARK: - 定期振替

struct RecurringTransferBackupItem: Codable {
    let id: UUID
    let fromMethodId: UUID
    let fromMethodName: String
    let fromType: String
    let toMethodId: UUID
    let toMethodName: String
    let toType: String
    let amount: Int
    let day: Int
    let startDate: Date?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let bookId: UUID?
    // 以下2件は旧バックアップに無いため Optional にし、復元時はそれぞれ false 扱いにする
    var isLocked: Bool? = nil
    var isTestData: Bool? = nil
    // 以下2件は旧バックアップに無いため Optional にし、復元時はそれぞれ
    // WeekendHolidayAdjustment.shiftLater.rawValue / 空配列 扱いにする
    var holidayAdjustment: String? = nil
    var generatedScheduleMonths: [String]? = nil
}
