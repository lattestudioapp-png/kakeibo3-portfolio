// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 注意: SearchViewModelには「金額範囲」フィルタは存在しない（キーワード検索が金額の
// 文字列部分一致にヒットするのみ）。存在しない機能のテストは書かず、実際の挙動を検証する。

import XCTest
@testable import kakeibo3

final class SearchHistoryQARegressionTests: QARegressionTestCase {
    private let repository = SwiftDataTransactionRepository()

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    private func makeSearchViewModel(bookId: UUID) throws -> SearchViewModel {
        let allIncomes = IncomeDataSync.fetchAll(bookId: bookId)
        let allExpenses = ExpenseDataSync.fetchAll(bookId: bookId)
        let viewModel = SearchViewModel()
        viewModel.startDate = nil
        viewModel.endDate = nil
        viewModel.rebuildAllItems(incomes: allIncomes, expenses: allExpenses)
        viewModel.applyFilters()
        return viewModel
    }

    // MARK: - 帳簿スコープ

    func testSearchOnlyIncludesCurrentBookTransactions() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 300, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 999, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        XCTAssertEqual(viewModel.filteredItems.count, 1)
        XCTAssertEqual(viewModel.filteredItems.first?.amount, 300)
    }

    func testSameNameCategoryDoesNotMixAcrossBooksInSearch() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        let mainViewModel = try makeSearchViewModel(bookId: main.book.id)
        mainViewModel.selectedCategory = "食費"
        mainViewModel.applyFilters()
        XCTAssertEqual(mainViewModel.filteredItems.map(\.amount), [100])
    }

    // MARK: - 種別フィルタ

    func testFilterByExpenseOnly() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.setTransactionType(.expense)
        viewModel.applyFilters()

        XCTAssertTrue(viewModel.filteredItems.allSatisfy { $0.kind == .expense })
    }

    func testFilterByIncomeOnly() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.setTransactionType(.income)
        viewModel.applyFilters()

        XCTAssertTrue(viewModel.filteredItems.allSatisfy { $0.kind == .income })
    }

    // MARK: - カテゴリー/支払い方法/受け取り方法フィルタ

    func testFilterByCategory() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        let repository = SwiftDataCategoryRepository()
        try repository.addCategory(name: "娯楽", type: "支出", existingCategories: [], bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 2000, paymentMethod: "現金", category: "娯楽", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.selectedCategory = "娯楽"
        viewModel.applyFilters()

        XCTAssertEqual(viewModel.filteredItems.map(\.amount), [2000])
    }

    func testFilterByPaymentMethod() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, paymentMethod: "PayPay", category: "食費", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.setTransactionType(.expense)
        viewModel.selectedPayment = "PayPay"
        viewModel.applyFilters()

        XCTAssertEqual(viewModel.filteredItems.map(\.amount), [200])
    }

    func testFilterByReceiveMethod() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeIncome(amount: 1000, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 2000, receiveMethod: "三井住友銀行", category: "給料", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.setTransactionType(.income)
        viewModel.selectedReceive = "三井住友銀行"
        viewModel.applyFilters()

        XCTAssertEqual(viewModel.filteredItems.map(\.amount), [2000])
    }

    // MARK: - メモ検索

    func testKeywordSearchMatchesMemo() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", memo: "ランチ代", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, paymentMethod: "現金", category: "食費", memo: "ディナー代", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.keyword = "ランチ"
        viewModel.applyFilters()

        XCTAssertEqual(viewModel.filteredItems.map(\.amount), [100])
    }

    // MARK: - 日付範囲フィルタ

    func testFilterByDateRange() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let inRangeDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 10))!
        let outOfRangeDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        QARegressionTestFactory.makeExpense(amount: 100, date: inRangeDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, date: outOfRangeDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))
        viewModel.endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 31))
        viewModel.applyFilters()

        XCTAssertEqual(viewModel.filteredItems.map(\.amount), [100])
    }

    // MARK: - 検索結果からの編集・削除反映

    func testEditingFromSearchResultsUpdatesFilteredItems() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var expense = QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        expense.amount = 750
        ExpenseDataSync.update(expense)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        XCTAssertEqual(viewModel.filteredItems.first?.amount, 750)
    }

    func testDeletedTransactionDisappearsFromSearchResults() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        let expense = QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        ExpenseDataSync.delete(id: expense.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        XCTAssertTrue(viewModel.filteredItems.isEmpty)
    }

    // MARK: - フィルタリセット

    func testResetAllFiltersRestoresFullList() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let viewModel = try makeSearchViewModel(bookId: main.book.id)
        viewModel.setTransactionType(.expense)
        viewModel.applyFilters()
        XCTAssertEqual(viewModel.filteredItems.count, 1)

        viewModel.resetAllFilters()
        viewModel.applyFilters()
        XCTAssertEqual(viewModel.filteredItems.count, 2)
        XCTAssertFalse(viewModel.hasActiveFilter)
    }
}
