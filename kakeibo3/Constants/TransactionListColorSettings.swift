import SwiftUI

// MARK: - 取引リスト行の背景色オプション

enum TransactionListRowColorOption: String, CaseIterable {
    case lightRed
    case lightBlue
    case white

    var color: Color {
        switch self {
        case .lightRed:
            return Color(red: 1.00, green: 0.94, blue: 0.94)
        case .lightBlue:
            return Color(red: 0.93, green: 0.98, blue: 1.00)
        case .white:
            return Color.white
        }
    }

    var displayName: String {
        switch self {
        case .lightRed:  return "薄い赤"
        case .lightBlue: return "薄い青"
        case .white:     return "白"
        }
    }
}

// MARK: - 取引リスト行の背景色設定（テーマカラーとは別管理）

enum TransactionListColorSettings {
    static let expenseRowColorStorageKey = "expenseListRowColorOption"
    static let incomeRowColorStorageKey  = "incomeListRowColorOption"

    static let defaultExpenseRowColor: TransactionListRowColorOption = .lightRed
    static let defaultIncomeRowColor:  TransactionListRowColorOption = .lightBlue
}
