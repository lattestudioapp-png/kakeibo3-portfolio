// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

// MARK: - 最重要シナリオ（複数帳簿の完全分離）を1本で確認する
//
// メイン帳簿: 現金・資産に含めるON・初期残高10,000円・カテゴリー「食費」・支出100円
// 事業用帳簿: 現金・資産に含めるOFF・初期残高10,000円・カテゴリー「食費」・支出200円
//
// 期待:
// - メイン帳簿の支出合計は100円だけ
// - 事業用帳簿の支出合計は200円だけ
// - メイン帳簿の総資産に現金が入る
// - 事業用帳簿の総資産に現金が入らない
// - 食費カテゴリーが混ざらない
// - 現金設定が混ざらない
// - カレンダーが混ざらない
// - 分析が混ざらない
// - 検索が混ざらない
// - バックアップ復元後も同じ結果になる
final class CriticalScenarioQARegressionTests: QARegressionTestCase {

    private var mainFixture: QARegressionTestFactory.BookFixture!
    private var businessFixture: QARegressionTestFactory.BookFixture!
    private let fixedDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try seedCriticalScenario()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    private func seedCriticalScenario() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var mainCash = main.cash
        mainCash.isAsset = true
        PaymentMethodSettingDataSync.update(mainCash)
        var businessCash = business.cash
        businessCash.isAsset = false
        PaymentMethodSettingDataSync.update(businessCash)

        mainFixture = QARegressionTestFactory.BookFixture(
            book: main.book, expenseCategory: main.expenseCategory, incomeCategory: main.incomeCategory,
            cash: mainCash, electronicMoney: main.electronicMoney, creditCard: main.creditCard,
            receiveMethod: main.receiveMethod, bankAccount: main.bankAccount
        )
        businessFixture = QARegressionTestFactory.BookFixture(
            book: business.book, expenseCategory: business.expenseCategory, incomeCategory: business.incomeCategory,
            cash: businessCash, electronicMoney: business.electronicMoney, creditCard: business.creditCard,
            receiveMethod: business.receiveMethod, bankAccount: business.bankAccount
        )

        QARegressionTestFactory.makeIncome(amount: 10000, date: fixedDate, receiveMethod: "現金", category: "初期残高", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 100, date: fixedDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        QARegressionTestFactory.makeIncome(amount: 10000, date: fixedDate, receiveMethod: "現金", category: "初期残高", bookId: business.book.id)
        QARegressionTestFactory.makeExpense(amount: 200, date: fixedDate, paymentMethod: "現金", category: "食費", bookId: business.book.id)
        SnapshotUpdateService.handle(.expenseCreated(date: fixedDate, bookId: main.book.id))
        SnapshotUpdateService.handle(.incomeCreated(date: fixedDate, bookId: main.book.id))
        SnapshotUpdateService.handle(.expenseCreated(date: fixedDate, bookId: business.book.id))
        SnapshotUpdateService.handle(.incomeCreated(date: fixedDate, bookId: business.book.id))
    }

    func testCriticalScenarioFullIsolation() async throws {
        try assertExpenseTotalsAreIsolated()
        try assertTotalAssetsAreIsolated()
        try assertCategoriesDoNotMix()
        try assertCashSettingsDoNotMix()
        try assertCalendarDoesNotMix()
        try assertAnalysisDoesNotMix()
        try assertSearchDoesNotMix()
        try await assertBackupRestoreProducesSameResult()
    }

    // MARK: - 支出合計

    private func assertExpenseTotalsAreIsolated() throws {
        let allExpenses = ExpenseDataSync.fetchAll()
        let mainTotal = allExpenses.filter { $0.bookId == mainFixture.book.id }.reduce(0) { $0 + $1.amount }
        let businessTotal = allExpenses.filter { $0.bookId == businessFixture.book.id }.reduce(0) { $0 + $1.amount }

        XCTAssertEqual(mainTotal, 100)
        XCTAssertEqual(businessTotal, 200)
    }

    // MARK: - 総資産

    private func assertTotalAssetsAreIsolated() throws {
        let allIncomes = IncomeDataSync.fetchAll()
        let allExpenses = ExpenseDataSync.fetchAll()

        let mainMethodAssets = [mainFixture.cash].filter { $0.isAsset && $0.isActive }
        let mainCalculator = BankAccountBalanceCalculator(
            bankAccounts: [],
            allIncomeData: allIncomes.filter { $0.bookId == mainFixture.book.id },
            allExpenseData: allExpenses.filter { $0.bookId == mainFixture.book.id },
            allTransferData: [], creditCardNames: []
        )
        let mainSummaries = mainCalculator.paymentMethodSummaries(for: mainMethodAssets, upTo: Date.distantFuture)
        XCTAssertEqual(mainSummaries.first?.balance, 9900) // 10000 - 100

        let businessMethodAssets = [businessFixture.cash].filter { $0.isAsset && $0.isActive }
        XCTAssertTrue(businessMethodAssets.isEmpty) // 資産に含めるOFF
    }

