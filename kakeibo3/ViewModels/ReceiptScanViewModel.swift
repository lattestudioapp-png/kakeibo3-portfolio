import SwiftUI
import Combine

// MARK: - レシート撮影〜保存までを統括するViewModel
//
// 撮影/選択→OCR→パース→カテゴリー提案→ドラフト作成→保存、の一連の処理をここに集約する。
// 既存の支出保存経路（TransactionRepository）はそのまま呼び出すだけで、独自の保存処理は作らない。

@MainActor
final class ReceiptScanViewModel: ObservableObject {
    enum FlowState: Equatable {
        case capture
        case preview(UIImage)
        case ocrProcessing(UIImage)
        case review
        case alreadySaved

        static func == (lhs: FlowState, rhs: FlowState) -> Bool {
            switch (lhs, rhs) {
            case (.capture, .capture), (.review, .review), (.alreadySaved, .alreadySaved):
                return true
            case let (.preview(a), .preview(b)): return a === b
            case let (.ocrProcessing(a), .ocrProcessing(b)): return a === b
            default: return false
            }
        }
    }

    @Published var state: FlowState = .capture
    @Published var draft: ReceiptDraft?
    @Published var editingItemId: UUID?
    @Published var isEditingHeader = false

    private let repository: TransactionRepository = SwiftDataTransactionRepository()

    // MARK: - 撮影/選択後の遷移

    func imageCaptured(_ image: UIImage) {
        state = .preview(image)
    }

    // MARK: - OCR開始

    func startRecognition(
        image: UIImage,
        expenseCategoryNames: [String],
        storeName: String? = nil
    ) {
        if ReceiptDuplicateGuardStore.isDuplicate(image) {
            state = .alreadySaved
            return
        }

        state = .ocrProcessing(image)

        Task.detached(priority: .userInitiated) {
            let parseResult: ReceiptParseResult
            do {
                let lines = try ReceiptOCRService.recognizeLines(in: image)
                parseResult = ReceiptParsingService.parse(lines: lines)
            } catch {
                parseResult = ReceiptParseResult(
                    date: nil, storeName: nil, items: [], receiptTotal: nil,
                    subtotal: nil, taxAmount: nil, isTaxIncluded: nil, paymentMethodGuess: nil
                )
            }

            await MainActor.run {
                self.buildDraft(from: parseResult, image: image, expenseCategoryNames: expenseCategoryNames)
            }
        }
    }

    private func buildDraft(
        from result: ReceiptParseResult,
        image: UIImage,
        expenseCategoryNames: [String]
    ) {
        let storeName = result.storeName
        let items = result.items.map { parsed -> ReceiptDraftItem in
            let suggestion = ReceiptCategorySuggestionService.suggestCategory(
                productName: parsed.name,
                storeName: storeName,
                availableCategories: expenseCategoryNames
            )
            return ReceiptDraftItem(
                productName: parsed.name,
                amount: parsed.amount,
                category: suggestion,
                suggestedCategory: suggestion
            )
        }

        draft = ReceiptDraft(
            capturedImage: image,
            date: result.date,
            storeName: storeName,
            paymentMethod: result.paymentMethodGuess,
            receiptTotal: result.receiptTotal,
            taxAmount: result.taxAmount,
            isTaxIncluded: result.isTaxIncluded,
            items: items
        )
        state = .review
    }

    func retake() {
        draft = nil
        state = .capture
    }

    // MARK: - 保存

    /// チェック済みの商品を1件ずつ既存のTransactionRepository経由でExpenseDataとして保存する。
    /// 戻り値は保存件数。未設定カテゴリーの商品が含まれる場合はエラーを投げて保存しない。
    func save(
        expenseTypeName: String,
        bookId: UUID,
        bankAccounts: [BankAccountData]
    ) throws -> Int {
        guard var draft else { return 0 }

        let checkedItems = draft.items.filter(\.isIncluded)
        guard !checkedItems.isEmpty else {
            throw ReceiptSaveError.noItemsSelected
        }
        guard !checkedItems.contains(where: { $0.category == ReceiptCategorySuggestionService.unsetCategory }) else {
            throw ReceiptSaveError.unsetCategoryExists
        }
        guard let method = draft.paymentMethod, !method.isEmpty else {
            throw ReceiptSaveError.paymentMethodMissing
        }

        let date = draft.date ?? Date()
        let bankAccountId = bankAccounts.first(where: { $0.accountName == method && $0.isActive })?.id
        let imagePath = ReceiptImageHelper.save(draft.capturedImage)
        let imagePaths = imagePath.map { [$0] } ?? []

        for item in checkedItems {
            let txDraft = TransactionDraft(
                type: expenseTypeName,
                amount: item.amount,
                date: date,
                method: method,
                category: item.category,
                memo: item.productName,
                bankAccountId: bankAccountId,
                receiptImagePaths: imagePaths,
                bookId: bookId
            )
            try repository.insertNewTransaction(
                draft: txDraft,
                expenseTypeName: expenseTypeName
            )
            ReceiptCategoryLearningStore.recordCorrection(productName: item.productName, category: item.category)
        }

        ReceiptDuplicateGuardStore.markSaved(draft.capturedImage)
        self.draft = draft
        return checkedItems.count
    }
}

enum ReceiptSaveError: LocalizedError {
    case noItemsSelected
    case unsetCategoryExists
    case paymentMethodMissing

    var errorDescription: String? {
        switch self {
        case .noItemsSelected:
            return "保存する商品が選択されていません。"
        case .unsetCategoryExists:
            return "カテゴリーが未設定の商品があります。すべての商品にカテゴリーを設定してください。"
        case .paymentMethodMissing:
            return "支払い方法を設定してください。"
        }
    }
}
