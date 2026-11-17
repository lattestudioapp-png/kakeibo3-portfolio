// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class CrashSafetyQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 初回起動相当

    func testFreshStartDoesNotCrash() throws {
        XCTAssertNoThrow(BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false))
        XCTAssertNoThrow(SnapshotManager.backfillIfNeeded())
        XCTAssertNoThrow(AnalysisSnapshotManager.backfillIfNeeded())
        XCTAssertNoThrow(DowngradeLockService.unlockAll())
        XCTAssertNoThrow(RecurringEntryGenerator.backfillAllIfNeeded())

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)
    }

    // MARK: - 既存データ(bookId=nilのレガシーデータ)ありでのアップデート相当

    func testMigrationWithLegacyNilBookIdDataDoesNotCrash() throws {
        // 複数帳簿対応前に保存された、bookIdを持たないデータを模す
        let legacyExpense = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "")
        ExpenseDataSync.insert(legacyExpense) // bookId は初期値のnilのまま

        XCTAssertNoThrow(BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false))

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)

        let expenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(expenses.first?.bookId, books.first?.id) // メイン帳簿にバックフィルされる
    }

    func testBookIdNilDataDoesNotCrashSnapshotRebuild() throws {
        let legacyExpense = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "")
        ExpenseDataSync.insert(legacyExpense)

        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        XCTAssertNoThrow(SnapshotManager.rebuildAll())
        XCTAssertNoThrow(AnalysisSnapshotManager.rebuildAll())
    }

    // MARK: - BookDataなし状態からの各種処理呼び出し

    func testCalculatingWithNoBooksDoesNotCrash() throws {
        // BookDataが1件も無い状態であえてmigrateIfNeededを呼ばずに集計系を叩く
        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        XCTAssertNoThrow(calculator.totalAssets(upTo: Date()))
        XCTAssertNoThrow(calculator.paymentMethodSummaries(for: [], upTo: Date()))

        let calendarCalculator = CalendarTransactionCalculator()
        XCTAssertNoThrow(calendarCalculator.monthlyTotal(selectedDate: Date(), incomeDataList: [], expenseDataList: []))
    }

    // MARK: - 各種0件状態

    func testZeroCategoriesDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        // 全カテゴリーを削除
        for category in CategoryDataSync.fetchAll() { CategoryDataSync.delete(id: category.id) }

        let repository = SwiftDataCategoryRepository()
        XCTAssertNoThrow(repository.categoryNames(type: "支出", categories: []))
        XCTAssertNoThrow(repository.sortedCategories(type: "支出", categories: []))
        _ = main
    }

    func testZeroPaymentMethodsDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        for method in PaymentMethodSettingDataSync.fetchAll() { PaymentMethodSettingDataSync.delete(id: method.id) }

        let participants = TransferParticipantBuilder.build(bankAccounts: [], paymentMethods: [], receiveMethods: [])
        XCTAssertTrue(participants.isEmpty)
        _ = main
    }

    func testZeroBankAccountsDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        for bank in BankAccountDataSync.fetchAll() { BankAccountDataSync.delete(id: bank.id) }

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        XCTAssertNoThrow(calculator.summaries(for: AnalysisDateRange(start: .distantPast, end: .distantFuture)))
        _ = main
    }

    func testZeroCreditCardsDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        PaymentMethodSettingDataSync.delete(id: main.creditCard.id)

        let allMethods = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id)
        XCTAssertFalse(allMethods.contains { $0.type == PaymentMethodType.creditCard.rawValue })
    }

    func testZeroBudgetsDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        XCTAssertNoThrow(
            BudgetSummaryService.buildMonthSummary(
                allExpenses: [], allBudgets: [], allRecurringBudgets: [], allCategories: allCategories,
                year: 2026, month: 7
            )
        )
    }

    // MARK: - 全データ削除後

    func testDeletingAllDataDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        XCTAssertNoThrow(DataResetService.deleteAllData(bookId: main.book.id))

        let remaining = ExpenseDataSync.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - 帳簿削除直後の集計呼び出し

    func testCallingAggregationImmediatelyAfterBookDeletionDoesNotCrash() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        BookDeletionService.deleteBook(business.book)

        // 削除直後に全期間再構築を呼んでもクラッシュしない
        XCTAssertNoThrow(SnapshotManager.rebuildAll())
        XCTAssertNoThrow(AnalysisSnapshotManager.rebuildAll())

        let remainingSnapshots = DailySnapshotSync.fetchAll()
        XCTAssertTrue(remainingSnapshots.allSatisfy { $0.bookId != business.book.id })
        _ = main
    }

    func testRebuildingSnapshotsTwiceInARowDoesNotCrashOrCorruptData() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        SnapshotManager.rebuildAll()
        XCTAssertNoThrow(SnapshotManager.rebuildAll()) // 再構築中に別の再構築が走った状態を模す

        let snapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(snapshots.reduce(0) { $0 + $1.expenseTotal }, 500) // 二重計上されていない
    }
}
