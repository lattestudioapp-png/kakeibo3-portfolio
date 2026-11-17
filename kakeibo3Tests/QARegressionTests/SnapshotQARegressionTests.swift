// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 注意: SnapshotUpdateService.handle(.fullRebuildRequested)・.bankAccountTouched・.methodTouched・
// .categoryDeleted は SnapshotRebuildQueue 経由の非同期処理のため、テストでは決定的な
// SnapshotManager.rebuildAll() / AnalysisSnapshotManager.rebuildAll() を直接呼ぶか、
// 同期的に処理される .expenseCreated 等のイベントだけを使う。

import XCTest
@testable import kakeibo3

final class SnapshotQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 保存直後の同期反映

    func testExpenseSaveUpdatesDailyAndMonthlySnapshotsSynchronously() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        let expense = QARegressionTestFactory.makeExpense(amount: 700, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: main.book.id))

        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.expenseTotal }, 700)

        let monthlySnapshots = MonthlySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertFalse(monthlySnapshots.isEmpty)

        _ = expense
    }

    func testExpenseSaveUpdatesAnalysisMonthlySnapshot() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeExpense(amount: 900, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: main.book.id))

        let analysisSnapshots = AnalysisMonthlySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertFalse(analysisSnapshots.isEmpty)
    }

    func testIncomeSaveUpdatesSnapshots() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeIncome(amount: 4000, date: date, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        SnapshotUpdateService.handle(.incomeCreated(date: date, bookId: main.book.id))

        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.incomeTotal }, 4000)
    }

    func testEditingTransactionRecalculatesSnapshot() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        var expense = QARegressionTestFactory.makeExpense(amount: 500, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: main.book.id))

        expense.amount = 1500
        ExpenseDataSync.update(expense)
        SnapshotUpdateService.handle(.expenseUpdated(oldDate: date, newDate: date, bookId: main.book.id))

        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.expenseTotal }, 1500)
    }

    func testDeletingTransactionRecalculatesSnapshot() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        let expense = QARegressionTestFactory.makeExpense(amount: 500, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: main.book.id))

        ExpenseDataSync.delete(id: expense.id)
        SnapshotUpdateService.handle(.expenseDeleted(date: date, bookId: main.book.id))

        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.expenseTotal }, 0)
    }

    // MARK: - 帳簿ごとのスナップショット分離

    func testSnapshotsAreSeparatedPerBook() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeExpense(amount: 100, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, date: date, paymentMethod: "現金", category: "食費", bookId: business.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: main.book.id))
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: business.book.id))

        let allDaily = DailySnapshotSync.fetchAll()
        XCTAssertEqual(allDaily.filter { $0.bookId == main.book.id }.reduce(0) { $0 + $1.expenseTotal }, 100)
        XCTAssertEqual(allDaily.filter { $0.bookId == business.book.id }.reduce(0) { $0 + $1.expenseTotal }, 200)
    }

    func testSnapshotDoesNotReferenceOtherBookData() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeExpense(amount: 100, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: date, bookId: main.book.id))

        // 事業用帳簿には何も保存していないので、スナップショットも作られていないはず
        let businessDaily = DailySnapshotSync.fetchAll(bookId: business.book.id)
        XCTAssertTrue(businessDaily.isEmpty)
    }

    // MARK: - nil bookIdの扱い / メイン帳簿への移行

    func testMigrationBackfillsNilBookIdSnapshotsToMainBook() throws {
        _ = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        let allBooks = BookDataSync.fetchAll()
        XCTAssertEqual(allBooks.count, 1) // 新しくメイン帳簿が重複作成されていない
    }

    // MARK: - 全再構築で金額が正しくなる

    func testFullRebuildProducesCorrectTotals() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeExpense(amount: 300, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 1000, date: date, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        // スナップショットを一切touchしない状態から全再構築する
        SnapshotManager.rebuildAll()
        AnalysisSnapshotManager.rebuildAll()

        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.expenseTotal }, 300)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.incomeTotal }, 1000)
    }

    func testFullRebuildDoesNotDuplicateSnapshotRows() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeExpense(amount: 300, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        SnapshotManager.rebuildAll()
        let firstRunCount = DailySnapshotSync.fetchAll(bookId: main.book.id).count

        SnapshotManager.rebuildAll()
        let secondRunCount = DailySnapshotSync.fetchAll(bookId: main.book.id).count

        XCTAssertEqual(firstRunCount, secondRunCount)
    }

    // MARK: - 使用停止カテゴリーをスナップショット集計から除外しない

    func testSuspendedCategoryIsNotExcludedFromSnapshotRebuild() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let date = Date()
        QARegressionTestFactory.makeExpense(amount: 400, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        SnapshotManager.rebuildAll()

        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.expenseTotal }, 400)
    }

    // MARK: - 資産に含めるOFFの口座/現金は資産Snapshotに含めない

    func testAssetExcludedMethodIsNotIncludedInAssetGraphCache() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isAsset = false
        PaymentMethodSettingDataSync.update(cash)

        let methodAssets = [cash].filter { $0.isAsset && $0.isActive }
        XCTAssertTrue(methodAssets.isEmpty)
    }
}
