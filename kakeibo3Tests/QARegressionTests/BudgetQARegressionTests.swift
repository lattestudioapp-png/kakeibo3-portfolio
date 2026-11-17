// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class BudgetQARegressionTests: QARegressionTestCase {
    private let year = 2026
    private let month = 7
    private var referenceDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 15))!
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: AccountingMonthSettings.startDayStorageKey)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 帳簿スコープ

    func testBudgetIsScopedToCurrentBookOnly() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var mainBudget = BudgetData(year: year, month: month, categoryName: "食費", amount: 30000)
        mainBudget.bookId = main.book.id
        var businessBudget = BudgetData(year: year, month: month, categoryName: "食費", amount: 99999)
        businessBudget.bookId = business.book.id
        BudgetDataSync.insert(mainBudget)
        BudgetDataSync.insert(businessBudget)

        let allBudgets = BudgetDataSync.fetchAll()
        let mainOnly = allBudgets.filter { $0.bookId == main.book.id }
        XCTAssertEqual(mainOnly.count, 1)
        XCTAssertEqual(mainOnly.first?.amount, 30000)
    }

    // MARK: - 追加/編集/削除

    func testCanAddBudget() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 30000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)

        XCTAssertEqual(BudgetDataSync.fetchAll().count, 1)
    }

    func testCanEditBudget() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 30000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)

        budget.amount = 40000
        BudgetDataSync.update(budget)

        XCTAssertEqual(BudgetDataSync.fetchAll().first?.amount, 40000)
    }

    func testCanDeleteBudget() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 30000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)

        BudgetDataSync.delete(id: budget.id)

        XCTAssertTrue(BudgetDataSync.fetchAll().isEmpty)
    }

    func testSameCategoryBudgetDoesNotMixAcrossBooks() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var mainBudget = BudgetData(year: year, month: month, categoryName: "食費", amount: 10000)
        mainBudget.bookId = main.book.id
        var businessBudget = BudgetData(year: year, month: month, categoryName: "食費", amount: 50000)
        businessBudget.bookId = business.book.id
        BudgetDataSync.insert(mainBudget)
        BudgetDataSync.insert(businessBudget)

        let allExpenses = [
            QARegressionTestFactory.makeExpense(amount: 3000, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id),
        ]

        let allBudgets = BudgetDataSync.fetchAll()
        let allCategories = CategoryDataSync.fetchAll()

        let mainSummary = BudgetSummaryService.buildMonthSummary(
            allExpenses: allExpenses.filter { $0.bookId == main.book.id },
            allBudgets: allBudgets.filter { $0.bookId == main.book.id },
            allRecurringBudgets: [],
            allCategories: allCategories.filter { $0.bookId == main.book.id },
            year: year, month: month
        )
        let mainFood = mainSummary.categorySummaries.first { $0.categoryName == "食費" }
        XCTAssertEqual(mainFood?.budgetAmount, 10000)
        XCTAssertEqual(mainFood?.usedAmount, 3000)
    }

    // MARK: - 支出実績・消化率・残り金額

    func testUsageRateAndRemainingAmountAreCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 10000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)

        let expense = QARegressionTestFactory.makeExpense(amount: 4000, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [expense], allBudgets: [budget], allRecurringBudgets: [], allCategories: allCategories,
            year: year, month: month
        )

        let food = summary.categorySummaries.first { $0.categoryName == "食費" }
        XCTAssertEqual(food?.usageRate, 40) // 4000/10000 = 40%
        XCTAssertEqual(food?.remainingAmount, 6000)
        XCTAssertFalse(food?.isOverBudget ?? true)
    }

    func testOverBudgetIsDetected() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 1000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)
        let expense = QARegressionTestFactory.makeExpense(amount: 1500, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [expense], allBudgets: [budget], allRecurringBudgets: [], allCategories: allCategories,
            year: year, month: month
        )
        let food = summary.categorySummaries.first { $0.categoryName == "食費" }
        XCTAssertTrue(food?.isOverBudget ?? false)
        XCTAssertEqual(food?.remainingAmount, -500)
    }

    func testUnsetCategoryShowsSpendWithoutBudget() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let expense = QARegressionTestFactory.makeExpense(amount: 800, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [expense], allBudgets: [], allRecurringBudgets: [], allCategories: allCategories,
            year: year, month: month
        )
        let unset = summary.unsetCategorySummaries.first { $0.categoryName == "食費" }
        XCTAssertNotNil(unset)
        XCTAssertFalse(unset?.isBudgetSet ?? true)
        XCTAssertEqual(unset?.usedAmount, 800)
    }

    // MARK: - 定期予算(RecurringBudgetData)の反映

    func testRecurringBudgetIsUsedWhenNoMonthlyBudgetExists() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var recurringBudget = RecurringBudgetData(categoryName: "食費", amount: 20000)
        recurringBudget.bookId = main.book.id
        RecurringBudgetDataSync.insert(recurringBudget)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [], allBudgets: [], allRecurringBudgets: [recurringBudget], allCategories: allCategories,
            year: year, month: month
        )
        let food = summary.categorySummaries.first { $0.categoryName == "食費" }
        XCTAssertEqual(food?.budgetAmount, 20000)
        XCTAssertEqual(food?.budgetSource, .recurring)
    }

    func testMonthlyBudgetTakesPriorityOverRecurringBudget() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var recurringBudget = RecurringBudgetData(categoryName: "食費", amount: 20000)
        recurringBudget.bookId = main.book.id
        var monthlyBudget = BudgetData(year: year, month: month, categoryName: "食費", amount: 15000)
        monthlyBudget.bookId = main.book.id
        RecurringBudgetDataSync.insert(recurringBudget)
        BudgetDataSync.insert(monthlyBudget)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [], allBudgets: [monthlyBudget], allRecurringBudgets: [recurringBudget], allCategories: allCategories,
            year: year, month: month
        )
        let food = summary.categorySummaries.first { $0.categoryName == "食費" }
        XCTAssertEqual(food?.budgetAmount, 15000)
        XCTAssertEqual(food?.budgetSource, .monthly)
    }

    // MARK: - 月開始日設定の反映

    func testAccountingMonthStartDayAffectsBudgetPeriod() throws {
        UserDefaults.standard.set(10, forKey: AccountingMonthSettings.startDayStorageKey)

        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 10000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)

        // 7/5は開始日=10の設定では「6月分」の会計期間に属する
        let earlyJulyDate = Calendar.current.date(from: DateComponents(year: year, month: 7, day: 5))!
        let expenseBeforeBoundary = QARegressionTestFactory.makeExpense(amount: 999, date: earlyJulyDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [expenseBeforeBoundary], allBudgets: [budget], allRecurringBudgets: [], allCategories: allCategories,
            year: year, month: month
        )
        let food = summary.categorySummaries.first { $0.categoryName == "食費" }
        // 7/5の支出は「7月分（開始日=10日=7/10〜8/9）」には含まれない
        XCTAssertEqual(food?.usedAmount, 0)
    }

    // MARK: - 使用停止カテゴリーでも過去実績には影響しない

    func testSuspendedCategoryStillCountsInPastBudgetUsage() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var budget = BudgetData(year: year, month: month, categoryName: "食費", amount: 10000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)
        let expense = QARegressionTestFactory.makeExpense(amount: 2000, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: [expense], allBudgets: [budget], allRecurringBudgets: [], allCategories: allCategories,
            year: year, month: month
        )
        let food = summary.categorySummaries.first { $0.categoryName == "食費" }
        XCTAssertEqual(food?.usedAmount, 2000)
    }
}