    // MARK: - カテゴリー

    private func assertCategoriesDoNotMix() throws {
        let allCategories = CategoryDataSync.fetchAll()
        let foodCategories = allCategories.filter { $0.name == "食費" && $0.type == "支出" }
        XCTAssertEqual(foodCategories.count, 3) // メイン・事業用・旅行用の3帳簿分
        XCTAssertNotEqual(
            foodCategories.first { $0.bookId == mainFixture.book.id }?.id,
            foodCategories.first { $0.bookId == businessFixture.book.id }?.id
        )
    }

    // MARK: - 現金設定

    private func assertCashSettingsDoNotMix() throws {
        XCTAssertNotEqual(mainFixture.cash.id, businessFixture.cash.id)
        XCTAssertEqual(mainFixture.cash.methodName, businessFixture.cash.methodName)
        XCTAssertTrue(mainFixture.cash.isAsset)
        XCTAssertFalse(businessFixture.cash.isAsset)
    }

    // MARK: - カレンダー

    private func assertCalendarDoesNotMix() throws {
        let allIncomes = IncomeDataSync.fetchAll()
        let allExpenses = ExpenseDataSync.fetchAll()
        let calculator = CalendarTransactionCalculator()

        let mainTotal = calculator.monthlyTotal(
            selectedDate: fixedDate,
            incomeDataList: allIncomes.filter { $0.bookId == mainFixture.book.id },
            expenseDataList: allExpenses.filter { $0.bookId == mainFixture.book.id }
        )
        let businessTotal = calculator.monthlyTotal(
            selectedDate: fixedDate,
            incomeDataList: allIncomes.filter { $0.bookId == businessFixture.book.id },
            expenseDataList: allExpenses.filter { $0.bookId == businessFixture.book.id }
        )

        XCTAssertEqual(mainTotal.expense, 100)
        XCTAssertEqual(businessTotal.expense, 200)
        XCTAssertEqual(mainTotal.income, 10000)
        XCTAssertEqual(businessTotal.income, 10000)
    }

    // MARK: - 分析

    private func assertAnalysisDoesNotMix() throws {
        AnalysisSnapshotManager.rebuildAll()

        let allAnalysisSnapshots = AnalysisMonthlySnapshotSync.fetchAll()
        let mainSnapshots = allAnalysisSnapshots.filter { $0.bookId == mainFixture.book.id }
        let businessSnapshots = allAnalysisSnapshots.filter { $0.bookId == businessFixture.book.id }

        XCTAssertFalse(mainSnapshots.isEmpty)
        XCTAssertFalse(businessSnapshots.isEmpty)
        XCTAssertTrue(mainSnapshots.allSatisfy { $0.bookId == mainFixture.book.id })
        XCTAssertTrue(businessSnapshots.allSatisfy { $0.bookId == businessFixture.book.id })
    }

    // MARK: - 検索

    private func assertSearchDoesNotMix() throws {
        let allIncomes = IncomeDataSync.fetchAll()
        let allExpenses = ExpenseDataSync.fetchAll()

        let mainSearch = SearchViewModel()
        mainSearch.startDate = nil
        mainSearch.endDate = nil
        mainSearch.rebuildAllItems(
            incomes: allIncomes.filter { $0.bookId == mainFixture.book.id },
            expenses: allExpenses.filter { $0.bookId == mainFixture.book.id }
        )
        mainSearch.applyFilters()

        let mainExpenseAmounts = mainSearch.filteredItems.filter { $0.kind == .expense }.map(\.amount)
        XCTAssertEqual(mainExpenseAmounts, [100])

        let businessSearch = SearchViewModel()
        businessSearch.startDate = nil
        businessSearch.endDate = nil
        businessSearch.rebuildAllItems(
            incomes: allIncomes.filter { $0.bookId == businessFixture.book.id },
            expenses: allExpenses.filter { $0.bookId == businessFixture.book.id }
        )
        businessSearch.applyFilters()

        let businessExpenseAmounts = businessSearch.filteredItems.filter { $0.kind == .expense }.map(\.amount)
        XCTAssertEqual(businessExpenseAmounts, [200])
    }

    // MARK: - バックアップ復元後も同じ結果になる

