// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 注意: BackupManager.createBackup(modelContext:) はアプリの実Documentsフォルダ
// (またはカスタムバックアップフォルダ)へ無条件に書き込む実装になっており、テストから
// 呼ぶと実データ領域にファイルを作ってしまうリスクがある。そのためこのファイルでは
// createBackup() を直接呼ばず、BackupData を手動構築してFileManager.default.temporaryDirectory
// (プロセスごとに隔離された一時領域)へ書き出し、restore(from:modelContext:) だけを検証する。
// restore は指定したModelContext（インメモリ）だけを書き換えるため安全に検証できる。

import XCTest
@testable import kakeibo3

final class BackupRestoreQARegressionTests: QARegressionTestCase {
    private var tempFileURLs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs = []
        try super.tearDownWithError()
    }

    // MARK: - ヘルパー

    private func writeBackupToTempFile(_ backup: BackupData) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionBackup_\(UUID().uuidString).json")
        try data.write(to: url)
        tempFileURLs.append(url)
        return url
    }

    private func makeTwoBookBackup() -> (backup: BackupData, mainBookId: UUID, businessBookId: UUID) {
        let mainBookId = UUID()
        let businessBookId = UUID()

        let books = [
            BookBackupItem(id: mainBookId, name: "メイン帳簿", createdAt: Date(), sortOrder: 0, isArchived: false, isMain: true),
            BookBackupItem(id: businessBookId, name: "事業用帳簿", createdAt: Date(), sortOrder: 1, isArchived: false, isMain: false),
        ]

        let categories = [
            CategoryBackupItem(name: "食費", colorHex: "#6FA58C", type: "支出", sortOrder: 0, createdAt: Date(), bookId: mainBookId),
            CategoryBackupItem(name: "食費", colorHex: "#6FA58C", type: "支出", sortOrder: 0, createdAt: Date(), bookId: businessBookId),
            CategoryBackupItem(name: "給料", colorHex: "#5A9ED8", type: "収入", sortOrder: 0, createdAt: Date(), bookId: mainBookId),
        ]

        let expenses = [
            ExpenseBackupItem(
                id: UUID(), amount: 111, date: Date(), paymentMethod: "現金", category: "食費", memo: "メイン",
                createdAt: Date(), bankAccountId: nil, fixedExpenseId: nil, receiptImagePath: nil,
                isTestData: false, bookId: mainBookId
            ),
            ExpenseBackupItem(
                id: UUID(), amount: 222, date: Date(), paymentMethod: "現金", category: "食費", memo: "事業用",
                createdAt: Date(), bankAccountId: nil, fixedExpenseId: nil, receiptImagePath: nil,
                isTestData: false, bookId: businessBookId
            ),
        ]

        let paymentMethods = [
            PaymentMethodBackupItem(
                id: UUID(), methodName: "現金", type: PaymentMethodType.cash.rawValue, closingDay: nil, withdrawalDay: nil,
                adjustPaymentDateToNextBusinessDay: true, bankAccount: nil, withdrawalBankAccountId: nil,
                createdAt: Date(), updatedAt: Date(), sortOrder: 0, isActive: true, isAsset: true,
                assetInitialBalance: nil, includeInAnalysis: true, assetInitialBalanceIncomeId: nil,
                showInInputPicker: true, useForReceive: true, showInAnalysis: true,
                recurringTransferSettingId: nil, recurringTransferSettingIds: [], isTestData: false, bookId: mainBookId
            ),
            PaymentMethodBackupItem(
                id: UUID(), methodName: "現金", type: PaymentMethodType.cash.rawValue, closingDay: nil, withdrawalDay: nil,
                adjustPaymentDateToNextBusinessDay: true, bankAccount: nil, withdrawalBankAccountId: nil,
                createdAt: Date(), updatedAt: Date(), sortOrder: 0, isActive: true, isAsset: false,
                assetInitialBalance: nil, includeInAnalysis: true, assetInitialBalanceIncomeId: nil,
                showInInputPicker: true, useForReceive: true, showInAnalysis: true,
                recurringTransferSettingId: nil, recurringTransferSettingIds: [], isTestData: false, bookId: businessBookId
            ),
        ]

        let backup = BackupData(
            version: BackupData.currentVersion,
            createdAt: Date(),
            books: books,
            expenses: expenses,
            incomes: [],
            transfers: [],
            categories: categories,
            paymentMethods: paymentMethods,
            receiveMethods: [],
            bankAccounts: [],
            budgets: [],
            recurringBudgets: [],
            fixedExpenses: [],
            recurringIncomes: [],
            recurringTransfers: [],
            settings: BackupSettings(
                themeColorHex: nil, analysisSegmentOrder: nil, showPreviousMonthCarryover: true,
                creditCardAssetReflectionTiming: nil, accountingMonthStartDay: nil,
                accountingMonthWeekendHolidayAdjustment: nil, accountingMonthLabelBasis: nil,
                calendarWeekStartWeekday: nil
            )
        )
        return (backup, mainBookId, businessBookId)
    }

    // MARK: - 複数帳簿を含むバックアップの復元

    func testBackupContainsMultipleBooksWithBookIds() throws {
        let (backup, mainBookId, businessBookId) = makeTwoBookBackup()
        XCTAssertEqual(backup.books?.count, 2)
        XCTAssertEqual(Set(backup.books?.map(\.id) ?? []), Set([mainBookId, businessBookId]))
    }

    func testExpensesAreRestored() async throws {
        let (backup, mainBookId, businessBookId) = makeTwoBookBackup()
        let url = try writeBackupToTempFile(backup)

        let manager = BackupManager()
        try await manager.restore(from: url, targetBookId: mainBookId)

        let expenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(expenses.count, 2)
        XCTAssertEqual(expenses.filter { $0.bookId == mainBookId }.first?.amount, 111)
        XCTAssertEqual(expenses.filter { $0.bookId == businessBookId }.first?.amount, 222)
    }

    func testCategoriesAreRestoredWithBookSeparationPreserved() async throws {
        let (backup, mainBookId, businessBookId) = makeTwoBookBackup()
        let url = try writeBackupToTempFile(backup)

        let manager = BackupManager()
        try await manager.restore(from: url, targetBookId: mainBookId)

        let categories = CategoryDataSync.fetchAll()
        // 同名「食費」が両帳簿分復元され、混ざっていない
        XCTAssertEqual(categories.filter { $0.name == "食費" }.count, 2)
        XCTAssertEqual(categories.filter { $0.name == "食費" && $0.bookId == mainBookId }.count, 1)
        XCTAssertEqual(categories.filter { $0.name == "食費" && $0.bookId == businessBookId }.count, 1)
        XCTAssertEqual(categories.filter { $0.name == "給料" && $0.bookId == mainBookId }.count, 1)
    }

    func testPaymentMethodsAreRestoredWithoutMixingSameNameSettings() async throws {
        let (backup, mainBookId, businessBookId) = makeTwoBookBackup()
        let url = try writeBackupToTempFile(backup)

        let manager = BackupManager()
        try await manager.restore(from: url, targetBookId: mainBookId)

        let methods = PaymentMethodSettingDataSync.fetchAll()
        let mainCash = methods.first { $0.bookId == mainBookId }
        let businessCash = methods.first { $0.bookId == businessBookId }

        XCTAssertEqual(mainCash?.methodName, "現金")
        XCTAssertEqual(businessCash?.methodName, "現金")
        XCTAssertTrue(mainCash?.isAsset ?? false)
        XCTAssertFalse(businessCash?.isAsset ?? true) // 同名でも資産設定が混ざっていない
    }

    func testRestoredBooksPreserveBookSeparation() async throws {
        let (backup, mainBookId, businessBookId) = makeTwoBookBackup()
        let url = try writeBackupToTempFile(backup)

        let manager = BackupManager()
        try await manager.restore(from: url, targetBookId: mainBookId)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 2)
        XCTAssertTrue(books.contains { $0.id == mainBookId && $0.isMain })
        XCTAssertTrue(books.contains { $0.id == businessBookId && !$0.isMain })
    }

    func testRestoreRebuildsSnapshots() async throws {
        let (backup, mainBookId, _) = makeTwoBookBackup()
        let url = try writeBackupToTempFile(backup)

        let manager = BackupManager()
        try await manager.restore(from: url, targetBookId: mainBookId)

        // restore() 内部で SnapshotUpdateService.handle(.fullRebuildRequested) がキューされる。
        // 決定的に確認するため、ここでは同期的な rebuildAll を明示的に呼んで整合性を確認する。
        SnapshotManager.rebuildAll()
        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: mainBookId)
        XCTAssertEqual(dailySnapshots.reduce(0) { $0 + $1.expenseTotal }, 111)
    }

    // MARK: - 旧形式(帳簿機能導入前)のバックアップ

    func testLegacyBackupWithoutBooksDoesNotCrash() async throws {
        let legacyBackup = BackupData(
            version: 0,
            createdAt: Date(),
            books: nil, // 旧形式は books が無い
            expenses: [
                ExpenseBackupItem(
                    id: UUID(), amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "",
                    createdAt: Date(), bankAccountId: nil, fixedExpenseId: nil, receiptImagePath: nil,
                    isTestData: false, bookId: nil
                ),
            ],
            incomes: [], transfers: [], categories: [], paymentMethods: [], receiveMethods: [],
            bankAccounts: [], budgets: [], recurringBudgets: [], fixedExpenses: [], recurringIncomes: [],
            recurringTransfers: [],
            settings: BackupSettings(
                themeColorHex: nil, analysisSegmentOrder: nil, showPreviousMonthCarryover: true,
                creditCardAssetReflectionTiming: nil, accountingMonthStartDay: nil,
                accountingMonthWeekendHolidayAdjustment: nil, accountingMonthLabelBasis: nil,
                calendarWeekStartWeekday: nil
            )
        )
        let url = try writeBackupToTempFile(legacyBackup)

        let manager = BackupManager()
        do {
            try await manager.restore(from: url, targetBookId: UUID())
        } catch {
            XCTFail("復元が失敗しないはずだが例外が発生した: \(error)")
        }

        let expenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(expenses.count, 1)
    }

    // MARK: - 復元失敗時にクラッシュしない

    func testRestoringFromInvalidFileDoesNotCrash() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionInvalid_\(UUID().uuidString).json")
        try "not valid json".data(using: .utf8)!.write(to: url)
        tempFileURLs.append(url)

        let manager = BackupManager()
        do {
            try await manager.restore(from: url, targetBookId: UUID())
            XCTFail("不正なファイルからの復元は例外を投げるはずだが成功した")
        } catch {
            // 期待通り
        }
    }

    func testRestoringFromMissingFileDoesNotCrash() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionMissing_\(UUID().uuidString).json")
        let manager = BackupManager()
        do {
            try await manager.restore(from: url, targetBookId: UUID())
            XCTFail("存在しないファイルからの復元は例外を投げるはずだが成功した")
        } catch {
            // 期待通り
        }
    }

    // MARK: - 帳簿単位バックアップ（新方式）：他帳簿のデータ破損バグの再現・修正確認
    //
    // 実際のバグ報告の再現手順をそのままなぞる:
    // 1. メイン帳簿でバックアップ1を復元 → 2. 新しい帳簿を作成 → 3. バックアップ2を復元
    // → 4. メイン帳簿へ戻る → メイン帳簿のデータが変わっていないことを確認する。

    private func makeScopedBackup(bookId: UUID, expenseAmount: Int, memo: String) -> BackupData {
        var backup = BackupData(
            version: BackupData.currentVersion,
            createdAt: Date(),
            books: [BookBackupItem(id: bookId, name: memo, createdAt: Date(), sortOrder: 0, isArchived: false, isMain: false)],
            expenses: [
                ExpenseBackupItem(
                    id: UUID(), amount: expenseAmount, date: Date(), paymentMethod: "現金", category: "食費", memo: memo,
                    createdAt: Date(), bankAccountId: nil, fixedExpenseId: nil, receiptImagePath: nil,
                    isTestData: false, bookId: bookId
                ),
            ],
            incomes: [], transfers: [], categories: [], paymentMethods: [], receiveMethods: [],
            bankAccounts: [], budgets: [], recurringBudgets: [], fixedExpenses: [], recurringIncomes: [],
            recurringTransfers: [],
            settings: BackupSettings(
                themeColorHex: nil, analysisSegmentOrder: nil, showPreviousMonthCarryover: true,
                creditCardAssetReflectionTiming: nil, accountingMonthStartDay: nil,
                accountingMonthWeekendHolidayAdjustment: nil, accountingMonthLabelBasis: nil,
                calendarWeekStartWeekday: nil
            )
        )
        backup.sourceBookId = bookId
        return backup
    }

    func testScopedRestoreIntoOneBookDoesNotAffectOtherBooks() async throws {
        let mainBook = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(mainBook)
        let newBook = BookData(name: "新しい帳簿", sortOrder: 1, isMain: false)
        BookDataSync.insert(newBook)

        let manager = BackupManager()

        // 1. メイン帳簿でバックアップ1を復元
        let backup1 = makeScopedBackup(bookId: mainBook.id, expenseAmount: 1000, memo: "バックアップ1")
        let url1 = try writeBackupToTempFile(backup1)
        try await manager.restore(from: url1, targetBookId: mainBook.id)

        let mainExpensesAfterBackup1 = ExpenseDataSync.fetchAll(bookId: mainBook.id)
        XCTAssertEqual(mainExpensesAfterBackup1.map(\.amount), [1000])

        // 2. 新しい帳簿を作成（すでに上で作成済み）
        // 3. バックアップ2を復元（対象は新しい帳簿）
        let backup2 = makeScopedBackup(bookId: UUID(), expenseAmount: 2000, memo: "バックアップ2")
        let url2 = try writeBackupToTempFile(backup2)
        try await manager.restore(from: url2, targetBookId: newBook.id)

        // 4. メイン帳簿へ戻る → メイン帳簿のデータが変わっていないことを確認
        let mainExpensesAfterBackup2 = ExpenseDataSync.fetchAll(bookId: mainBook.id)
        XCTAssertEqual(mainExpensesAfterBackup2.map(\.amount), [1000], "バックアップ2の復元でメイン帳簿のデータが変わってはいけない")

        let newBookExpenses = ExpenseDataSync.fetchAll(bookId: newBook.id)
        XCTAssertEqual(newBookExpenses.map(\.amount), [2000])

        // 帳簿自体（BookData）も勝手に削除・上書きされていない
        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 2)
        XCTAssertTrue(books.contains { $0.id == mainBook.id && $0.name == "メイン帳簿" })
        XCTAssertTrue(books.contains { $0.id == newBook.id && $0.name == "新しい帳簿" })
    }

    // MARK: - BackupItem属性欠落の回帰確認（使用停止/保護/memo/写真参照/UUID/全属性）

    func testSuspendedCategoryStaysSuspendedAfterRestore() async throws {
        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        var backup = makeScopedBackup(bookId: book.id, expenseAmount: 100, memo: "x")
        backup.categories = [
            CategoryBackupItem(
                id: UUID(), name: "使わないカテゴリ", colorHex: "#111111", type: "支出",
                sortOrder: 0, createdAt: Date(), bookId: book.id,
                isTestData: false, isSuspended: true, isProtected: false
            ),
        ]
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: book.id)

        let categories = CategoryDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(categories.first?.isSuspended, true)
    }

    func testProtectedCategoryStaysProtectedAfterRestore() async throws {
        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        var backup = makeScopedBackup(bookId: book.id, expenseAmount: 100, memo: "x")
        backup.categories = [
            CategoryBackupItem(
                id: UUID(), name: "初期残高", colorHex: "#222222", type: "収入",
                sortOrder: 0, createdAt: Date(), bookId: book.id,
                isTestData: false, isSuspended: false, isProtected: true
            ),
        ]
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: book.id)

        let categories = CategoryDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(categories.first?.isProtected, true)
    }

    func testPaymentMethodMemoIsPreservedAfterRestore() async throws {
        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        var backup = makeScopedBackup(bookId: book.id, expenseAmount: 100, memo: "x")
        backup.paymentMethods = [
            PaymentMethodBackupItem(
                id: UUID(), methodName: "現金", type: PaymentMethodType.cash.rawValue,
                closingDay: nil, withdrawalDay: nil, adjustPaymentDateToNextBusinessDay: true,
                bankAccount: nil, withdrawalBankAccountId: nil, memo: "財布の中の現金だけ",
                createdAt: Date(), updatedAt: Date(), sortOrder: 0, isActive: true, isAsset: true,
                assetInitialBalance: nil, includeInAnalysis: true, assetInitialBalanceIncomeId: nil,
                showInInputPicker: true, useForReceive: true, showInAnalysis: true,
                recurringTransferSettingId: nil, recurringTransferSettingIds: [], isTestData: false,
                bookId: book.id, isLocked: false
            ),
        ]
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: book.id)

        let methods = PaymentMethodSettingDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(methods.first?.memo, "財布の中の現金だけ")
    }

    func testTransferReceiptImagePathIsPreservedAfterRestore() async throws {
        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        var backup = makeScopedBackup(bookId: book.id, expenseAmount: 100, memo: "x")
        backup.transfers = [
            TransferBackupItem(
                id: UUID(), date: Date(), fromType: "payment", fromId: nil, fromName: "現金",
                toType: "bank", toId: nil, toName: "三井住友銀行", amount: 5000, feeAmount: 0,
                memo: "", receiptImagePath: "transfer_receipt_abc123.jpg", createdAt: Date(), updatedAt: Date(),
                recurringTransferSettingId: nil, bookId: book.id, isTestData: false
            ),
        ]
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: book.id)

        let transfers = TransferDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(transfers.first?.receiptImagePath, "transfer_receipt_abc123.jpg")
    }

    /// バックアップ対象13Entity全ての永続化属性が、機械的に見て1件も欠落せず往復することを確認する。
    /// UUID（id）が復元後も維持されることもここで併せて確認する。
    func testAllBackupEntitiesRoundTripEveryPersistedAttributeWithoutLoss() async throws {
        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        let expenseId = UUID()
        let incomeId = UUID()
        let transferId = UUID()
        let categoryId = UUID()
        let paymentMethodId = UUID()
        let receiveMethodId = UUID()
        let bankAccountId = UUID()
        let budgetId = UUID()
        let recurringBudgetId = UUID()
        let fixedExpenseId = UUID()
        let recurringIncomeId = UUID()
        let recurringTransferId = UUID()

        var backup = makeScopedBackup(bookId: book.id, expenseAmount: 1, memo: "unused")
        backup.expenses = [
            ExpenseBackupItem(
                id: expenseId, amount: 321, date: Date(), paymentMethod: "現金", category: "食費",
                memo: "全属性確認", createdAt: Date(), bankAccountId: bankAccountId, fixedExpenseId: fixedExpenseId,
                receiptImagePath: "expense_photo.jpg", isTestData: true, bookId: book.id
            ),
        ]
        backup.incomes = [
            IncomeBackupItem(
                id: incomeId, amount: 654, date: Date(), receiveMethod: "現金", category: "給料",
                memo: "収入確認", createdAt: Date(), bankAccountId: bankAccountId, recurringIncomeId: recurringIncomeId,
                receiptImagePath: "income_photo.jpg", isTestData: true, bookId: book.id
            ),
        ]
        backup.transfers = [
            TransferBackupItem(
                id: transferId, date: Date(), fromType: "payment", fromId: nil, fromName: "現金",
                toType: "bank", toId: bankAccountId, toName: "三井住友銀行", amount: 999, feeAmount: 10,
                memo: "振替確認", receiptImagePath: "transfer_photo.jpg", createdAt: Date(), updatedAt: Date(),
                recurringTransferSettingId: recurringTransferId, bookId: book.id, isTestData: true
            ),
        ]
        backup.categories = [
            CategoryBackupItem(
                id: categoryId, name: "全属性カテゴリ", colorHex: "#ABCDEF", type: "支出", sortOrder: 3,
                createdAt: Date(), bookId: book.id, isTestData: true, isSuspended: true, isProtected: true
            ),
        ]
        backup.paymentMethods = [
            PaymentMethodBackupItem(
                id: paymentMethodId, methodName: "全属性カード", type: PaymentMethodType.creditCard.rawValue,
                closingDay: 15, withdrawalDay: 10, adjustPaymentDateToNextBusinessDay: false,
                bankAccount: "三井住友銀行", withdrawalBankAccountId: bankAccountId, memo: "支払い方法メモ",
                createdAt: Date(), updatedAt: Date(), sortOrder: 2, isActive: false, isAsset: true,
                assetInitialBalance: 12345, includeInAnalysis: false, assetInitialBalanceIncomeId: incomeId,
                assetInitialBalanceExpenseId: expenseId, showInInputPicker: false, useForReceive: true,
                showInAnalysis: false, recurringTransferSettingId: recurringTransferId,
                recurringTransferSettingIds: [recurringTransferId], isTestData: true, bookId: book.id, isLocked: true
            ),
        ]
        backup.receiveMethods = [
            ReceiveMethodBackupItem(
                id: receiveMethodId, methodName: "全属性受取", isActive: false, sortOrder: 4,
                createdAt: Date(), bookId: book.id
            ),
        ]
        backup.bankAccounts = [
            BankAccountBackupItem(
                id: bankAccountId, accountName: "全属性口座", initialBalance: 54321, memo: "口座メモ",
                isActive: false, sortOrder: 5, createdAt: Date(), updatedAt: Date(),
                initialBalanceIncomeId: incomeId, showAsPaymentMethod: false, showAsReceiveMethod: false,
                showInAnalysis: false, recurringTransferSettingId: recurringTransferId,
                recurringTransferSettingIds: [recurringTransferId], isTestData: true, bookId: book.id,
                isAsset: false, isLocked: true
            ),
        ]
        backup.budgets = [
            BudgetBackupItem(
                id: budgetId, year: 2026, month: 7, categoryName: "全属性カテゴリ", amount: 30000,
                createdAt: Date(), updatedAt: Date(), isTestData: true, bookId: book.id
            ),
        ]
        backup.recurringBudgets = [
            RecurringBudgetBackupItem(
                id: recurringBudgetId, categoryName: "全属性カテゴリ", amount: 40000, isEnabled: false,
                createdAt: Date(), updatedAt: Date(), bookId: book.id
            ),
        ]
        backup.fixedExpenses = [
            FixedExpenseBackupItem(
                id: fixedExpenseId, name: "全属性固定費", amount: 5000, categoryName: "全属性カテゴリ",
                paymentMethodType: "paymentMethod", paymentMethodId: paymentMethodId, dayOfMonth: 27,
                startDate: Date(), memo: "固定費メモ", isActive: false, createdAt: Date(), updatedAt: Date(),
                isTestData: true, bookId: book.id, isLocked: true
            ),
        ]
        backup.recurringIncomes = [
            RecurringIncomeBackupItem(
                id: recurringIncomeId, name: "全属性定期収入", amount: 6000, categoryName: "給料",
                receiveMethodType: "receiveMethod", receiveMethodId: receiveMethodId, dayOfMonth: 25,
                startDate: Date(), memo: "定期収入メモ", isActive: false, createdAt: Date(), updatedAt: Date(),
                isTestData: true, bookId: book.id, isLocked: true
            ),
        ]
        backup.recurringTransfers = [
            RecurringTransferBackupItem(
                id: recurringTransferId, fromMethodId: paymentMethodId, fromMethodName: "全属性カード",
                fromType: "payment", toMethodId: bankAccountId, toMethodName: "全属性口座", toType: "bank",
                amount: 7000, day: 20, startDate: Date(), isActive: false, createdAt: Date(), updatedAt: Date(),
                bookId: book.id, isLocked: true, isTestData: true
            ),
        ]

        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: book.id)

        let expense = ExpenseDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(expense?.id, expenseId)
        XCTAssertEqual(expense?.amount, 321)
        XCTAssertEqual(expense?.memo, "全属性確認")
        XCTAssertEqual(expense?.bankAccountId, bankAccountId)
        XCTAssertEqual(expense?.fixedExpenseId, fixedExpenseId)
        XCTAssertEqual(expense?.receiptImagePath, "expense_photo.jpg")
        XCTAssertEqual(expense?.isTestData, true)

        let income = IncomeDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(income?.id, incomeId)
        XCTAssertEqual(income?.recurringIncomeId, recurringIncomeId)
        XCTAssertEqual(income?.receiptImagePath, "income_photo.jpg")
        XCTAssertEqual(income?.isTestData, true)

        let transfer = TransferDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(transfer?.id, transferId)
        XCTAssertEqual(transfer?.feeAmount, 10)
        XCTAssertEqual(transfer?.receiptImagePath, "transfer_photo.jpg")
        XCTAssertEqual(transfer?.recurringTransferSettingId, recurringTransferId)
        XCTAssertEqual(transfer?.isTestData, true)

        let category = CategoryDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(category?.id, categoryId)
        XCTAssertEqual(category?.isTestData, true)
        XCTAssertEqual(category?.isSuspended, true)
        XCTAssertEqual(category?.isProtected, true)

        let method = PaymentMethodSettingDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(method?.memo, "支払い方法メモ")
        XCTAssertEqual(method?.assetInitialBalanceExpenseId, expenseId)
        XCTAssertEqual(method?.isLocked, true)

        let bankAccount = BankAccountDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(bankAccount?.isAsset, false)
        XCTAssertEqual(bankAccount?.isLocked, true)

        let fixedExpense = FixedExpenseDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(fixedExpense?.isLocked, true)

        let recurringIncome = RecurringIncomeDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(recurringIncome?.isLocked, true)

        let recurringTransfer = RecurringTransferSettingDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(recurringTransfer?.isLocked, true)
        XCTAssertEqual(recurringTransfer?.isTestData, true)
    }

    // MARK: - 資産グラフキャッシュの復元後再生成/無効化

    func testRestoreRebuildsOrInvalidatesAssetGraphCache() async throws {
        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        // 復元前の「古いキャッシュ」を直接仕込む（本来の再計算経路は使わず、確実に古い値を再現する）。
        let staleCache = AssetGraphCacheData(
            bookId: book.id, updatedAt: Date.distantPast, maxPointsUsed: 60, granularityUsed: "monthly",
            firstDate: Date.distantPast, lastDate: Date.distantPast,
            points: [AssetGraphCachePoint(date: Date.distantPast, value: 999_999)]
        )
        AssetGraphCacheDataSync.upsert(staleCache)
        XCTAssertEqual(AssetGraphCacheService.fetchTotalAssetsCache(bookId: book.id)?.points.first?.value, 999_999)

        let backup = makeScopedBackup(bookId: book.id, expenseAmount: 500, memo: "資産キャッシュ確認")
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: book.id)

        // 復元直後、古いキャッシュの値がそのまま残っていてはいけない
        // （再生成が間に合っていなくても、無効化＝nilなら正しい状態）。
        let cacheAfterRestore = AssetGraphCacheService.fetchTotalAssetsCache(bookId: book.id)
        XCTAssertNotEqual(cacheAfterRestore?.points.first?.value, 999_999, "復元後に古い資産グラフキャッシュの値が残ってはいけない")
    }

    func testRestoreDoesNotAffectOtherBookAssetGraphCache() async throws {
        let mainBook = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(mainBook)
        let otherBook = BookData(name: "事業用帳簿", sortOrder: 1, isMain: false)
        BookDataSync.insert(otherBook)

        let otherCache = AssetGraphCacheData(
            bookId: otherBook.id, updatedAt: Date(), maxPointsUsed: 60, granularityUsed: "monthly",
            firstDate: Date(), lastDate: Date(),
            points: [AssetGraphCachePoint(date: Date(), value: 123_456)]
        )
        AssetGraphCacheDataSync.upsert(otherCache)

        let backup = makeScopedBackup(bookId: mainBook.id, expenseAmount: 500, memo: "他帳簿キャッシュ確認")
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: mainBook.id)

        // メイン帳簿だけを復元しても、他帳簿（事業用帳簿）のキャッシュは一切変化しない
        let otherCacheAfterRestore = AssetGraphCacheService.fetchTotalAssetsCache(bookId: otherBook.id)
        XCTAssertEqual(otherCacheAfterRestore?.points.first?.value, 123_456)
    }

    // MARK: - アプリ再起動相当（実SQLiteストアの破棄・再生成）後もデータが維持されることの確認
    //
    // in-memoryストア（QARegressionTestCaseが毎テスト差し替える既定のCoreDataStack）は
    // 破棄すると中身も消えるため、「アプリ再起動後もデータが残る」ことの検証には使えない。
    // このテストだけは一時ディレクトリに実際のSQLiteストアを作り、CoreDataStackインスタンスを
    // 完全に破棄・同じURLから再生成することで、実際のアプリ終了→再起動を模擬する。

    func testRestoredDataSurvivesRealPersistentStoreRestart() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        // 1. 一時ディレクトリに永続ストアを作成
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let mainBook = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(mainBook)
        let otherBook = BookData(name: "事業用帳簿", sortOrder: 1, isMain: false)
        BookDataSync.insert(otherBook)
        // 他帳簿に既存データを入れておき、復元後・再起動後も変化しないことを確認する
        var otherExpense = ExpenseData(amount: 777, date: Date(), paymentMethod: "現金", category: "食費", memo: "他帳簿")
        otherExpense.bookId = otherBook.id
        ExpenseDataSync.insert(otherExpense)

        // 2. バックアップを復元
        let backup = makeScopedBackup(bookId: mainBook.id, expenseAmount: 4242, memo: "再起動確認")
        let url = try writeBackupToTempFile(backup)
        try await BackupManager().restore(from: url, targetBookId: mainBook.id)

        // 3. CoreDataStack（＝NSPersistentContainer）を破棄する
        // 4. 同じストアURLから再生成する（アプリ終了→再起動に相当）
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        // 5. 復元データが維持されていることを確認（新しいCoreDataStackインスタンス経由で読み直す）
        let mainExpensesAfterRestart = ExpenseDataSync.fetchAll(bookId: mainBook.id)
        XCTAssertEqual(mainExpensesAfterRestart.map(\.amount), [4242], "再起動相当後も復元したデータが残っている必要がある")

        let booksAfterRestart = BookDataSync.fetchAll()
        XCTAssertTrue(booksAfterRestart.contains { $0.id == mainBook.id && $0.name == "メイン帳簿" })

        // 6. 他帳簿が変化していないことを確認
        let otherExpensesAfterRestart = ExpenseDataSync.fetchAll(bookId: otherBook.id)
        XCTAssertEqual(otherExpensesAfterRestart.map(\.amount), [777], "再起動相当後も他帳簿のデータは変化してはいけない")
        XCTAssertTrue(booksAfterRestart.contains { $0.id == otherBook.id && $0.name == "事業用帳簿" })
    }
}
