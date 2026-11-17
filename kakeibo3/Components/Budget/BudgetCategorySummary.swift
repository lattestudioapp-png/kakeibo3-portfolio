import SwiftUI

enum BudgetSource {
    case monthly
    case recurring
}

struct BudgetCategorySummary: Identifiable {
    let id: String
    let categoryName: String
    let color: Color
    let budgetAmount: Int?
    let usedAmount: Int
    let budgetSource: BudgetSource?

    init(
        id: String,
        categoryName: String,
        color: Color,
        budgetAmount: Int?,
        usedAmount: Int,
        budgetSource: BudgetSource? = nil
    ) {
        self.id = id
        self.categoryName = categoryName
        self.color = color
        self.budgetAmount = budgetAmount
        self.usedAmount = usedAmount
        self.budgetSource = budgetSource
    }

    var remainingAmount: Int? {
        guard let b = budgetAmount else { return nil }
        return b - usedAmount
    }
    var usageRate: Int? {
        guard let b = budgetAmount, b > 0 else { return nil }
        return Int(Double(usedAmount) / Double(b) * 100)
    }
    var isOverBudget: Bool {
        guard let b = budgetAmount else { return false }
        return usedAmount > b
    }
    var isBudgetSet: Bool { budgetAmount != nil }
    var usageRatio: Double {
        guard let b = budgetAmount, b > 0 else { return 0 }
        return min(1.0, Double(usedAmount) / Double(b))
    }
}

struct BudgetMonthSummary {
    let totalBudgetAmount: Int
    let totalUsedAmount: Int
    let categorySummaries: [BudgetCategorySummary]
    let unsetCategorySummaries: [BudgetCategorySummary]

    var remainingAmount: Int { totalBudgetAmount - totalUsedAmount }
    var usageRate: Int? {
        guard totalBudgetAmount > 0 else { return nil }
        return Int(Double(totalUsedAmount) / Double(totalBudgetAmount) * 100)
    }
    var isOverBudget: Bool {
        totalBudgetAmount > 0 && totalUsedAmount > totalBudgetAmount
    }
    var isBudgetSet: Bool { totalBudgetAmount > 0 }
    var usageRatio: Double {
        guard totalBudgetAmount > 0 else { return 0 }
        return min(1.0, Double(totalUsedAmount) / Double(totalBudgetAmount))
    }
}
