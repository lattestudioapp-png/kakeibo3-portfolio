import Foundation

// MARK: - 保存失敗の明示的なエラー
//
// 以前はExpenseDataSync.insert/update等の戻り値が無く、context.save()が実際に失敗しても
// 呼び出し元(InputView等)には何も伝わらず「保存した体」のまま画面が進んでしまっていた
// （帳簿が1件も無い状態での保存試行等で実際に発生した）。これを明示的なErrorとして
// 呼び出し元まで伝播させ、UIで必ずユーザーへ知らせる・入力内容を消さない対応を取れるようにする。
enum TransactionSaveError: LocalizedError, Equatable {
    /// 保存先の帳簿が解決できなかった（帳簿が1件も無い、CloudKit初回同期待ち等）
    case noBookAvailable
    /// Core Dataへの実際の永続化(context.save())が失敗した
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .noBookAvailable:
            return "保存先の帳簿の準備ができていません。少し時間をおいてから、もう一度保存をお試しください。"
        case .persistenceFailed:
            return "データの保存に失敗しました。もう一度お試しください。"
        }
    }
}

// MARK: - 収支データRepository

/**
 ExpenseData / IncomeData の保存・更新・削除を担当するRepository。
 */
protocol TransactionRepository {
    func insertNewTransaction(
        draft: TransactionDraft,
        expenseTypeName: String
    ) throws

    func updateTransaction(
        originalItem: TransactionListItem,
        draft: TransactionDraft,
        expenseTypeName: String,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) throws -> Bool

    func deleteTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) throws -> Bool

    /// 支出/収入/振替のいずれかをゴミ箱へ移動する（isInTrash=true, trashedAt=Date()）。
    /// 実レコードの削除は行わない。通常削除と同じSnapshotEventを発火する。
    func trashTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Bool

    /// ゴミ箱から元に戻す（isInTrash=false, trashedAt=nil）。それ以外のフィールド
    /// （帳簿・日付・カテゴリー・支払い方法・金額・写真参照）には一切触れない。
    func restoreTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Bool

    /// ゴミ箱内の1件を完全に削除する。写真ファイルも削除する。
    func permanentlyDeleteTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Bool

    /// 指定した帳簿のゴミ箱内データを全て完全に削除する（他帳簿には触れない）。
    /// 削除件数を返す。
    func emptyTrash(
        bookId: UUID,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Int
}

struct SwiftDataTransactionRepository: TransactionRepository {
    func insertNewTransaction(
        draft: TransactionDraft,
        expenseTypeName: String
    ) throws {
        try insertDraft(
            draft,
            expenseTypeName: expenseTypeName
        )

        let event: SnapshotEvent = draft.type == expenseTypeName
            ? .expenseCreated(date: draft.date, bookId: draft.bookId)
            : .incomeCreated(date: draft.date, bookId: draft.bookId)
        SnapshotUpdateService.handle(event)
    }

    func updateTransaction(
        originalItem: TransactionListItem,
        draft: TransactionDraft,
        expenseTypeName: String,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) throws -> Bool {
        let originalTypeName = typeName(
            for: originalItem.kind,
            expenseTypeName: expenseTypeName
        )

        if originalTypeName == draft.type {
            let updated = try updateSameTypeTransaction(
                originalItem: originalItem,
                draft: draft,
                expenseTypeName: expenseTypeName,
                incomeDataList: incomeDataList,
                expenseDataList: expenseDataList
            )

            guard updated else {
                return false
            }
        } else {
            let deleted = deleteOnly(
                originalItem: originalItem,
                incomeDataList: incomeDataList,
                expenseDataList: expenseDataList
            )

            guard deleted else {
                return false
            }

            try insertDraft(
                draft,
                expenseTypeName: expenseTypeName
            )
        }

        let event: SnapshotEvent = originalItem.kind == .income
            ? .incomeUpdated(oldDate: originalItem.date, newDate: draft.date, bookId: draft.bookId)
            : .expenseUpdated(oldDate: originalItem.date, newDate: draft.date, bookId: draft.bookId)
        SnapshotUpdateService.handle(event)
        return true
    }

