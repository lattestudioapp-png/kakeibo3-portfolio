import SwiftUI

struct MonthlySavingsSummary: Identifiable {
    let id: String
    let year: Int
    let month: Int
    let incomeTotal: Int
    let expenseTotal: Int
    let savingsAmount: Int
    let previousMonthSavingsAmount: Int?
    let monthOverMonthDiff: Int?

    var shortMonthLabel: String { "\(month)月" }
    var fullMonthLabel: String { String(format: "%02d月", month) }
    var hasData: Bool { incomeTotal > 0 || expenseTotal > 0 }
}

struct AnalysisCategorySummary: Identifiable {
    let id: String          // カテゴリー名をIDとして使用（再描画で変わらない）
    let categoryName: String
    let color: Color
    let totalAmount: Int
    let percentage: Double
    let monthOverMonthDiff: Int?
}

private let _analysisNumberFormatter: NumberFormatter = {
    let f = NumberFormatter(); f.numberStyle = .decimal; return f
}()

func formatAnalysisAmount(_ amount: Int) -> String {
    (_analysisNumberFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)") + "円"
}

func formatAnalysisDiff(_ diff: Int) -> String {
    let absVal = Swift.abs(diff)
    let absStr = (_analysisNumberFormatter.string(from: NSNumber(value: absVal)) ?? "\(absVal)") + "円"
    return diff >= 0 ? "+\(absStr)" : "-\(absStr)"
}

func analysisMomColor(diff: Int) -> Color {
    if diff > 0 { return AppColors.incomeColor }
    if diff < 0 { return AppColors.expenseColor }
    return Color.gray.opacity(0.55)
}
