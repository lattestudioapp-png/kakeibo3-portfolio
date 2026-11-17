import Foundation

// MARK: - 銀行口座データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDBankAccountData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`BankAccountDataSync`が変換を担当する）。
struct BankAccountData: Identifiable, Hashable {
    var id: UUID
    var accountName: String
    var initialBalance: Double?
    var memo: String?
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date = Date()
    // 自動作成した初期残高 IncomeData の UUID（更新・削除時の検索キー）
    var initialBalanceIncomeId: UUID? = nil
    // 入力Viewの支払い/受け取り方法一覧に表示するか
    var showAsPaymentMethod: Bool = true
    var showAsReceiveMethod: Bool = true
    // 分析View（資産一覧・総資産）に表示するか
    var showInAnalysis: Bool = true
    // 総資産の計算対象に含めるか（falseにすると分析にも表示されなくなる）
    var isAsset: Bool = true
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
        accountName: String,
        initialBalance: Double? = nil,
        memo: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountName = accountName
        self.initialBalance = initialBalance
        self.memo = memo
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
