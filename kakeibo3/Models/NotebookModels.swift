import SwiftUI

// MARK: - 家計簿ノート 用紙サイズ

enum NotebookPaperSize: String, CaseIterable, Identifiable {
    case a4
    case a5
    case b5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a4: return "A4"
        case .a5: return "A5"
        case .b5: return "B5"
        }
    }

    // ポイント単位（72pt = 1inch）のページサイズ
    var size: CGSize {
        switch self {
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .a5: return CGSize(width: 419.53, height: 595.28)
        case .b5: return CGSize(width: 515.91, height: 728.50)
        }
    }
}

// MARK: - 家計簿ノート デザイン

enum NotebookDesignStyle: String, CaseIterable, Identifiable {
    case simple
    case themeColor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simple: return "シンプル"
        case .themeColor: return "テーマカラー"
        }
    }
}

// MARK: - 家計簿ノート 作成するページ

enum NotebookPageKind: String, CaseIterable, Identifiable {
    case monthlySummary
    case categoryBreakdown
    case dailyDetail
    case reflection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlySummary: return "収支まとめ"
        case .categoryBreakdown: return "カテゴリー別支出"
        case .dailyDetail: return "日別明細"
        case .reflection: return "振り返り欄"
        }
    }
}

// MARK: - 振り返り欄テキスト（保存はせず、作成時にその場で入力する）

struct NotebookReflectionText {
    var goodThings: String = ""
    var overspent: String = ""
    var nextMonthCaution: String = ""
    var freeMemo: String = ""
}

// MARK: - カテゴリー別支出（1カテゴリー分）

struct NotebookCategorySummary: Identifiable {
    var id: String { categoryName }
    let categoryName: String
    let amount: Int
    let percentage: Double // 0...1
    let colorHex: String
}

// MARK: - 日別明細（1行分）

struct NotebookDailyEntry: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let memo: String
    let amount: Int
    let isExpense: Bool
}

// MARK: - 家計簿ノート 集計データ

struct BudgetNotebookData {
    let totalIncome: Int
    let totalExpense: Int
    let totalBudgetAmount: Int // 0 = 予算未設定
    let categories: [NotebookCategorySummary]
    let dailyEntries: [NotebookDailyEntry] // 日付昇順

    var balance: Int { totalIncome - totalExpense }
    var remainingBudget: Int { totalBudgetAmount - totalExpense }
}
