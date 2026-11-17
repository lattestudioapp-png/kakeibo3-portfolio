// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class AnalysisTargetFilterQARegressionTests: QARegressionTestCase {
    private let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    private func currentMonthRange() -> AnalysisDateRange {
        AnalysisDateRangeCalculator.current(for: .month, referenceDate: referenceDate)
    }

    // MARK: - 集計対象データの存在確認

    func testExpenseAndIncomeCategoryFilterDataCanBeBuilt() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let expenseCategories = CategoryDataSync.fetchAll()
            .filter { $0.bookId == main.book.id && $0.type == "支出" }
        let incomeCategories = CategoryDataSync.fetchAll()
            .filter { $0.bookId == main.book.id && $0.type == "収入" }

        XCTAssertFalse(expenseCategories.isEmpty)
        XCTAssertFalse(incomeCategories.isEmpty)
        XCTAssertTrue(expenseCategories.allSatisfy { $0.type == "支出" })
        XCTAssertTrue(incomeCategories.allSatisfy { $0.type == "収入" })
    }

    func testCurrentBookCategoriesOnlyAppearAsFilterCandidates() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allCategories = CategoryDataSync.fetchAll()
        let mainExpenseCandidates = allCategories.filter { $0.bookId == main.book.id && $0.type == "支出" }
        XCTAssertFalse(mainExpenseCandidates.contains { $0.id == business.expenseCategory.id })
    }

    // MARK: - フィルタ適用で支出テーブル・円グラフが絞られる

    func testApplyingExpenseCategoryFilterNarrowsResults() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let repository = SwiftDataCategoryRepository()
        try repository.addCategory(name: "娯楽", type: "支出", existingCategories: [], bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, date: referenceDate, paymentMethod: "現金", category: "娯楽", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let allCategories = CategoryDataSync.fetchAll().filter { $0.bookId == main.book.id }
        let range = currentMonthRange()

        let viewModel = AnalysisViewModel()
        viewModel.rebuildExpenseIncome(
            allExpenses: allExpenses, allIncomes: [], allTransfers: [], categories: allCategories,
            paymentMethods: [], bankAccounts: [],
            dateRange: range, prevDateRange: range, periodType: .month, monthlySnapshots: [],
            expenseCategoryFilter: Set(["食費"])
        )

        XCTAssertEqual(viewModel.expenseCategoryItems.map(\.categoryName), ["食費"])
        XCTAssertEqual(viewModel.expenseTotal, 100)
    }

    func testApplyingIncomeCategoryFilterNarrowsResults() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let repository = SwiftDataCategoryRepository()
        try repository.addCategory(name: "副業", type: "収入", existingCategories: [], bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 250000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 10000, date: referenceDate, receiveMethod: "現金", category: "副業", bookId: main.book.id)

        let allIncomes = IncomeDataSync.fetchAll(bookId: main.book.id)
        let allCategories = CategoryDataSync.fetchAll().filter { $0.bookId == main.book.id }
        let range = currentMonthRange()

        let viewModel = AnalysisViewModel()
        viewModel.rebuildExpenseIncome(
            allExpenses: [], allIncomes: allIncomes, allTransfers: [], categories: allCategories,
            paymentMethods: [], bankAccounts: [],
            dateRange: range, prevDateRange: range, periodType: .month, monthlySnapshots: [],
            incomeCategoryFilter: Set(["副業"])
        )

        XCTAssertEqual(viewModel.incomeCategoryItems.map(\.categoryName), ["副業"])
        XCTAssertEqual(viewModel.incomeTotal, 10000)
    }

    // MARK: - フィルタを「すべて」に戻す

    func testResettingFilterToNilShowsAllCategories() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let allCategories = CategoryDataSync.fetchAll().filter { $0.bookId == main.book.id }
        let range = currentMonthRange()

        let viewModel = AnalysisViewModel()
        viewModel.rebuildExpenseIncome(
            allExpenses: allExpenses, allIncomes: [], allTransfers: [], categories: allCategories,
            paymentMethods: [], bankAccounts: [],
            dateRange: range, prevDateRange: range, periodType: .month, monthlySnapshots: [],
            usesLiveAggregation: true, // スナップショット未構築のためライブ集計を強制する
            expenseCategoryFilter: nil // 「すべて」
        )

        XCTAssertEqual(viewModel.expenseTotal, 100)
    }

    // MARK: - 保存された選択状態が bookId + 収支種別ごとに分かれる

    func testFilterSelectionIsSavedPerBookAndTransactionType() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        AnalysisCategoryFilterSettings.save(Set(["食費"]), bookId: main.book.id, categoryType: "支出")
        AnalysisCategoryFilterSettings.save(Set(["給料"]), bookId: main.book.id, categoryType: "収入")
        AnalysisCategoryFilterSettings.save(Set(["娯楽"]), bookId: business.book.id, categoryType: "支出")

        XCTAssertEqual(AnalysisCategoryFilterSettings.load(bookId: main.book.id, categoryType: "支出"), Set(["食費"]))
        XCTAssertEqual(AnalysisCategoryFilterSettings.load(bookId: main.book.id, categoryType: "収入"), Set(["給料"]))
        XCTAssertEqual(AnalysisCategoryFilterSettings.load(bookId: business.book.id, categoryType: "支出"), Set(["娯楽"]))
        // 別帳簿の選択状態が混ざっていない
        XCTAssertNotEqual(
            AnalysisCategoryFilterSettings.load(bookId: main.book.id, categoryType: "支出"),
            AnalysisCategoryFilterSettings.load(bookId: business.book.id, categoryType: "支出")
        )
    }

    func testNoSavedFilterMeansAllCategoriesShown() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let loaded = AnalysisCategoryFilterSettings.load(bookId: main.book.id, categoryType: "支出")
        XCTAssertNil(loaded) // nil = 絞り込みなし = すべて対象
    }

    func testSwitchingBookDoesNotMixFilterSelection() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        AnalysisCategoryFilterSettings.save(Set(["食費"]), bookId: main.book.id, categoryType: "支出")
        // 事業用帳簿に切り替えた直後は、事業用帳簿用のキーがまだ無いのでnil(すべて)のはず
        XCTAssertNil(AnalysisCategoryFilterSettings.load(bookId: business.book.id, categoryType: "支出"))
    }
}
