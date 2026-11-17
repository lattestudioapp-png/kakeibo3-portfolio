// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class AnalysisQARegressionTests: QARegressionTestCase {
    private let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    private func snapshot(bookId: UUID, yearMonth: String = "2026-07") -> AnalysisMonthlySnapshot? {
        AnalysisMonthlySnapshotSync.fetchAll().first { $0.bookId == bookId && $0.yearMonth == yearMonth }
    }

    // MARK: - 支出集計の帳簿分離

    func testAnalysisOnlyAggregatesCurrentBookExpenses() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 500, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 9999, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        AnalysisSnapshotManager.rebuildAll()

        let mainSnapshot = try snapshot(bookId: main.book.id)
        XCTAssertEqual(mainSnapshot?.displayExpenseTotal, 500)
    }

    func testSameNameCategoryDoesNotMixInExpenseBreakdown() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 300, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 700, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        AnalysisSnapshotManager.rebuildAll()

        let mainFood = try snapshot(bookId: main.book.id)?.expenseCategoryTotals.first { $0.categoryName == "食費" }
        XCTAssertEqual(mainFood?.amount, 300)
    }

    func testExpenseTotalIsCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        AnalysisSnapshotManager.rebuildAll()
        XCTAssertEqual(try snapshot(bookId: main.book.id)?.displayExpenseTotal, 300)
    }

    func testUnusedCategoryIsNotInExpenseBreakdown() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let repository = SwiftDataCategoryRepository()
        try repository.addCategory(name: "娯楽", type: "支出", existingCategories: [], bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        AnalysisSnapshotManager.rebuildAll()
        let breakdown = try snapshot(bookId: main.book.id)?.expenseCategoryTotals ?? []
        XCTAssertFalse(breakdown.contains { $0.categoryName == "娯楽" })
    }

    func testAggregationDoesNotCrashAfterCategorySuspension() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        AnalysisSnapshotManager.rebuildAll()
        // 使用停止中でも過去の支出は普通に集計される
        XCTAssertEqual(try snapshot(bookId: main.book.id)?.displayExpenseTotal, 100)
    }

    // MARK: - 収入集計の帳簿分離

    func testAnalysisOnlyAggregatesCurrentBookIncomes() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeIncome(amount: 250000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 9999, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: business.book.id)

        AnalysisSnapshotManager.rebuildAll()
        XCTAssertEqual(try snapshot(bookId: main.book.id)?.displayIncomeTotal, 250000)
    }

    func testSameNameIncomeCategoryDoesNotMix() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeIncome(amount: 1000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 2000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: business.book.id)

        AnalysisSnapshotManager.rebuildAll()
        let mainSalary = try snapshot(bookId: main.book.id)?.incomeCategoryTotals.first { $0.categoryName == "給料" }
        XCTAssertEqual(mainSalary?.amount, 1000)
    }

    func testIncomeTotalIsCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeIncome(amount: 100000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        AnalysisSnapshotManager.rebuildAll()
        XCTAssertEqual(try snapshot(bookId: main.book.id)?.displayIncomeTotal, 100000)
    }

    // MARK: - クレジットカードの帳簿分離

    func testOnlyCurrentBookCreditCardsAreConsidered() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allMethods = PaymentMethodSettingDataSync.fetchAll()
        let mainCards = allMethods.filter { $0.bookId == main.book.id && $0.type == PaymentMethodType.creditCard.rawValue }
        XCTAssertEqual(mainCards.count, 1)
        XCTAssertFalse(mainCards.contains { $0.id == business.creditCard.id })
    }

    func testCreditCardExpenseIsReflectedInWithdrawalTiming() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 5000, date: referenceDate, paymentMethod: "テストカード", category: "食費", bookId: main.book.id)

        AnalysisSnapshotManager.rebuildAll()
        let snap = try snapshot(bookId: main.book.id)
        XCTAssertEqual(snap?.creditCardExpenseTotal, 5000)
        // 引き落とし日反映モードでは資産用expenseTotalからクレカ分を除外するため、
        // 支出5000円すべてがクレカ利用でも資産純増減は0円になる
        XCTAssertEqual(snap?.assetNetTotal(assetReflectionTiming: .withdrawalDate), 0)
    }
}
