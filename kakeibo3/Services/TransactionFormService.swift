import Foundation

// MARK: - 入力フォーム検証Service

/**
 入力フォームの文字列を、保存できる形に変換するService。
 ViewModelは画面状態を持ち、このServiceは検証と変換だけを担当する。
 */
struct TransactionFormService {
    enum ValidationError: Error {
        case invalidAmount
        case emptyCategory
    }

    func makeDraft(
        selectedType: String,
        amountText: String,
        date: Date,
        selectedMethod: String,
        selectedCategory: String,
        memo: String,
        bankAccountId: UUID? = nil,
        receiptImagePaths: [String] = [],
        bookId: UUID
    ) throws -> TransactionDraft {
        let calculator = ExpressionCalculator()

        let amount: Int

        do {
            amount = try calculator.calculate(amountText)
        } catch {
            throw ValidationError.invalidAmount
        }

        guard amount > 0 else {
            throw ValidationError.invalidAmount
        }

        guard !selectedCategory.isEmpty else {
            throw ValidationError.emptyCategory
        }

        return TransactionDraft(
            type: selectedType,
            amount: amount,
            date: date,
            method: selectedMethod,
            category: selectedCategory,
            memo: memo,
            bankAccountId: bankAccountId,
            receiptImagePaths: receiptImagePaths,
            bookId: bookId
        )
    }
}
