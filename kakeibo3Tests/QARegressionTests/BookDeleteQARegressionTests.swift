// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class BookDeleteQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 削除対象の特定

    func testCanIdentifyBookToDeleteById() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let targetId = business.book.id
        let fetched = BookDataSync.fetchAll()
        let target = fetched.first { $0.id == targetId }

        XCTAssertNotNil(target)
        XCTAssertEqual(target?.name, "事業用帳簿")
        XCTAssertNotEqual(target?.id, main.book.id)
    }

    // MARK: - メイン帳簿は削除不可

    func testMainBookCannotBeDeleted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        BookDeletionService.deleteBook(main.book)

        let remaining = BookDataSync.fetchAll()
        XCTAssertTrue(remaining.contains { $0.id == main.book.id })
    }

    // MARK: - 選択中の帳簿削除後、メイン帳簿へ切り替わる
    //
    // 実際の切り替えロジックは BookSwitchSettingView.swift の private struct BookEditView.deleteBook() 内にあり、
    // Viewから独立していないため直接呼び出せない。同じ手順をここに再現する。

    func testDeletingSelectedBookFallsBackToMainBook() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var selectedBookIdString = business.book.id.uuidString
        let wasSelected = UUID(uuidString: selectedBookIdString) == business.book.id

        BookDeletionService.deleteBook(business.book)

        let remaining = BookDataSync.fetchAll()
        if wasSelected, let mainBook = remaining.first(where: { $0.isMain }) {
            selectedBookIdString = mainBook.id.uuidString
        }

        XCTAssertEqual(selectedBookIdString, main.book.id.uuidString)
    }

    // MARK: - 削除対象帳簿の全データが削除される

    func testDeletingBookRemovesAllScopedData() throws {
        let (_, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let bookId = business.book.id
        let expense = QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: bookId)
        let income = QARegressionTestFactory.makeIncome(amount: 3000, receiveMethod: "現金", category: "給料", bookId: bookId)

        var budget = BudgetData(year: 2026, month: 7, categoryName: "食費", amount: 30000)
        budget.bookId = bookId
        BudgetDataSync.insert(budget)

        var recurringBudget = RecurringBudgetData(categoryName: "食費", amount: 20000)
        recurringBudget.bookId = bookId
        RecurringBudgetDataSync.insert(recurringBudget)

        var fixedExpense = FixedExpenseData(name: "家賃", amount: 80000)
        fixedExpense.bookId = bookId
        FixedExpenseDataSync.insert(fixedExpense)

        var recurringIncome = RecurringIncomeData(name: "給料", amount: 250000)
        recurringIncome.bookId = bookId
        RecurringIncomeDataSync.insert(recurringIncome)

        var transfer = TransferData(
            fromType: TransferAccountType.paymentMethod.rawValue,
            fromId: business.cash.id,
            fromName: "現金",
            toType: TransferAccountType.bank.rawValue,
            toId: business.bankAccount.id,
            toName: "三井住友銀行",
            amount: 1000
        )
        transfer.bookId = bookId
        TransferDataSync.insert(transfer)

        var recurringTransfer = RecurringTransferSettingData(
            fromMethodId: business.cash.id,
            fromMethodName: "現金",
            toMethodId: business.bankAccount.id,
            toMethodName: "三井住友銀行",
            amount: 500,
            day: 1
        )
        recurringTransfer.bookId = bookId
        RecurringTransferSettingDataSync.insert(recurringTransfer)

        SnapshotManager.rebuildAll()
        AnalysisSnapshotManager.rebuildAll()

        // 削除前に対象データが存在することを確認
        XCTAssertFalse(ExpenseDataSync.fetchAll(bookId: bookId).isEmpty)
        XCTAssertFalse(DailySnapshotSync.fetchAll(bookId: bookId).isEmpty)

        BookDeletionService.deleteBook(business.book)

        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(IncomeDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(CategoryDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(PaymentMethodSettingDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(ReceiveMethodDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(BankAccountDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(BudgetDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(RecurringBudgetDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(FixedExpenseDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(RecurringIncomeDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(TransferDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(RecurringTransferSettingDataSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(DailySnapshotSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(MonthlySnapshotSync.fetchAll(bookId: bookId).count, 0)
        XCTAssertEqual(AnalysisMonthlySnapshotSync.fetchAll(bookId: bookId).count, 0)

        // BookData自体も消えている
        XCTAssertFalse(BookDataSync.fetchAll().contains { $0.id == bookId })

        _ = expense
        _ = income
    }

    // MARK: - 他帳簿のデータは消えない

    func testDeletingBookDoesNotAffectOtherBooksData() throws {
        let (main, business, travel) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, paymentMethod: "現金", category: "食費", bookId: business.book.id)
        QARegressionTestFactory.makeExpense(amount: 300, paymentMethod: "現金", category: "食費", bookId: travel.book.id)

        BookDeletionService.deleteBook(business.book)

        let remainingExpenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(remainingExpenses.filter { $0.bookId == main.book.id }.count, 1)
        XCTAssertEqual(remainingExpenses.filter { $0.bookId == travel.book.id }.count, 1)
        XCTAssertEqual(remainingExpenses.filter { $0.bookId == business.book.id }.count, 0)

        // メイン帳簿・旅行用帳簿のカテゴリー/支払い方法も無事
        XCTAssertEqual(CategoryDataSync.fetchAll(bookId: main.book.id).count, 2)
        XCTAssertEqual(CategoryDataSync.fetchAll(bookId: travel.book.id).count, 2)
        XCTAssertEqual(CategoryDataSync.fetchAll(bookId: business.book.id).count, 0)
    }
}
