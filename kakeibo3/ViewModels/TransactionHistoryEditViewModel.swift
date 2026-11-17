import Foundation
import Combine

final class TransactionHistoryEditViewModel: ObservableObject {
    let item: TransactionListItem

    private let formService: TransactionFormService
    private let transactionRepository: any TransactionRepository

    init(
        item: TransactionListItem,
        formService: TransactionFormService = TransactionFormService(),
        transactionRepository: any TransactionRepository = SwiftDataTransactionRepository()
    ) {
        self.item = item
        self.formService = formService
        self.transactionRepository = transactionRepository
    }

    func applyItem(to inputViewModel: InputViewModel) {
        switch item.kind {
        case .expense:
            inputViewModel.selectedType = inputViewModel.expenseSetting.typeName
            inputViewModel.selectedExpenseMethod = item.method
            inputViewModel.selectedExpenseCategory = item.category
        case .income:
            inputViewModel.selectedType = inputViewModel.incomeSetting.typeName
            inputViewModel.selectedIncomeMethod = item.method
            inputViewModel.selectedIncomeCategory = item.category
        case .transfer:
            break
        }

        inputViewModel.date = item.date
        inputViewModel.amountText = String(item.amount)
        inputViewModel.memo = item.memo

        reloadPhotos(into: inputViewModel)
    }

    /// 写真をバックグラウンドで読み込んでサムネイルを生成し、inputViewModelへ反映する。
    /// 画面表示直後（applyItem経由）だけでなく、CloudKitから写真を受信した後の自動更新
    /// （修正2：ReceiptPhotoSyncService.photoMaterializedNotificationをView側が受けて呼ぶ）
    /// からも使う、再実行可能な処理。
    func reloadPhotos(into inputViewModel: InputViewModel) {
        let paths = item.receiptImagePaths
        guard !paths.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak inputViewModel] in
            let photos = paths.compactMap { MemoPhoto.make(fromFilePath: $0) }
            DispatchQueue.main.async {
                inputViewModel?.memoPhotos = photos
            }
        }
    }

    /// 保存・削除失敗時にユーザーへ表示するメッセージ。nilなら直近の操作は失敗していない。
    @Published private(set) var lastSaveErrorMessage: String?

    func clearSaveError() {
        lastSaveErrorMessage = nil
    }

    /// - Parameter fallbackBookId: `item.bookId`が無い（マイグレーション未実施の異常系）場合に
    ///   使う帳簿。以前は呼び出し元が解決できない場合に`?? UUID()`で意味を持たないランダムな
    ///   UUIDへフォールバックしており、保存自体は「成功」するが実在しない帳簿へ紐づく
    ///   （どの帳簿からも二度と見えなくなる）という不具合があった。nilを受け取れるようにし、
    ///   両方nilの場合は保存を試みず明確な失敗として扱う。
    @discardableResult
    func updateTransaction(
        inputViewModel: InputViewModel,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        bankAccountId: UUID? = nil,
        fallbackBookId: UUID?
    ) -> Bool {
        guard let resolvedBookId = item.bookId ?? fallbackBookId else {
            lastSaveErrorMessage = TransactionSaveError.noBookAvailable.errorDescription
            return false
        }

        do {
            let isExpense = inputViewModel.selectedType == inputViewModel.expenseSetting.typeName
            let method = isExpense ? inputViewModel.selectedExpenseMethod : inputViewModel.selectedIncomeMethod
            let category = isExpense ? inputViewModel.selectedExpenseCategory : inputViewModel.selectedIncomeCategory

            // 新しい画像ファイルを書き込んでパスを取得
            let newPaths = inputViewModel.resolveImagePaths()
            let oldPaths = item.receiptImagePaths

            // 編集では帳簿間を移動しないため、元の取引の帳簿をそのまま引き継ぐ
            let draft = try formService.makeDraft(
                selectedType: inputViewModel.selectedType,
                amountText: inputViewModel.amountText,
                date: inputViewModel.date,
                selectedMethod: method,
                selectedCategory: category,
                memo: inputViewModel.memo,
                bankAccountId: bankAccountId,
                receiptImagePaths: newPaths,
                bookId: resolvedBookId
            )

            let success = try transactionRepository.updateTransaction(
                originalItem: item,
                draft: draft,
                expenseTypeName: inputViewModel.expenseSetting.typeName,
                incomeDataList: incomeDataList,
                expenseDataList: expenseDataList
            )

            if success {
                // DB保存成功後に古いファイルを削除（新しいファイルはensureSyncedで追加済み。
                // TransactionRepository.updateTransaction内部で呼ばれる）
                ReceiptImageHelper.deleteAll(oldPaths)
                ReceiptPhotoSyncService.removeSynced(filenames: oldPaths)
                lastSaveErrorMessage = nil
            } else {
                // 保存失敗時は新しく書いたファイルをロールバックし、入力内容は消さない
                ReceiptImageHelper.deleteAll(newPaths)
                ReceiptPhotoSyncService.removeSynced(filenames: newPaths)
                lastSaveErrorMessage = "対象の取引が見つかりませんでした。"
            }

            return success
        } catch TransactionFormService.ValidationError.invalidAmount {
            lastSaveErrorMessage = "金額が正しくありません"
            return false
        } catch TransactionFormService.ValidationError.emptyCategory {
            lastSaveErrorMessage = "カテゴリーが選択されていません"
            return false
        } catch let error as TransactionSaveError {
            lastSaveErrorMessage = error.errorDescription
            return false
        } catch {
            lastSaveErrorMessage = "保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteTransaction(
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) -> Bool {
        do {
            let success = try transactionRepository.deleteTransaction(
                originalItem: item,
                incomeDataList: incomeDataList,
                expenseDataList: expenseDataList
            )
            if success {
                ReceiptImageHelper.deleteAll(item.receiptImagePaths)
                lastSaveErrorMessage = nil
            } else {
                lastSaveErrorMessage = "削除に失敗しました。対象の取引が見つかりませんでした。"
            }
            return success
        } catch {
            lastSaveErrorMessage = "削除に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    func deleteAlertTitle(selectedType: String, expenseTypeName: String) -> String {
        selectedType == expenseTypeName ? "支出を削除" : "収入を削除"
    }
}
