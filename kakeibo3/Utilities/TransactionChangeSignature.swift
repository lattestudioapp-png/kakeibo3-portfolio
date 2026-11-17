import Foundation

// MARK: - 収入・支出・振替データの変化検知用シグネチャ

/**
 一覧系Viewが「キャッシュ済みの TransactionListItem を作り直すべきか」を判定するための
 変化検知シグネチャを作るヘルパー。

 件数だけを見ていると、既存の取引を編集した場合（写真を追加した、金額を変えた等）に
 件数が変わらないため変化を検知できず、キャッシュが古いままになってしまう。
 ここでは金額・日付・カテゴリー・支払方法・メモ・写真パスまで含めて比較することで、
 編集による変化も確実に検知できるようにする。

 集計そのものには使わない。onChange の変化検知にのみ使う（O(N) だが許容範囲）。
 */
enum TransactionChangeSignature {
    static func make(
        incomeDataList: [IncomeData] = [],
        expenseDataList: [ExpenseData] = [],
        transferDataList: [TransferData] = []
    ) -> String {
        var hasher = Hasher()
        hasher.combine(incomeDataList.count)
        hasher.combine(expenseDataList.count)
        hasher.combine(transferDataList.count)

        for item in incomeDataList {
            hasher.combine(item.id)
            hasher.combine(item.amount)
            hasher.combine(item.date)
            hasher.combine(item.category)
            hasher.combine(item.receiveMethod)
            hasher.combine(item.memo)
            hasher.combine(item.receiptImagePath)
        }
        for item in expenseDataList {
            hasher.combine(item.id)
            hasher.combine(item.amount)
            hasher.combine(item.date)
            hasher.combine(item.category)
            hasher.combine(item.paymentMethod)
            hasher.combine(item.memo)
            hasher.combine(item.receiptImagePath)
        }
        for item in transferDataList {
            hasher.combine(item.id)
            hasher.combine(item.amount)
            hasher.combine(item.date)
            hasher.combine(item.feeAmount)
            hasher.combine(item.memo)
            hasher.combine(item.receiptImagePath)
        }

        return String(hasher.finalize())
    }
}
