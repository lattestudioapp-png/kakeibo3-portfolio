// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class MoneyItemColorQARegressionTests: QARegressionTestCase {

    // MARK: - colorHexの保存・取得

    func testPaymentMethodColorHexRoundTrips() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var cash = main.cash
        cash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.update(cash)

        let reloaded = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == cash.id }
        XCTAssertEqual(reloaded?.colorHex, "#4A7DBA")
    }

    func testBankAccountColorHexRoundTrips() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var bank = main.bankAccount
        bank.colorHex = "#82C08A"
        BankAccountDataSync.update(bank)

        let reloaded = BankAccountDataSync.fetchAll(bookId: main.book.id).first { $0.id == bank.id }
        XCTAssertEqual(reloaded?.colorHex, "#82C08A")
    }

    // MARK: - 新規追加時のデフォルト色（帳簿内で種類をまたいで重複を避ける）

    func testNextColorHexAvoidsColorsAlreadyUsedAcrossMoneyItemTypes() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var cash = main.cash
        let firstColor = MoneyItemColorDefault.nextColorHex(forPaymentMethodType: PaymentMethodType.cash.rawValue, bookId: main.book.id)
        cash.colorHex = firstColor
        PaymentMethodSettingDataSync.update(cash)

        // 銀行口座用の次色も、既に現金が使っている色は避けること
        let bankColor = MoneyItemColorDefault.nextColorHexForBankAccount(bookId: main.book.id)
        XCTAssertNotEqual(bankColor, firstColor)
    }

    func testNextColorHexForBankAccountDoesNotConsiderOtherBookColors() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var businessCash = business.cash
        let businessColor = MoneyItemColorDefault.nextColorHex(forPaymentMethodType: PaymentMethodType.cash.rawValue, bookId: business.book.id)
        businessCash.colorHex = businessColor
        PaymentMethodSettingDataSync.update(businessCash)

        // 他帳簿が使っている色の影響を受けず、メイン帳簿では最初の推奨色がそのまま選ばれる
        let mainColorWithoutBusiness = MoneyItemColorDefault.nextColorHex(forPaymentMethodType: PaymentMethodType.cash.rawValue, bookId: main.book.id)
        let mainColorIgnoringOtherBook = CategoryColorPalette.nextDistinctColor(existingColors: [])
        XCTAssertEqual(mainColorWithoutBusiness, mainColorIgnoringOtherBook)
    }

    // MARK: - 起動時バックフィル

    func testBackfillAssignsColorToExistingUnsetData() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        XCTAssertNil(PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.cash.id }?.colorHex)

        MoneyItemColorDefault.backfillMissingColorsIfNeeded()

        let afterBackfill = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.cash.id }
        XCTAssertNotNil(afterBackfill?.colorHex)
    }

    func testBackfillIsIdempotentAndDoesNotOverwriteAlreadyAssignedColors() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var cash = main.cash
        cash.colorHex = "#123456"
        PaymentMethodSettingDataSync.update(cash)

        MoneyItemColorDefault.backfillMissingColorsIfNeeded()
        MoneyItemColorDefault.backfillMissingColorsIfNeeded()

        let reloaded = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == cash.id }
        XCTAssertEqual(reloaded?.colorHex, "#123456", "既に色が確定している行はバックフィルで上書きされないこと")
    }

    func testBackfillDoesNotAffectOtherBookColors() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        MoneyItemColorDefault.backfillMissingColorsIfNeeded()

        let mainColor = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.cash.id }?.colorHex
        let businessColor = PaymentMethodSettingDataSync.fetchAll(bookId: business.book.id).first { $0.id == business.cash.id }?.colorHex
        XCTAssertNotNil(mainColor)
        XCTAssertNotNil(businessColor)
    }

    // MARK: - 分析グラフの色解決

    func testMethodColorResolvesFromPaymentMethodColorHex() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.update(cash)

        let resolved = AnalysisSnapshotBreakdownAggregator.methodColor(
            for: "現金", paymentMethods: [cash], bankAccounts: []
        )
        XCTAssertEqual(resolved, ColorHexConverter.color(from: "#4A7DBA"))
    }

    func testMethodColorResolvesFromBankAccountColorHex() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bank = main.bankAccount
        bank.colorHex = "#82C08A"
        BankAccountDataSync.update(bank)

        let resolved = AnalysisSnapshotBreakdownAggregator.methodColor(
            for: bank.accountName, paymentMethods: [], bankAccounts: [bank]
        )
        XCTAssertEqual(resolved, ColorHexConverter.color(from: "#82C08A"))
    }

    func testMethodColorFallsBackToHashBasedColorForUnmatchedName() throws {
        let resolved = AnalysisSnapshotBreakdownAggregator.methodColor(
            for: "手数料", paymentMethods: [], bankAccounts: []
        )
        let expected = ColorHexConverter.color(
            from: CategoryColorPalette.colors[abs("手数料".hashValue) % CategoryColorPalette.colors.count]
        )
        XCTAssertEqual(resolved, expected)
    }

    // MARK: - ColorHexConverter(optional)のフォールバック

    func testColorHexConverterFallsBackToThemeColorWhenNilOrEmpty() {
        // AppColors.main はUserDefaultsの実機テーマ設定に依存する動的な値のため、既知の値へ固定してから比較する
        UserDefaults.standard.removeObject(forKey: AppColors.themeColorStorageKey)
        let expectedTheme = ColorHexConverter.color(from: AppColors.defaultThemeHex)

        XCTAssertEqual(ColorHexConverter.color(from: String?.none), expectedTheme)
        XCTAssertEqual(ColorHexConverter.color(from: Optional("")), expectedTheme)
        XCTAssertEqual(ColorHexConverter.color(from: "#4A7DBA"), ColorHexConverter.color(from: "#4A7DBA" as String))
    }

    // MARK: - バックアップ・復元でcolorHexが保持される

    func testScopedRestorePreservesPaymentMethodAndBankAccountColorHex() async throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let backup = BackupData(
            version: BackupData.currentVersion, createdAt: Date(), sourceBookId: main.book.id,
            books: nil, expenses: [], incomes: [], transfers: [], categories: [],
            paymentMethods: [
                PaymentMethodBackupItem(
                    id: main.cash.id, methodName: main.cash.methodName, type: main.cash.type,
                    closingDay: nil, withdrawalDay: nil,
                    adjustPaymentDateToNextBusinessDay: true, bankAccount: nil, withdrawalBankAccountId: nil,
                    createdAt: main.cash.createdAt, updatedAt: main.cash.updatedAt, sortOrder: 0,
                    isActive: true, isAsset: true, assetInitialBalance: nil, includeInAnalysis: true,
                    assetInitialBalanceIncomeId: nil, showInInputPicker: true, useForReceive: true,
                    showInAnalysis: true, recurringTransferSettingId: nil, recurringTransferSettingIds: [],
                    isTestData: false, bookId: main.book.id, isLocked: false, colorHex: "#FF00FF"
                )
            ],
            receiveMethods: [],
            bankAccounts: [
                BankAccountBackupItem(
                    id: main.bankAccount.id, accountName: main.bankAccount.accountName, initialBalance: nil,
                    memo: nil, isActive: true, sortOrder: 0,
                    createdAt: main.bankAccount.createdAt, updatedAt: main.bankAccount.updatedAt,
                    initialBalanceIncomeId: nil, showAsPaymentMethod: true, showAsReceiveMethod: true,
                    showInAnalysis: true, recurringTransferSettingId: nil, recurringTransferSettingIds: [],
                    isTestData: false, bookId: main.book.id, isAsset: true, isLocked: false, colorHex: "#00FFAA"
                )
            ],
            budgets: [], recurringBudgets: [], fixedExpenses: [], recurringIncomes: [], recurringTransfers: [],
            settings: BackupSettings(
                themeColorHex: nil, analysisSegmentOrder: nil, showPreviousMonthCarryover: false,
                creditCardAssetReflectionTiming: nil, accountingMonthStartDay: nil,
                accountingMonthWeekendHolidayAdjustment: nil, accountingMonthLabelBasis: nil,
                calendarWeekStartWeekday: nil
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionMoneyColorBackup_\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await BackupManager().restore(from: url, targetBookId: main.book.id)

        let restoredCash = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.cash.id }
        let restoredBank = BankAccountDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.bankAccount.id }
        XCTAssertEqual(restoredCash?.colorHex, "#FF00FF")
        XCTAssertEqual(restoredBank?.colorHex, "#00FFAA")
    }

    // MARK: - 実SQLite永続ストアでの再起動相当テスト

    func testColorHexSurvivesRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionColorRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)
        var cash = PaymentMethodSettingData(methodName: "現金", type: PaymentMethodType.cash.rawValue)
        cash.bookId = book.id
        cash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.insert(cash)
        var bank = BankAccountData(accountName: "三井住友銀行")
        bank.bookId = book.id
        bank.colorHex = "#82C08A"
        BankAccountDataSync.insert(bank)

        // アプリ終了→再起動に相当
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let restoredCash = PaymentMethodSettingDataSync.fetchAll(bookId: book.id).first
        let restoredBank = BankAccountDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(restoredCash?.colorHex, "#4A7DBA")
        XCTAssertEqual(restoredBank?.colorHex, "#82C08A")
    }
}
