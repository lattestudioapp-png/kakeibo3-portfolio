import Foundation

// MARK: - 支払い方法設定データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDPaymentMethodSettingData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`PaymentMethodSettingDataSync`が変換を担当する）。
struct PaymentMethodSettingData: Identifiable, Hashable {
    var id: UUID
    var methodName: String
    var type: String
    var closingDay: Int?
    var withdrawalDay: Int?
    // 旧方式（2択・Bool）。クレジットカードの引落予定日が土日祝の場合に翌営業日へずらすか。
    // holidayAdjustmentへ移行済みのため、以後は書き込まない。holidayAdjustmentがnilの
    // 既存カードだけ、resolvedHolidayAdjustmentのフォールバック導出に使う。
    var adjustPaymentDateToNextBusinessDay: Bool = true
    // 新方式（3択）。WeekendHolidayAdjustment.rawValue。nil = 旧UIのままholidayAdjustmentを
    // 一度も保存していない（resolvedHolidayAdjustmentが旧Boolから自動導出する）。
    var holidayAdjustment: String? = nil
    var bankAccount: String?
    // 引き落とし口座を BankAccountData の UUID で管理（口座名変更に対して堅牢）
    var withdrawalBankAccountId: UUID? = nil
    var memo: String? = nil
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int = 0
    var isActive: Bool = true
    var isAsset: Bool = false
    var assetInitialBalance: Double? = nil
    var includeInAnalysis: Bool = true
    var assetInitialBalanceIncomeId: UUID? = nil
    // 負債扱いの初期残高分を紐づける ExpenseData の UUID（更新・削除時の検索キー）。
    // 借入機能は廃止済みだが、BankAccountBalanceCalculator/AnalysisViewModelが
    // assetInitialBalanceIncomeIdと合わせて汎用的に参照するため残している。
    var assetInitialBalanceExpenseId: UUID? = nil
    // 入力Viewの支払い方法一覧に表示するか（false = データは残すが一覧には出ない）
    var showInInputPicker: Bool = true
    // 受け取り方法としても使用するか
    var useForReceive: Bool = false
    // 分析Viewに表示するか（false = データは残すが分析には出ない）
    var showInAnalysis: Bool = true
    // 紐づく RecurringTransferSettingData の UUID（旧・後方互換用）
    var recurringTransferSettingId: UUID? = nil
    // 複数の定期振替設定 UUID（新）
    var recurringTransferSettingIds: [UUID] = []
    var isTestData: Bool = false
    // 無料版の上限超過によりロックされているか（データは保持したまま利用制限する）
    var isLocked: Bool = false
    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil
    // 表示色（カテゴリーと同じCategoryColorPalette由来のhexコード）。nil = 未設定（テーマカラーで表示）。
    // このお金の管理データを表す色情報は常にこのプロパティが唯一の情報源。一覧・アイコン・
    // 各種グラフ（支払い方法別グラフなど、今後追加するものも含む）は、独自の色パレットを
    // 持たずに必ずこのcolorHex（ColorHexConverter.color(from:)経由）を参照すること。
    var colorHex: String? = nil

    init(
        id: UUID = UUID(),
        methodName: String,
        type: String,
        closingDay: Int? = nil,
        withdrawalDay: Int? = nil,
        adjustPaymentDateToNextBusinessDay: Bool = true,
        bankAccount: String? = nil,
        withdrawalBankAccountId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.methodName = methodName
        self.type = type
        self.closingDay = closingDay
        self.withdrawalDay = withdrawalDay
        self.adjustPaymentDateToNextBusinessDay = adjustPaymentDateToNextBusinessDay
        self.bankAccount = bankAccount
        self.withdrawalBankAccountId = withdrawalBankAccountId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    // MARK: - 休業日調整（3択）の実効値
    //
    // holidayAdjustmentが未保存（nil）の既存カードは、旧Bool
    // （true=翌営業日にする, false=そのまま何もしない）から導出する。
    // 一度でも新UIで保存されればholidayAdjustmentが確定し、以後はそちらだけを見る。
    var resolvedHolidayAdjustment: WeekendHolidayAdjustment {
        if let raw = holidayAdjustment, let value = WeekendHolidayAdjustment(rawValue: raw) {
            return value
        }
        return adjustPaymentDateToNextBusinessDay ? .shiftLater : .none
    }
}

// MARK: - クレジットカード利用分の総資産反映タイミング

enum CreditCardAssetReflectionTiming: String, CaseIterable {
    case usageDate      = "usageDate"
    case withdrawalDate = "withdrawalDate"

    static let storageKey = "creditCardAssetReflectionTiming"
    static let defaultValue: CreditCardAssetReflectionTiming = .usageDate

    var displayName: String {
        switch self {
        case .usageDate:      return "利用日に反映"
        case .withdrawalDate: return "引き落とし日に反映"
        }
    }

    var description: String {
        switch self {
        case .usageDate:
            return "カードで支払った日に総資産を減らします。引き落とし日には総資産を変動させません。"
        case .withdrawalDate:
            return "引き落とし口座からお金が引き落とされるタイミングで総資産を減らします。利用日には総資産を変動させません。"
        }
    }
}

enum PaymentMethodType: String, CaseIterable {
    case cash = "cash"
    case creditCard = "creditCard"
    case debitCard = "debitCard"
    case electronicMoney = "electronicMoney"
    case bankTransfer = "bankTransfer"
    case securities = "securities"
    case crypto = "crypto"
    case other = "other"

    var displayName: String {
        switch self {
        case .cash: return "現金"
        case .creditCard: return "クレジットカード"
        case .debitCard: return "デビットカード"
        case .electronicMoney: return "電子マネー"
        case .bankTransfer: return "口座引落"
        case .securities: return "証券口座"
        case .crypto: return "暗号資産"
        case .other: return "その他"
        }
    }
}
