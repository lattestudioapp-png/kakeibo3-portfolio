// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 金融機関休業日の個別設定（固定費/定期収入/定期振替/クレジットカード引落）の回帰テスト。

import XCTest
@testable import kakeibo3

final class HolidayAdjustmentQARegressionTests: QARegressionTestCase {

    // MARK: - 日付ヘルパー

    private let cal = Calendar.current

    /// supportedYearRange内で、指定条件を満たす最初の日付を今日から探す
    private func firstDate(from start: Date, matching predicate: (Date) -> Bool, maxDays: Int = 400) -> Date {
        var date = start
        for _ in 0..<maxDays {
            if predicate(date) { return date }
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        fatalError("条件を満たす日付が見つかりませんでした")
    }

    private var aNonBusinessDay: Date {
        firstDate(from: Date(), matching: { HolidayCalendarService.isNonBusinessDay($0) })
    }

    private var aBusinessDay: Date {
        firstDate(from: Date(), matching: { !HolidayCalendarService.isNonBusinessDay($0) })
    }

    /// RecurringEntryGeneratorは「設定日がまだ来ていない当月ぶんは生成しない」ため、
    /// 固定費/定期収入のテストでは必ず「今日以前に実際に発生した休業日」を使う必要がある。
    /// 未来の休業日のday-of-monthを別の月に転用すると、その月の同じ日は別の曜日になり
    /// 休業日とは限らないため、過去方向に探索した実在の日付をそのまま使う。
    private var aPastNonBusinessDay: Date {
        var date = cal.startOfDay(for: Date())
        for _ in 0..<60 {
            if HolidayCalendarService.isNonBusinessDay(date) { return date }
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }
        fatalError("過去60日以内に休業日が見つかりませんでした")
    }

    // MARK: - PaymentMethodSettingData.resolvedHolidayAdjustment

    func testResolvedHolidayAdjustmentFallsBackToLegacyBoolWhenNotSet() {
        var card = PaymentMethodSettingData(methodName: "テストカード", type: PaymentMethodType.creditCard.rawValue)
        card.holidayAdjustment = nil
        card.adjustPaymentDateToNextBusinessDay = true
        XCTAssertEqual(card.resolvedHolidayAdjustment, .shiftLater)

        card.adjustPaymentDateToNextBusinessDay = false
        XCTAssertEqual(card.resolvedHolidayAdjustment, .none)
    }

    func testResolvedHolidayAdjustmentUsesNewValueOverLegacyBoolWhenSet() {
        var card = PaymentMethodSettingData(methodName: "テストカード", type: PaymentMethodType.creditCard.rawValue)
        card.adjustPaymentDateToNextBusinessDay = true // 旧値は無視されるべき
        card.holidayAdjustment = WeekendHolidayAdjustment.shiftEarlier.rawValue
        XCTAssertEqual(card.resolvedHolidayAdjustment, .shiftEarlier)
    }

    // MARK: - HolidayCalendarService.adjustedDate

    func testAdjustedDateNoneNeverChangesDate() {
        let holiday = aNonBusinessDay
        XCTAssertEqual(HolidayCalendarService.adjustedDate(for: holiday, adjustment: .none), holiday)
    }

    func testAdjustedDateShiftLaterMovesToNextBusinessDay() {
        let holiday = aNonBusinessDay
        let adjusted = HolidayCalendarService.adjustedDate(for: holiday, adjustment: .shiftLater)
        XCTAssertEqual(adjusted, HolidayCalendarService.nextBusinessDay(from: holiday))
        XCTAssertFalse(HolidayCalendarService.isNonBusinessDay(adjusted))
    }

    func testAdjustedDateShiftEarlierMovesToPreviousBusinessDay() {
        let holiday = aNonBusinessDay
        let adjusted = HolidayCalendarService.adjustedDate(for: holiday, adjustment: .shiftEarlier)
        XCTAssertEqual(adjusted, HolidayCalendarService.previousBusinessDay(from: holiday))
        XCTAssertFalse(HolidayCalendarService.isNonBusinessDay(adjusted))
    }

    func testAdjustedDateDoesNotChangeAlreadyBusinessDay() {
        let businessDay = aBusinessDay
        XCTAssertEqual(HolidayCalendarService.adjustedDate(for: businessDay, adjustment: .shiftLater), businessDay)
        XCTAssertEqual(HolidayCalendarService.adjustedDate(for: businessDay, adjustment: .shiftEarlier), businessDay)
    }

    // MARK: - 固定費：銀行口座の場合のみ休日調整が適用される

    func testFixedExpenseHolidayAdjustmentOnlyAppliesWhenPaymentMethodIsBankAccount() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        let holiday = aPastNonBusinessDay
        let day = cal.component(.day, from: holiday)
        let startDate = cal.date(byAdding: .month, value: -2, to: holiday)!

        // 現金払い（銀行口座ではない）：休日でも調整されない
        var cashFixed = FixedExpenseData(
            name: "現金固定費", amount: 1000, categoryName: "食費",
            paymentMethodType: "paymentMethod", paymentMethodId: main.cash.id,
            dayOfMonth: day, startDate: startDate
        )
        cashFixed.bookId = main.book.id
        cashFixed.holidayAdjustment = WeekendHolidayAdjustment.shiftLater.rawValue
        FixedExpenseDataSync.insert(cashFixed)
        RecurringEntryGenerator.generateExpenseEntries(for: cashFixed, methodName: "現金", bookId: main.book.id)

        let cashGenerated = ExpenseDataSync.fetchAll(bookId: main.book.id).filter { $0.fixedExpenseId == cashFixed.id }
        XCTAssertTrue(cashGenerated.contains { cal.isDate($0.date, inSameDayAs: holiday) },
                      "現金払いは休日調整の対象外なので、予定通りの休日に生成されること")
    }

