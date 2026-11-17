import Foundation

// MARK: - 月次集計スナップショット
//
// 分析Viewの「総資産・繰越額」を高速に読めるようにするための事前計算キャッシュ。
// carryoverBalance は「その月が始まる時点」での資産ベースの繰越残高＝
// 前月の carryoverBalance + 前月の資産ベースnet（クレジットカードの資産反映タイミング設定・
// 振替手数料を織り込み済み）。月初残高を絶対値でチェーン管理することで、
// 日ごとの資産累計をキャッシュせずに済ませている（日次の累計が必要な場面では、
// 対象月の carryoverBalance に、その月内の DailySnapshot を該当日まで積み上げるだけで求められる）。
//
// クレジットカードの資産反映タイミング設定（利用日／引き落とし日）を変更した場合は、
// 過去の carryoverBalance チェーンが総入れ替えになるため SnapshotManager.rebuildAll を呼ぶ
// （通常の取引の保存・編集・削除では「編集月〜現在月までの連鎖更新」だけで済む）。
//
// SnapshotManager が取引の保存・編集・削除のたびに該当月ぶんだけ更新する。

struct MonthlySnapshot: Hashable {
    // "2026-07" 形式。ソート・検索キーとして使う（bookIdとの組で一意）
    var yearMonth: String
    var bookId: UUID?
    var year: Int
    var month: Int
    var incomeTotal: Int
    var expenseTotal: Int
    var creditCardExpenseTotal: Int
    var transferFeeTotal: Int
    var carryoverBalance: Int
    // カレンダーViewの「前月繰越」表示専用のチェーン。carryoverBalanceと違い、
    // クレジットカードの資産反映タイミング調整・振替手数料の控除を行わない
    // 単純な「収入合計−支出合計」の月またぎ積み上げ（ロック除外は反映済み）。
    var rawCarryoverBalance: Int
    var updatedAt: Date

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
        rawCarryoverBalance: Int = 0,
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
        self.rawCarryoverBalance = rawCarryoverBalance
        self.updatedAt = updatedAt
    }

    var netTotal: Int { incomeTotal - expenseTotal }

    // 資産ベースのnet（総資産計算用。クレジットカードの資産反映タイミング・振替手数料を考慮）
    func assetNetTotal(assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        let assetExpense = assetReflectionTiming == .withdrawalDate
            ? expenseTotal - creditCardExpenseTotal
            : expenseTotal
        return incomeTotal - assetExpense - transferFeeTotal
    }

    // carryoverBalance は資産ベースのnetで積み上げているため、月末残高も同じ基準で計算する
    // （netTotal ではなく assetNetTotal を使う）
    func endOfMonthBalance(assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        carryoverBalance + assetNetTotal(assetReflectionTiming: assetReflectionTiming)
    }

    // カレンダーの「前月繰越」表示用（rawCarryoverBalanceと同じ単純基準で月末残高を返す）
    var rawEndOfMonthBalance: Int { rawCarryoverBalance + netTotal }
}
