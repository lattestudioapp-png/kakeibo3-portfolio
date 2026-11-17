import Foundation

// MARK: - 日次集計スナップショット
//
// カレンダーViewが「全期間の取引を毎回スキャンして集計する」のを避けるための事前計算キャッシュ。
// SnapshotManager が取引の保存・編集・削除のたびに該当日ぶんだけ更新する（詳細は SnapshotManager を参照）。
// ロック中（無料版の上限超過）の口座・支払い方法に紐づく取引は最初から集計に含めない
// （DowngradeLockService.isMethodLocked と同じ判定基準）。
//
// incomeTotal / expenseTotal はカレンダーの日別表示にそのまま使える「無条件の」合計値。
// creditCardExpenseTotal は expenseTotal のうちクレジットカード払いだった分の内訳で、
// 分析Viewの「総資産」計算（引き落とし日に反映モードではクレジットカード支出を除外する）
// が必要な時に expenseTotal から差し引くために使う（BankAccountBalanceCalculator.totalAssets と同じ考え方）。
// transferFeeTotal も同様に総資産計算でのみ使う（振替手数料は日別の収入/支出には出てこない）。

struct DailySnapshot: Hashable {
    // Calendar.current.startOfDay に正規化した日付 + bookId の組でキーにする
    var date: Date
    var bookId: UUID?
    var incomeTotal: Int
    var expenseTotal: Int
    var creditCardExpenseTotal: Int
    var transferFeeTotal: Int
    var transactionCount: Int
    var updatedAt: Date

    init(
        date: Date,
        bookId: UUID,
        incomeTotal: Int = 0,
        expenseTotal: Int = 0,
        creditCardExpenseTotal: Int = 0,
        transferFeeTotal: Int = 0,
        transactionCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.bookId = bookId
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.creditCardExpenseTotal = creditCardExpenseTotal
        self.transferFeeTotal = transferFeeTotal
        self.transactionCount = transactionCount
        self.updatedAt = updatedAt
    }

    var netTotal: Int { incomeTotal - expenseTotal }
}
