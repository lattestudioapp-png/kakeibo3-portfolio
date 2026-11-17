import Foundation

// MARK: - 分析View専用の月次集計スナップショット
//
// MonthlySnapshotとほぼ同じ構造・チェーン方式（詳細はMonthlySnapshotのコメント参照）だが、
// scalar totals/日別配列（総資産・資産推移用）の除外基準がDowngradeLockService.isExcludedFromAssetTotal
// 相当（ロック＋isAsset除外）である点が異なる（詳細はAnalysisSnapshotManagerのコメント参照）。
// カレンダー用のrawCarryoverBalanceに相当するものは分析側では使わないため持たない。
//
// AnalysisSnapshotManager が取引の保存・編集・削除のたびに該当月ぶんだけ更新する。
// クレジットカードの資産反映タイミング設定を変更した場合はAnalysisSnapshotManager.rebuildAllで全期間作り直す。

// MARK: - カテゴリー別・支払い/受け取り方法別の内訳（1件分）
//
// percentageはその月単独の集計に対する割合。年・全期間など複数月をまたぐ集計では
// 保存された値をそのまま使わず、合算後のamountから割合を再計算すること
// （月ごとの分母が異なるため、保存済みpercentageの平均や合算では正しい値にならない。
// AnalysisSnapshotBreakdownAggregator参照）。
//
// categoryId/methodIdは集計時点でCategoryData/PaymentMethodSettingData（+ReceiveMethodData）を
// 名前で検索して解決する。カテゴリー名変更・削除後の古いデータでは解決できずnilになりうる
// （ExpenseData/IncomeDataのcategory文字列自体は書き換えないため）。

struct AnalysisCategoryAmount: Codable, Hashable {
    var categoryId: UUID?
    var categoryName: String
    var amount: Int
    var percentage: Double
}

struct AnalysisMethodAmount: Codable, Hashable {
    var methodId: UUID?
    var methodName: String
    var amount: Int
    var percentage: Double
}

struct AnalysisMonthlySnapshot: Hashable {
    // "2026-07" 形式。ソート・検索キーとして使う（bookIdとの組で一意）
    var yearMonth: String
    var bookId: UUID?
    var year: Int
    var month: Int
    // MARK: - 総資産・資産推移用のtotals（「資産に含める」＝isAssetだけで集計対象を決める）
    var incomeTotal: Int
    var expenseTotal: Int
    var creditCardExpenseTotal: Int
    var transferFeeTotal: Int
    var carryoverBalance: Int
    var updatedAt: Date

    // MARK: - 支出/収入タブの見出し合計（ロック中かどうかだけで判定。isAsset/「分析に表示」の影響を受けない）
    var displayExpenseTotal: Int = 0
    var displayIncomeTotal: Int = 0

    // MARK: - カテゴリー別・方法別内訳（分析Viewのカテゴリー/支払い方法タブ用）
    var expenseCategoryTotals: [AnalysisCategoryAmount] = []
    var incomeCategoryTotals: [AnalysisCategoryAmount] = []
    var paymentMethodTotals: [AnalysisMethodAmount] = []
    var receiveMethodTotals: [AnalysisMethodAmount] = []

    // 分析Viewの「件数」表示用（支出は振替手数料の件数も含む。ライブ集計時のperiod.count+fees.countと同じ基準）
    var expenseTransactionCount: Int = 0
    var incomeTransactionCount: Int = 0

    // MARK: - 日別配列（資産推移グラフの精度維持用。index 0 = その月の1日）
    var dailyExpenseTotals: [Int] = []
    var dailyIncomeTotals: [Int] = []
    var dailyCreditCardExpenseTotals: [Int] = []
    var dailyTransferFeeTotals: [Int] = []

    init(
        yearMonth: String,
        bookId: UUID,
        year: Int,
        month: Int,
        incomeTotal: Int = 0,
        expenseTotal: Int = 0,
        creditCardExpenseTotal: Int = 0,
        transferFeeTotal: Int = 0,
        carryoverBalance: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.yearMonth = yearMonth
        self.bookId = bookId
        self.year = year
        self.month = month
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.creditCardExpenseTotal = creditCardExpenseTotal
        self.transferFeeTotal = transferFeeTotal
        self.carryoverBalance = carryoverBalance
        self.updatedAt = updatedAt
    }

    var netTotal: Int { incomeTotal - expenseTotal }

    func assetNetTotal(assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        let assetExpense = assetReflectionTiming == .withdrawalDate
            ? expenseTotal - creditCardExpenseTotal
            : expenseTotal
        return incomeTotal - assetExpense - transferFeeTotal
    }

    func endOfMonthBalance(assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        carryoverBalance + assetNetTotal(assetReflectionTiming: assetReflectionTiming)
    }
}