    func testFixedExpenseHolidayAdjustmentAppliesWhenPaymentMethodIsBankAccount() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        let holiday = aPastNonBusinessDay
        let day = cal.component(.day, from: holiday)
        let startDate = cal.date(byAdding: .month, value: -2, to: holiday)!

        var bankFixed = FixedExpenseData(
            name: "銀行固定費", amount: 2000, categoryName: "食費",
            paymentMethodType: "bankAccount", paymentMethodId: main.bankAccount.id,
            dayOfMonth: day, startDate: startDate
        )
        bankFixed.bookId = main.book.id
        bankFixed.holidayAdjustment = WeekendHolidayAdjustment.shiftLater.rawValue
        FixedExpenseDataSync.insert(bankFixed)
        RecurringEntryGenerator.generateExpenseEntries(for: bankFixed, methodName: "三井住友銀行", bookId: main.book.id)

        let bankGenerated = ExpenseDataSync.fetchAll(bookId: main.book.id).filter { $0.fixedExpenseId == bankFixed.id }
        let expectedDate = HolidayCalendarService.adjustedDate(for: holiday, adjustment: .shiftLater)
        XCTAssertTrue(bankGenerated.contains { cal.isDate($0.date, inSameDayAs: expectedDate) },
                      "銀行口座払いは休日調整後の営業日に生成されること")
        XCTAssertFalse(bankGenerated.contains { cal.isDate($0.date, inSameDayAs: holiday) } && !cal.isDate(holiday, inSameDayAs: expectedDate),
                       "調整前の休日そのままでは生成されないこと")
    }

    // MARK: - 二重生成防止（generatedScheduleMonths）

    func testFixedExpenseGenerationRemainsIdempotentWithHolidayAdjustment() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        let holiday = aPastNonBusinessDay
        let day = cal.component(.day, from: holiday)
        let startDate = cal.date(byAdding: .month, value: -3, to: holiday)!

        var bankFixed = FixedExpenseData(
            name: "銀行固定費", amount: 3000, categoryName: "食費",
            paymentMethodType: "bankAccount", paymentMethodId: main.bankAccount.id,
            dayOfMonth: day, startDate: startDate
        )
        bankFixed.bookId = main.book.id
        bankFixed.holidayAdjustment = WeekendHolidayAdjustment.shiftLater.rawValue
        FixedExpenseDataSync.insert(bankFixed)

        RecurringEntryGenerator.generateExpenseEntries(for: bankFixed, methodName: "三井住友銀行", bookId: main.book.id)
        let firstCount = ExpenseDataSync.fetchAll(bookId: main.book.id).filter { $0.fixedExpenseId == bankFixed.id }.count

        RecurringEntryGenerator.generateExpenseEntries(for: bankFixed, methodName: "三井住友銀行", bookId: main.book.id)
        let secondCount = ExpenseDataSync.fetchAll(bookId: main.book.id).filter { $0.fixedExpenseId == bankFixed.id }.count

        XCTAssertEqual(firstCount, secondCount, "休日調整で反映日がずれても、同じ月を二重生成しないこと")
        XCTAssertGreaterThan(firstCount, 0)

        let stored = FixedExpenseDataSync.fetchAll(bookId: main.book.id).first { $0.id == bankFixed.id }
        XCTAssertFalse(stored?.generatedScheduleMonths.isEmpty ?? true, "生成済み予定月が記録されること")
    }

    // MARK: - 後方互換：休日調整機能追加前のデータからの復元

    func testGeneratedScheduleMonthsIsRestoredFromExistingExpensesWhenEmpty() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        let lastMonth = cal.date(byAdding: .month, value: -1, to: Date())!

        var fixedExpense = FixedExpenseData(
            name: "家賃", amount: 80000, categoryName: "食費",
            paymentMethodType: "paymentMethod", paymentMethodId: main.cash.id,
            dayOfMonth: 1, startDate: lastMonth
        )
        fixedExpense.bookId = main.book.id
        XCTAssertTrue(fixedExpense.generatedScheduleMonths.isEmpty)
        FixedExpenseDataSync.insert(fixedExpense)

        // 休日調整機能が無かった頃に生成されたデータを模して、既存のExpenseDataを直接作る
        var existingEntry = ExpenseData(amount: 80000, date: lastMonth, paymentMethod: "現金", category: "食費", memo: "")
        existingEntry.fixedExpenseId = fixedExpense.id
        existingEntry.bookId = main.book.id
        ExpenseDataSync.insert(existingEntry)

        RecurringEntryGenerator.generateExpenseEntries(for: fixedExpense, methodName: "現金", bookId: main.book.id)

        let generated = ExpenseDataSync.fetchAll(bookId: main.book.id).filter { $0.fixedExpenseId == fixedExpense.id }
        let uniqueMonths = Set(generated.map { cal.dateComponents([.year, .month], from: $0.date) })
        XCTAssertEqual(generated.count, uniqueMonths.count, "既存データの月を復元し、二重生成しないこと")

        let stored = FixedExpenseDataSync.fetchAll(bookId: main.book.id).first { $0.id == fixedExpense.id }
        XCTAssertFalse(stored?.generatedScheduleMonths.isEmpty ?? true)
    }

    // MARK: - バックアップ・復元でholidayAdjustment/generatedScheduleMonthsが保持される

    func testScopedRestorePreservesHolidayAdjustmentAndGeneratedScheduleMonths() async throws {
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
                    isTestData: false, bookId: main.book.id, isLocked: false, colorHex: nil,
                    holidayAdjustment: WeekendHolidayAdjustment.shiftEarlier.rawValue
                )
            ],
            receiveMethods: [],
            bankAccounts: [],
            budgets: [], recurringBudgets: [],
            fixedExpenses: [
                FixedExpenseBackupItem(
                    id: UUID(), name: "テスト固定費", amount: 1000, categoryName: "食費",
                    paymentMethodType: "bankAccount", paymentMethodId: main.bankAccount.id,
                    dayOfMonth: 1, startDate: Date(), memo: "", isActive: true,
                    createdAt: Date(), updatedAt: Date(), isTestData: false, bookId: main.book.id,
                    isLocked: false, holidayAdjustment: WeekendHolidayAdjustment.shiftEarlier.rawValue,
                    generatedScheduleMonths: ["2026-1", "2026-2"]
                )
            ],
            recurringIncomes: [],
            recurringTransfers: [],
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionHolidayAdjustmentBackup_\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await BackupManager().restore(from: url, targetBookId: main.book.id)

        let restoredCash = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.cash.id }
        XCTAssertEqual(restoredCash?.holidayAdjustment, WeekendHolidayAdjustment.shiftEarlier.rawValue)

        let restoredFixed = FixedExpenseDataSync.fetchAll(bookId: main.book.id).first { $0.name == "テスト固定費" }
        XCTAssertEqual(restoredFixed?.holidayAdjustment, WeekendHolidayAdjustment.shiftEarlier.rawValue)
        XCTAssertEqual(Set(restoredFixed?.generatedScheduleMonths ?? []), Set(["2026-1", "2026-2"]))
    }

    // MARK: - 旧バックアップ（holidayAdjustment/generatedScheduleMonthsが無い）との後方互換

    func testLegacyBackupWithoutHolidayAdjustmentFieldsRestoresSafeDefaults() async throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 旧バックアップのJSONを模して、holidayAdjustment/generatedScheduleMonthsキー自体を含めない
        let legacyJSON = """
        {
          "version": 1,
          "createdAt": "2026-01-01T00:00:00Z",
          "expenses": [], "incomes": [], "transfers": [], "categories": [],
          "paymentMethods": [{
            "id": "\(main.cash.id.uuidString)",
            "methodName": "現金", "type": "cash",
            "closingDay": null, "withdrawalDay": null,
            "adjustPaymentDateToNextBusinessDay": true,
            "bankAccount": null, "withdrawalBankAccountId": null,
            "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z",
            "sortOrder": 0, "isActive": true, "isAsset": true,
            "assetInitialBalance": null, "includeInAnalysis": true,
            "assetInitialBalanceIncomeId": null,
            "showInInputPicker": true, "useForReceive": true, "showInAnalysis": true,
            "recurringTransferSettingId": null, "recurringTransferSettingIds": [],
            "isTestData": false, "bookId": "\(main.book.id.uuidString)"
          }],
          "receiveMethods": [], "bankAccounts": [], "budgets": [], "recurringBudgets": [],
          "fixedExpenses": [{
            "id": "\(UUID().uuidString)",
            "name": "旧固定費", "amount": 500, "categoryName": "食費",
            "paymentMethodType": "bankAccount", "paymentMethodId": "\(main.bankAccount.id.uuidString)",
            "dayOfMonth": 1, "startDate": "2026-01-01T00:00:00Z", "memo": "",
            "isActive": true, "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z",
            "isTestData": false, "bookId": "\(main.book.id.uuidString)"
          }],
          "recurringIncomes": [], "recurringTransfers": [],
          "settings": {
            "themeColorHex": null, "analysisSegmentOrder": null, "showPreviousMonthCarryover": false,
            "creditCardAssetReflectionTiming": null, "accountingMonthStartDay": null,
            "accountingMonthWeekendHolidayAdjustment": null, "accountingMonthLabelBasis": null,
            "calendarWeekStartWeekday": null
          }
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionLegacyHolidayBackup_\(UUID().uuidString).json")
        try legacyJSON.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try await BackupManager().restore(from: url, targetBookId: main.book.id)
        } catch {
            XCTFail("復元が失敗しないはずだが例外が発生した: \(error)")
        }

        let restoredCash = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id).first { $0.id == main.cash.id }
        XCTAssertNil(restoredCash?.holidayAdjustment, "旧バックアップにキーが無い場合はnil（resolvedHolidayAdjustmentが旧Boolからフォールバック導出する）")

        let restoredFixed = FixedExpenseDataSync.fetchAll(bookId: main.book.id).first { $0.name == "旧固定費" }
        XCTAssertEqual(restoredFixed?.holidayAdjustment, WeekendHolidayAdjustment.shiftLater.rawValue, "欠落時は安全なデフォルト(翌営業日)で復元されること")
        XCTAssertEqual(restoredFixed?.generatedScheduleMonths, [], "欠落時は空配列で復元されること")
    }

    // MARK: - 実SQLite永続ストアでの再起動相当テスト

    func testHolidayAdjustmentSurvivesRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionHolidayRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let book = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(book)

        var fixedExpense = FixedExpenseData(name: "家賃", amount: 80000, categoryName: "食費", dayOfMonth: 1)
        fixedExpense.bookId = book.id
        fixedExpense.holidayAdjustment = WeekendHolidayAdjustment.shiftEarlier.rawValue
        fixedExpense.generatedScheduleMonths = ["2026-1", "2026-2"]
        FixedExpenseDataSync.insert(fixedExpense)

        var card = PaymentMethodSettingData(methodName: "テストカード", type: PaymentMethodType.creditCard.rawValue)
        card.bookId = book.id
        card.holidayAdjustment = WeekendHolidayAdjustment.shiftEarlier.rawValue
        PaymentMethodSettingDataSync.insert(card)

        // アプリ終了→再起動に相当
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let restoredFixed = FixedExpenseDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(restoredFixed?.holidayAdjustment, WeekendHolidayAdjustment.shiftEarlier.rawValue)
        XCTAssertEqual(Set(restoredFixed?.generatedScheduleMonths ?? []), Set(["2026-1", "2026-2"]))

        let restoredCard = PaymentMethodSettingDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(restoredCard?.holidayAdjustment, WeekendHolidayAdjustment.shiftEarlier.rawValue)
    }

    // MARK: - 他帳簿非影響

    func testHolidayAdjustmentDoesNotAffectOtherBook() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var mainCard = main.creditCard
        mainCard.holidayAdjustment = WeekendHolidayAdjustment.shiftEarlier.rawValue
        PaymentMethodSettingDataSync.update(mainCard)

        let businessCard = PaymentMethodSettingDataSync.fetchAll(bookId: business.book.id).first { $0.id == business.creditCard.id }
        XCTAssertNil(businessCard?.holidayAdjustment)
    }
}
