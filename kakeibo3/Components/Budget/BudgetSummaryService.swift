import SwiftUI

struct BudgetSummaryService {

    /// year/month は「会計期間ラベル」（BudgetData/RecurringBudgetDataのyear/month列と同じ意味）。
    /// 実際の集計期間（開始日〜終了日）は、月の開始日設定を反映してAccountingMonthCalculatorで
    /// 都度計算する（ラベル→anchorへ逆引きしてから期間を求める。通常はlabel==anchor）。
    static func buildMonthSummary(
        allExpenses: [ExpenseData],
        allBudgets: [BudgetData],
        allRecurringBudgets: [RecurringBudgetData],
        allCategories: [CategoryData],
        year: Int,
        month: Int
    ) -> BudgetMonthSummary {
        let anchor = AccountingMonthCalculator.anchor(forLabelYear: year, labelMonth: month)
        guard let range = AccountingMonthCalculator.range(anchorYear: anchor.year, anchorMonth: anchor.month) else {
            return BudgetMonthSummary(
                totalBudgetAmount: 0, totalUsedAmount: 0,
                categorySummaries: [], unsetCategorySummaries: []
            )
        }
        let start = range.actualStartDate
        let end = range.actualEndDate

        let thisMonthExpenses = allExpenses.filter { $0.date >= start && $0.date < end }
        let thisMonthBudgets = allBudgets.filter { $0.year == year && $0.month == month }

        var expensesByCategory: [String: Int] = [:]
        for expense in thisMonthExpenses {
            expensesByCategory[expense.category, default: 0] += expense.amount
        }

        // Resolution: BudgetData (monthly) > RecurringBudgetData (recurring) > nil
        var budgetByCategory: [String: (amount: Int, source: BudgetSource)] = [:]
        for budget in thisMonthBudgets {
            budgetByCategory[budget.categoryName] = (budget.amount, .monthly)
        }
        for recurring in allRecurringBudgets where recurring.isEnabled && recurring.amount > 0 {
            if budgetByCategory[recurring.categoryName] == nil {
                budgetByCategory[recurring.categoryName] = (recurring.amount, .recurring)
            }
        }

        var setBudgets: [BudgetCategorySummary] = []
        var unsetBudgets: [BudgetCategorySummary] = []
        var processedNames = Set<String>()

        let sortedCats = allCategories
            .filter { $0.type == "支出" }
            .sorted { $0.sortOrder < $1.sortOrder }

        for cat in sortedCats {
            processedNames.insert(cat.name)
            let used = expensesByCategory[cat.name] ?? 0
            let entry = budgetByCategory[cat.name]
            guard entry != nil || used > 0 else { continue }
            let item = BudgetCategorySummary(
                id: cat.name,
                categoryName: cat.name,
                color: categoryColor(for: cat.name, type: "支出", categories: allCategories),
                budgetAmount: entry?.amount,
                usedAmount: used,
                budgetSource: entry?.source
            )
            if entry != nil { setBudgets.append(item) } else { unsetBudgets.append(item) }
        }

        for (catName, used) in expensesByCategory.sorted(by: { $0.key < $1.key })
        where !processedNames.contains(catName) {
            let entry = budgetByCategory[catName]
            let item = BudgetCategorySummary(
                id: catName,
                categoryName: catName,
                color: categoryColor(for: catName, type: "支出", categories: allCategories),
                budgetAmount: entry?.amount,
                usedAmount: used,
                budgetSource: entry?.source
            )
            if entry != nil { setBudgets.append(item) } else { unsetBudgets.append(item) }
        }

        let totalBudget = setBudgets.reduce(0) { $0 + ($1.budgetAmount ?? 0) }
        let totalUsed = thisMonthExpenses.reduce(0) { $0 + $1.amount }
        return BudgetMonthSummary(
            totalBudgetAmount: totalBudget,
            totalUsedAmount: totalUsed,
            categorySummaries: setBudgets,
            unsetCategorySummaries: unsetBudgets
        )
    }

    private static func categoryColor(for name: String, type: String, categories: [CategoryData]) -> Color {
        let hex = categories.first { $0.name == name && $0.type == type }?.colorHex ?? ""
        let normalized = CategoryColorPalette.normalize(hex)
        let safe = (normalized == "#" || normalized.isEmpty) ? "#CFCFCF" : normalized
        return ColorHexConverter.color(from: safe)
    }
}
