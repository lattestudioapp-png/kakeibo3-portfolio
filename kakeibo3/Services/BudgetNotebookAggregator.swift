import Foundation

// MARK: - 家計簿ノート用データ集計
//
// 指定した期間の支出・収入から、印刷用ページに必要な集計値をまとめて作る。
// 予算はカテゴリーごとに「年月」単位で設定されるため、年月モードのときだけ
// budgetYear/budgetMonth を渡して集計する（期間モードでは nil を渡し、予算は集計しない）。
// 予算の解決順序（月間指定 > 定期予算）は BudgetSummaryService と合わせている。

struct BudgetNotebookAggregator {

    static func build(
        start: Date,
        end: Date, // 排他的な上限（この日時より前のデータを対象にする）
        budgetYear: Int?,
        budgetMonth: Int?,
        allExpenses: [ExpenseData],
        allIncomes: [IncomeData],
        allBudgets: [BudgetData],
        allRecurringBudgets: [RecurringBudgetData],
        allCategories: [CategoryData]
    ) -> BudgetNotebookData {
        let targetExpenses = allExpenses.filter { $0.date >= start && $0.date < end }
        let targetIncomes = allIncomes.filter { $0.date >= start && $0.date < end }

        let totalExpense = targetExpenses.reduce(0) { $0 + $1.amount }
        let totalIncome = targetIncomes.reduce(0) { $0 + $1.amount }

        // 予算（カテゴリー別に設定された予算の合計。年月モードのときのみ）
        var totalBudget = 0
        if let budgetYear, let budgetMonth {
            let monthBudgets = allBudgets.filter { $0.year == budgetYear && $0.month == budgetMonth }
            var budgetByCategory: [String: Int] = [:]
            for budget in monthBudgets {
                budgetByCategory[budget.categoryName] = budget.amount
            }
            for recurring in allRecurringBudgets where recurring.isEnabled && recurring.amount > 0 {
                if budgetByCategory[recurring.categoryName] == nil {
                    budgetByCategory[recurring.categoryName] = recurring.amount
                }
            }
            totalBudget = budgetByCategory.values.reduce(0, +)
        }

        // カテゴリー別支出（金額の多い順）
        var amountByCategory: [String: Int] = [:]
        for expense in targetExpenses {
            amountByCategory[expense.category, default: 0] += expense.amount
        }
        let categorySummaries: [NotebookCategorySummary] = amountByCategory
            .sorted { $0.value > $1.value }
            .map { name, amount in
                let hex = allCategories.first { $0.name == name && $0.type == "支出" }?.colorHex ?? ""
                let normalized = CategoryColorPalette.normalize(hex)
                let safeHex = (normalized.isEmpty || normalized == "#") ? "#CFCFCF" : normalized
                let percentage = totalExpense > 0 ? Double(amount) / Double(totalExpense) : 0
                return NotebookCategorySummary(
                    categoryName: name, amount: amount, percentage: percentage, colorHex: safeHex
                )
            }

        // 日別明細（支出・収入をまとめて日付昇順）
        var entries: [NotebookDailyEntry] = targetExpenses.map {
            NotebookDailyEntry(date: $0.date, category: $0.category, memo: $0.memo, amount: $0.amount, isExpense: true)
        }
        entries.append(contentsOf: targetIncomes.map {
            NotebookDailyEntry(date: $0.date, category: $0.category, memo: $0.memo, amount: $0.amount, isExpense: false)
        })
        entries.sort { $0.date < $1.date }

        return BudgetNotebookData(
            totalIncome: totalIncome, totalExpense: totalExpense,
            totalBudgetAmount: totalBudget,
            categories: categorySummaries,
            dailyEntries: entries
        )
    }
}