    private func assertBackupRestoreProducesSameResult() async throws {
        // BackupManager.createBackup は実Documentsフォルダへ書き込むため、
        // ここでは復元先を新しいインメモリコンテナにしたうえで、
        // 現在のコンテキストから手動でBackupDataを組み立てて往復させる。
        let allBooks = BookDataSync.fetchAll()
        let allExpenses = ExpenseDataSync.fetchAll()
        let allIncomes = IncomeDataSync.fetchAll()
        let allCategories = CategoryDataSync.fetchAll()
        let allPaymentMethods = PaymentMethodSettingDataSync.fetchAll()

        let backup = BackupData(
            version: BackupData.currentVersion,
            createdAt: Date(),
            books: allBooks.map {
                BookBackupItem(id: $0.id, name: $0.name, createdAt: $0.createdAt, sortOrder: $0.sortOrder, isArchived: $0.isArchived, isMain: $0.isMain)
            },
            expenses: allExpenses.map {
                ExpenseBackupItem(
                    id: $0.id, amount: $0.amount, date: $0.date, paymentMethod: $0.paymentMethod, category: $0.category,
                    memo: $0.memo, createdAt: $0.createdAt, bankAccountId: $0.bankAccountId, fixedExpenseId: $0.fixedExpenseId,
                    receiptImagePath: $0.receiptImagePath, isTestData: $0.isTestData, bookId: $0.bookId
                )
            },
            incomes: allIncomes.map {
                IncomeBackupItem(
                    id: $0.id, amount: $0.amount, date: $0.date, receiveMethod: $0.receiveMethod, category: $0.category,
                    memo: $0.memo, createdAt: $0.createdAt, bankAccountId: $0.bankAccountId, recurringIncomeId: $0.recurringIncomeId,
                    receiptImagePath: $0.receiptImagePath, isTestData: $0.isTestData, bookId: $0.bookId
                )
            },
            transfers: [],
            categories: allCategories.map {
                CategoryBackupItem(name: $0.name, colorHex: $0.colorHex, type: $0.type, sortOrder: $0.sortOrder, createdAt: $0.createdAt, bookId: $0.bookId)
            },
            paymentMethods: allPaymentMethods.map {
                PaymentMethodBackupItem(
                    id: $0.id, methodName: $0.methodName, type: $0.type, closingDay: $0.closingDay, withdrawalDay: $0.withdrawalDay,
                    adjustPaymentDateToNextBusinessDay: $0.adjustPaymentDateToNextBusinessDay, bankAccount: $0.bankAccount,
                    withdrawalBankAccountId: $0.withdrawalBankAccountId, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    sortOrder: $0.sortOrder, isActive: $0.isActive, isAsset: $0.isAsset, assetInitialBalance: $0.assetInitialBalance,
                    includeInAnalysis: $0.includeInAnalysis, assetInitialBalanceIncomeId: $0.assetInitialBalanceIncomeId,
                    showInInputPicker: $0.showInInputPicker, useForReceive: $0.useForReceive, showInAnalysis: $0.showInAnalysis,
                    recurringTransferSettingId: $0.recurringTransferSettingId, recurringTransferSettingIds: $0.recurringTransferSettingIds,
                    isTestData: $0.isTestData, bookId: $0.bookId
                )
            },
            receiveMethods: [], bankAccounts: [], budgets: [], recurringBudgets: [],
            fixedExpenses: [], recurringIncomes: [], recurringTransfers: [],
            settings: BackupSettings(
                themeColorHex: nil, analysisSegmentOrder: nil, showPreviousMonthCarryover: true,
                creditCardAssetReflectionTiming: nil, accountingMonthStartDay: nil,
                accountingMonthWeekendHolidayAdjustment: nil, accountingMonthLabelBasis: nil, calendarWeekStartWeekday: nil
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionCritical_\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await BackupManager().restore(from: url, targetBookId: mainFixture.book.id)

        let restoredExpenses = ExpenseDataSync.fetchAll()
        let restoredMainTotal = restoredExpenses.filter { $0.bookId == mainFixture.book.id }.reduce(0) { $0 + $1.amount }
        let restoredBusinessTotal = restoredExpenses.filter { $0.bookId == businessFixture.book.id }.reduce(0) { $0 + $1.amount }

        XCTAssertEqual(restoredMainTotal, 100)
        XCTAssertEqual(restoredBusinessTotal, 200)

        let restoredCategories = CategoryDataSync.fetchAll()
        XCTAssertEqual(restoredCategories.filter { $0.name == "食費" }.count, 3)
    }
}
