import Foundation
import Combine
import UIKit

// MARK: - 入力画面ViewModel

final class InputViewModel: ObservableObject {

    // MARK: - 支出 / 収入設定

    let expenseSetting = ExpenseInputSetting()
    let incomeSetting = IncomeInputSetting()

    // MARK: - 入力状態

    @Published var selectedType: String
    @Published var amountText = ""
    @Published var selectedExpenseCategory: String
    @Published var selectedIncomeCategory: String
    @Published var selectedExpenseMethod: String
    @Published var selectedIncomeMethod: String
    @Published var memo = ""
    @Published var memoPhotos: [MemoPhoto] = []
    @Published var date = Date()

    // MARK: - 表示状態

    @Published var isDatePickerPresented = false
    @Published var isCategoryEditPresented = false
    @Published var isCalculatorKeyboardPresented = false
    @Published var isAddingPhoto = false

    // MARK: - 初期値反映管理

    private var lastAppliedInitialDate = Date.distantPast
    private var lastAppliedInitialType = ""

    // 設定画面の並び順先頭を反映した動的デフォルト（InputView から更新）
    private var defaultExpenseMethod: String = ""
    private var defaultIncomeMethod: String = ""

    // MARK: - Service / Repository

    private let formService: TransactionFormService
    private let transactionRepository: any TransactionRepository

    // MARK: - 初期化

    init(
        formService: TransactionFormService = TransactionFormService(),
        transactionRepository: any TransactionRepository = SwiftDataTransactionRepository()
    ) {
        self.formService = formService
        self.transactionRepository = transactionRepository

        let expense = ExpenseInputSetting()
        let income = IncomeInputSetting()
        selectedType = expense.typeName
        selectedExpenseCategory = expense.defaultCategory
        selectedIncomeCategory = income.defaultCategory
        // 方法はSwiftDataから動的に読み込むため空文字で初期化し、onAppear で補正する
        selectedExpenseMethod = ""
        selectedIncomeMethod = ""
    }

    // MARK: - 動的デフォルト更新（InputView から呼ぶ）

    func updateDefaultExpenseMethod(_ method: String) {
        guard !method.isEmpty else { return }
        defaultExpenseMethod = method
    }

    func updateDefaultIncomeMethod(_ method: String) {
        guard !method.isEmpty else { return }
        defaultIncomeMethod = method
    }

    // MARK: - 現在の入力設定

    var currentSetting: TransactionInputSetting {
        selectedType == expenseSetting.typeName ? expenseSetting : incomeSetting
    }

    // MARK: - 初期値反映

    func applyInitialInputIfNeeded(
        initialDate: Date,
        initialType: String,
        expenseCategories: [String],
        incomeCategories: [String]
    ) {
        let alreadyApplied =
            Calendar.current.isDate(initialDate, inSameDayAs: lastAppliedInitialDate) &&
            initialType == lastAppliedInitialType

        guard !alreadyApplied else { return }

        lastAppliedInitialDate = initialDate
        lastAppliedInitialType = initialType
        date = initialDate

        if initialType == expenseSetting.typeName {
            selectedType = expenseSetting.typeName
            selectedExpenseCategory = expenseCategories.first ?? expenseSetting.defaultCategory
            selectedExpenseMethod = defaultExpenseMethod
        } else {
            selectedType = incomeSetting.typeName
            selectedIncomeCategory = incomeCategories.first ?? incomeSetting.defaultCategory
            selectedIncomeMethod = defaultIncomeMethod
        }
    }

    // MARK: - 支出 / 収入切り替え

    func changeInputType(to setting: TransactionInputSetting, categories: [String]) {
        selectedType = setting.typeName

        if setting.typeName == expenseSetting.typeName {
            selectedExpenseMethod = defaultExpenseMethod
            if !categories.isEmpty && !categories.contains(selectedExpenseCategory) {
                selectedExpenseCategory = categories.first ?? setting.defaultCategory
            }
        } else {
            selectedIncomeMethod = defaultIncomeMethod
            if !categories.isEmpty && !categories.contains(selectedIncomeCategory) {
                selectedIncomeCategory = categories.first ?? setting.defaultCategory
            }
        }
    }

    // MARK: - カテゴリー補正

    func fixSelectedCategoryIfNeeded(for typeName: String, newCategories: [String]) {
        if typeName == expenseSetting.typeName {
            guard !newCategories.isEmpty else { selectedExpenseCategory = ""; return }
            if !newCategories.contains(selectedExpenseCategory) {
                selectedExpenseCategory = newCategories[0]
            }
        } else {
            guard !newCategories.isEmpty else { selectedIncomeCategory = ""; return }
            if !newCategories.contains(selectedIncomeCategory) {
                selectedIncomeCategory = newCategories[0]
            }
        }
    }

