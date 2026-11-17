import Foundation

// MARK: - ゴミ箱の自動完全削除
//
// isInTrash=trueのまま30日経過した支出・収入・振替を、アプリ起動のたびに完全削除する。
// バックグラウンド処理・スケジュール実行はなく、RecurringEntryGenerator.backfillAllIfNeeded()と
// 同じ「起動のたびに確認する」方式（Kakeibo3App.onAppear参照）。
//
// 全帳簿を横断して対象にする（帳簿単位のスコープは持たない）。ゴミ箱投入時点で既に
// 集計対象外のため、ここではSnapshotUpdateServiceを呼ばない（trashTransaction/
// permanentlyDeleteTransactionと同じ方針）。
enum TrashPurgeService {
    private static let retentionDays = 30

    static func purgeExpiredIfNeeded() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }

        // ExpenseDataSync.fetchAll()等はゴミ箱内を除外するのがデフォルトのため、ここでは
        // 帳簿ごとにfetchTrashed(bookId:)を呼び、全帳簿ぶんのゴミ箱内データを横断して集める。
        let bookIds = BookDataSync.fetchAll().map(\.id)
        let expiredExpenses = bookIds.flatMap { ExpenseDataSync.fetchTrashed(bookId: $0) }
            .filter { $0.trashedAt.map { $0 < cutoff } ?? false }
        let expiredIncomes = bookIds.flatMap { IncomeDataSync.fetchTrashed(bookId: $0) }
            .filter { $0.trashedAt.map { $0 < cutoff } ?? false }
        let expiredTransfers = bookIds.flatMap { TransferDataSync.fetchTrashed(bookId: $0) }
            .filter { $0.trashedAt.map { $0 < cutoff } ?? false }

        guard !expiredExpenses.isEmpty || !expiredIncomes.isEmpty || !expiredTransfers.isEmpty else { return }

        for expense in expiredExpenses {
            let paths = ReceiptImageHelper.decodePaths(expense.receiptImagePath)
            ReceiptImageHelper.deleteAll(paths)
            ReceiptPhotoSyncService.removeSynced(filenames: paths)
            ExpenseDataSync.delete(id: expense.id)
        }
        for income in expiredIncomes {
            let paths = ReceiptImageHelper.decodePaths(income.receiptImagePath)
            ReceiptImageHelper.deleteAll(paths)
            ReceiptPhotoSyncService.removeSynced(filenames: paths)
            IncomeDataSync.delete(id: income.id)
        }
        for transfer in expiredTransfers {
            let paths = ReceiptImageHelper.decodePaths(transfer.receiptImagePath)
            ReceiptImageHelper.deleteAll(paths)
            ReceiptPhotoSyncService.removeSynced(filenames: paths)
            TransferDataSync.delete(id: transfer.id)
        }
    }
}