    func deleteTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) throws -> Bool {
        let deleted = deleteOnly(
            originalItem: originalItem,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList
        )

        guard deleted else {
            return false
        }

        let event: SnapshotEvent = originalItem.kind == .income
            ? .incomeDeleted(date: originalItem.date, bookId: originalItem.bookId ?? UUID())
            : .expenseDeleted(date: originalItem.date, bookId: originalItem.bookId ?? UUID())
        SnapshotUpdateService.handle(event)
        return true
    }

    // MARK: - 内部処理

    private func insertDraft(
        _ draft: TransactionDraft,
        expenseTypeName: String
    ) throws {
        // 【調査用診断ログ】個人情報・取引内容は出力しない（bookId識別子のみ、調査内容9）。
        DiagnosticLog.logTransactionSaveBookId(
            kind: draft.type == expenseTypeName ? "expense" : "income", bookId: draft.bookId
        )
        if draft.type == expenseTypeName {
            var expense = ExpenseData(
                amount: draft.amount,
                date: draft.date,
                paymentMethod: draft.method,
                category: draft.category,
                memo: draft.memo,
                bankAccountId: draft.bankAccountId
            )
            expense.bookId = draft.bookId
            expense.receiptImagePath = ReceiptImageHelper.encodePaths(draft.receiptImagePaths)
            guard ExpenseDataSync.insertChecked(expense) else {
                throw TransactionSaveError.persistenceFailed
            }
            ReceiptPhotoSyncService.ensureSynced(
                filenames: draft.receiptImagePaths, transactionType: .expense,
                transactionId: expense.id, bookId: draft.bookId
            )
        } else {
            var income = IncomeData(
                amount: draft.amount,
                date: draft.date,
                receiveMethod: draft.method,
                category: draft.category,
                memo: draft.memo,
                bankAccountId: draft.bankAccountId
            )
            income.bookId = draft.bookId
            income.receiptImagePath = ReceiptImageHelper.encodePaths(draft.receiptImagePaths)
            guard IncomeDataSync.insertChecked(income) else {
                throw TransactionSaveError.persistenceFailed
            }
            ReceiptPhotoSyncService.ensureSynced(
                filenames: draft.receiptImagePaths, transactionType: .income,
                transactionId: income.id, bookId: draft.bookId
            )
        }
    }

    private func updateSameTypeTransaction(
        originalItem: TransactionListItem,
        draft: TransactionDraft,
        expenseTypeName: String,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) throws -> Bool {
        switch originalItem.kind {
        case .expense:
            guard var expense = expenseDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }

            expense.amount = draft.amount
            expense.date = draft.date
            expense.paymentMethod = draft.method
            expense.category = draft.category
            expense.memo = draft.memo
            expense.bankAccountId = draft.bankAccountId
            expense.receiptImagePath = ReceiptImageHelper.encodePaths(draft.receiptImagePaths)
            guard ExpenseDataSync.updateChecked(expense) else {
                throw TransactionSaveError.persistenceFailed
            }
            ReceiptPhotoSyncService.ensureSynced(
                filenames: draft.receiptImagePaths, transactionType: .expense,
                transactionId: expense.id, bookId: draft.bookId
            )
            return true

        case .income:
            guard var income = incomeDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }

            income.amount = draft.amount
            income.date = draft.date
            income.receiveMethod = draft.method
            income.category = draft.category
            income.memo = draft.memo
            income.bankAccountId = draft.bankAccountId
            income.receiptImagePath = ReceiptImageHelper.encodePaths(draft.receiptImagePaths)
            guard IncomeDataSync.updateChecked(income) else {
                throw TransactionSaveError.persistenceFailed
            }
            ReceiptPhotoSyncService.ensureSynced(
                filenames: draft.receiptImagePaths, transactionType: .income,
                transactionId: income.id, bookId: draft.bookId
            )
            return true

        case .transfer:
            return false
        }
    }

    private func deleteOnly(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) -> Bool {
        switch originalItem.kind {
        case .expense:
            guard let expense = expenseDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }

            ExpenseDataSync.delete(id: expense.id)
            return true

        case .income:
            guard let income = incomeDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }

            IncomeDataSync.delete(id: income.id)
            return true

        case .transfer:
            return false
        }
    }

    // MARK: - ゴミ箱

    func trashTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Bool {
        let bookId = originalItem.bookId ?? UUID()
        let trashedAt = Date()

        switch originalItem.kind {
        case .expense:
            guard var expense = expenseDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            expense.isInTrash = true
            expense.trashedAt = trashedAt
            ExpenseDataSync.update(expense)

        case .income:
            guard var income = incomeDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            income.isInTrash = true
            income.trashedAt = trashedAt
            IncomeDataSync.update(income)

        case .transfer:
            guard var transfer = transferDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            transfer.isInTrash = true
            transfer.trashedAt = trashedAt
            TransferDataSync.update(transfer)
        }

        let event: SnapshotEvent
        switch originalItem.kind {
        case .expense: event = .expenseDeleted(date: originalItem.date, bookId: bookId)
        case .income: event = .incomeDeleted(date: originalItem.date, bookId: bookId)
        case .transfer: event = .transferDeleted(date: originalItem.date, bookId: bookId)
        }
        SnapshotUpdateService.handle(event)
        return true
    }

    func restoreTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Bool {
        let bookId = originalItem.bookId ?? UUID()

        switch originalItem.kind {
        case .expense:
            guard var expense = expenseDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            expense.isInTrash = false
            expense.trashedAt = nil
            ExpenseDataSync.update(expense)

        case .income:
            guard var income = incomeDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            income.isInTrash = false
            income.trashedAt = nil
            IncomeDataSync.update(income)

        case .transfer:
            guard var transfer = transferDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            transfer.isInTrash = false
            transfer.trashedAt = nil
            TransferDataSync.update(transfer)
        }

        // 復元は新規作成と同じ扱いで、元の取引日を基準にSnapshotへ再度計上する
        let event: SnapshotEvent
        switch originalItem.kind {
        case .expense: event = .expenseCreated(date: originalItem.date, bookId: bookId)
        case .income: event = .incomeCreated(date: originalItem.date, bookId: bookId)
        case .transfer: event = .transferCreated(date: originalItem.date, bookId: bookId)
        }
        SnapshotUpdateService.handle(event)
        return true
    }

    func permanentlyDeleteTransaction(
        originalItem: TransactionListItem,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Bool {
        switch originalItem.kind {
        case .expense:
            guard let expense = expenseDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            let expensePaths = ReceiptImageHelper.decodePaths(expense.receiptImagePath)
            ReceiptImageHelper.deleteAll(expensePaths)
            ReceiptPhotoSyncService.removeSynced(filenames: expensePaths)
            ExpenseDataSync.delete(id: expense.id)

        case .income:
            guard let income = incomeDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            let incomePaths = ReceiptImageHelper.decodePaths(income.receiptImagePath)
            ReceiptImageHelper.deleteAll(incomePaths)
            ReceiptPhotoSyncService.removeSynced(filenames: incomePaths)
            IncomeDataSync.delete(id: income.id)

        case .transfer:
            guard let transfer = transferDataList.first(where: { $0.id == originalItem.sourceId }) else {
                return false
            }
            let transferPaths = ReceiptImageHelper.decodePaths(transfer.receiptImagePath)
            ReceiptImageHelper.deleteAll(transferPaths)
            ReceiptPhotoSyncService.removeSynced(filenames: transferPaths)
            TransferDataSync.delete(id: transfer.id)
        }
        // ゴミ箱投入時点で既に集計対象外のため、ここではSnapshotを更新しない
        return true
    }

    func emptyTrash(
        bookId: UUID,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData]
    ) throws -> Int {
        var deletedCount = 0

        for expense in expenseDataList where expense.isInTrash && expense.bookId == bookId {
            let paths = ReceiptImageHelper.decodePaths(expense.receiptImagePath)
            ReceiptImageHelper.deleteAll(paths)
            ReceiptPhotoSyncService.removeSynced(filenames: paths)
            ExpenseDataSync.delete(id: expense.id)
            deletedCount += 1
        }
        for income in incomeDataList where income.isInTrash && income.bookId == bookId {
            let paths = ReceiptImageHelper.decodePaths(income.receiptImagePath)
            ReceiptImageHelper.deleteAll(paths)
            ReceiptPhotoSyncService.removeSynced(filenames: paths)
            IncomeDataSync.delete(id: income.id)
            deletedCount += 1
        }
        for transfer in transferDataList where transfer.isInTrash && transfer.bookId == bookId {
            let paths = ReceiptImageHelper.decodePaths(transfer.receiptImagePath)
            ReceiptImageHelper.deleteAll(paths)
            ReceiptPhotoSyncService.removeSynced(filenames: paths)
            TransferDataSync.delete(id: transfer.id)
            deletedCount += 1
        }

        return deletedCount
    }

    private func typeName(
        for kind: TransactionKind,
        expenseTypeName: String
    ) -> String {
        switch kind {
        case .expense:
            return expenseTypeName
        case .income:
            return "収入"
        case .transfer:
            return "振替"
        }
    }
}