    // MARK: - 支払い/受け取り方法補正

    func fixSelectedExpenseMethodIfNeeded(availableMethods: [String]) {
        guard !availableMethods.isEmpty else { selectedExpenseMethod = ""; return }
        if !availableMethods.contains(selectedExpenseMethod) {
            selectedExpenseMethod = availableMethods[0]
        }
    }

    func fixSelectedIncomeMethodIfNeeded(availableMethods: [String]) {
        guard !availableMethods.isEmpty else { selectedIncomeMethod = ""; return }
        if !availableMethods.contains(selectedIncomeMethod) {
            selectedIncomeMethod = availableMethods[0]
        }
    }

    // MARK: - 写真追加（バックグラウンドで処理してメインスレッドで反映）

    func addPhoto(_ image: UIImage) {
        isAddingPhoto = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let photo = MemoPhoto.make(from: image)
            DispatchQueue.main.async {
                if let photo { self?.memoPhotos.append(photo) }
                self?.isAddingPhoto = false
            }
        }
    }

    // MARK: - 写真パス解決（保存時に imageData をディスクに書き込みパスを返す）

    func resolveImagePaths() -> [String] {
        memoPhotos.compactMap { ReceiptImageHelper.save($0.imageData) }
    }

    // MARK: - 保存処理

    /// 保存失敗時にユーザーへ表示するメッセージ。nilなら直近の保存は失敗していない。
    /// 【重要】保存に失敗した場合（帳簿が解決できない・Core Dataへの永続化が実際に失敗した等）、
    /// この関数は`resetInput`を呼ばない＝入力内容を一切消さない。ユーザーは画面に残った
    /// 内容のまま、もう一度保存をやり直せる。
    @Published private(set) var lastSaveErrorMessage: String?

    func clearSaveError() {
        lastSaveErrorMessage = nil
    }

    /// 振替保存（InputView.saveTransfer、ExpenseData/IncomeDataのような
    /// TransactionRepository経由ではなくInputView側で直接TransferDataSync.insertCheckedを
    /// 呼ぶ構造のため）等、このViewModel自身のsaveNewTransaction以外の保存経路からも
    /// 同じアラートでユーザーへ知らせるための汎用口。
    func reportSaveError(_ message: String) {
        lastSaveErrorMessage = message
    }

    /// - Parameter bookId: 保存先の帳簿。nilの場合（帳簿が1件も無い・CloudKit初回同期待ち等で
    ///   解決できなかった場合）は、Core Dataへの保存を一切試みず`.noBookAvailable`として
    ///   失敗扱いにする（以前は呼び出し元でこのケースをガードし、保存ボタンが無言で
    ///   何もしないだけだった。入力内容が消えないこと自体はこの関数の性質上元々守られて
    ///   いたが、ユーザーには「保存できていない」ことが一切伝わらなかった）。
    @discardableResult
    func saveNewTransaction(
        expenseCategories: [String],
        bankAccountId: UUID? = nil,
        bookId: UUID?
    ) -> Bool {
        guard let bookId else {
            lastSaveErrorMessage = TransactionSaveError.noBookAvailable.errorDescription
            return false
        }

        let method = selectedType == expenseSetting.typeName ? selectedExpenseMethod : selectedIncomeMethod
        let category = selectedType == expenseSetting.typeName ? selectedExpenseCategory : selectedIncomeCategory

        do {
            let resolvedPaths = resolveImagePaths()

            let draft = try formService.makeDraft(
                selectedType: selectedType,
                amountText: amountText,
                date: date,
                selectedMethod: method,
                selectedCategory: category,
                memo: memo,
                bankAccountId: bankAccountId,
                receiptImagePaths: resolvedPaths,
                bookId: bookId
            )

            try transactionRepository.insertNewTransaction(
                draft: draft,
                expenseTypeName: expenseSetting.typeName
            )

            lastSaveErrorMessage = nil
            resetInput(expenseCategories: expenseCategories)
            return true
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

    // MARK: - リセット

    private func resetInput(expenseCategories: [String]) {
        amountText = ""
        memo = ""
        memoPhotos = []
        // selectedType は変更しない（支出↔収入の状態を保持）
        selectedExpenseCategory = expenseCategories.first ?? expenseSetting.defaultCategory
        selectedIncomeCategory = incomeSetting.defaultCategory
        // 支払い/受取方法・日付はセッション内で維持（タブ切り替え時はViewが再生成されるためリセット済み）
    }

    // MARK: - タブ再タップ時の初期表示リセット

    func resetToInitialState() {
        selectedType = expenseSetting.typeName
        date = Date()
        amountText = ""
        memo = ""
        memoPhotos = []
        selectedExpenseCategory = ""
        selectedIncomeCategory = ""
    }
}
