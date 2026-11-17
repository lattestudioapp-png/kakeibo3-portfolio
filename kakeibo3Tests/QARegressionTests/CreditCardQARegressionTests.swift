// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 注意: 締め日/引き落とし日から対象期間を計算するロジック(billingPeriod)は
// Components/Analysis/CreditCardDueCard.swift の private メソッドであり、本番コードを
// テスト用に変更しないという方針のため @testable importでも直接呼び出せない。
// ここでは同じ計算式をテスト内に再現し、ロジックの回帰を検知する
// （BookQARegressionTestsのcanSaveBookNameと同じ方針）。
// HolidayCalendarService は internal のため直接呼び出して検証する。

import XCTest
@testable import kakeibo3

final class CreditCardQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - CreditCardDueCard.billingPeriod の再現（回帰検知用）

    private func billingPeriod(for withdrawalDate: Date, closingDay: Int, withdrawalDay: Int, cal: Calendar = .current) -> (start: Date, end: Date) {
        let offset = (closingDay < withdrawalDay) ? 0 : -1
        guard
            let withdrawalMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: withdrawalDate)),
            let billingEndMonthStart = cal.date(byAdding: .month, value: offset, to: withdrawalMonthStart)
        else { return (withdrawalDate, withdrawalDate) }

        let daysInBillingEnd = cal.range(of: .day, in: .month, for: billingEndMonthStart)?.count ?? 28
        var billingEndComponents = cal.dateComponents([.year, .month], from: billingEndMonthStart)
        billingEndComponents.day = min(closingDay, daysInBillingEnd)
        let billingEnd = cal.date(from: billingEndComponents) ?? withdrawalDate

        guard let prevMonthStart = cal.date(byAdding: .month, value: -1, to: billingEndMonthStart) else {
            return (billingEnd, billingEnd)
        }
        let daysInPrev = cal.range(of: .day, in: .month, for: prevMonthStart)?.count ?? 28
        var prevEndComponents = cal.dateComponents([.year, .month], from: prevMonthStart)
        prevEndComponents.day = min(closingDay, daysInPrev)
        let prevEnd = cal.date(from: prevEndComponents) ?? billingEnd
        let billingStart = cal.date(byAdding: .day, value: 1, to: prevEnd) ?? billingEnd

        return (start: billingStart, end: billingEnd)
    }

    // MARK: - カード名・締め日・引き落とし日の保存

    func testCanSaveCardNameClosingDayAndWithdrawalDay() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertEqual(main.creditCard.methodName, "テストカード")
        XCTAssertEqual(main.creditCard.closingDay, 15)
        XCTAssertEqual(main.creditCard.withdrawalDay, 10)
    }

    // MARK: - 引き落とし口座

    func testCanSetWithdrawalBankAccount() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var creditCard = main.creditCard
        creditCard.withdrawalBankAccountId = main.bankAccount.id
        PaymentMethodSettingDataSync.update(creditCard)

        XCTAssertEqual(creditCard.withdrawalBankAccountId, main.bankAccount.id)
    }

    func testOnlyCurrentBookBankAccountsAreSelectable() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBankAccounts = BankAccountDataSync.fetchAll()
        let selectable = allBankAccounts.filter { $0.bookId == main.book.id && $0.isActive }
        XCTAssertFalse(selectable.contains { $0.id == business.bankAccount.id })
        XCTAssertTrue(selectable.contains { $0.id == main.bankAccount.id })
    }

    // MARK: - 既知バグ: 削除済み銀行口座がクレカ編集画面に残る

    func testDeletedWithdrawalBankAccountResetsToUnselected() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var creditCard = main.creditCard
        creditCard.withdrawalBankAccountId = main.bankAccount.id
        PaymentMethodSettingDataSync.update(creditCard)

        var bankAccount = main.bankAccount
        bankAccount.isActive = false
        BankAccountDataSync.update(bankAccount)

        // CreditCardEditView.onAppear と同じ判定（bookId一致 + isActive）
        let allBankAccounts = BankAccountDataSync.fetchAll(bookId: main.book.id)
        func resolveSelectedBankAccountId(linkedId: UUID?) -> UUID? {
            guard let linkedId, allBankAccounts.contains(where: { $0.id == linkedId && $0.isActive }) else { return nil }
            return linkedId
        }
        XCTAssertNil(resolveSelectedBankAccountId(linkedId: creditCard.withdrawalBankAccountId))
    }

    // MARK: - 支払い候補への表示

    func testCreditCardAppearsInPaymentCandidatesWhenShowInInputPickerIsOn() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var creditCard = main.creditCard
        creditCard.showInInputPicker = true
        PaymentMethodSettingDataSync.update(creditCard)
        XCTAssertTrue(creditCard.showInInputPicker)
    }

    func testCreditCardHiddenFromPaymentCandidatesWhenShowInInputPickerIsOff() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var creditCard = main.creditCard
        creditCard.showInInputPicker = false
        PaymentMethodSettingDataSync.update(creditCard)
        XCTAssertFalse(creditCard.showInInputPicker)
    }

    func testCreditCardIsExcludedFromTransferParticipants() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allPaymentMethods = PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id)
        let participants = TransferParticipantBuilder.build(bankAccounts: [], paymentMethods: allPaymentMethods, receiveMethods: [])
        XCTAssertFalse(participants.contains { $0.id == main.creditCard.id })
    }

    // MARK: - クレカ支出の集計

    func testCreditCardExpenseIsIncludedInExpenseTotal() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let expense = QARegressionTestFactory.makeExpense(amount: 3000, paymentMethod: "テストカード", category: "食費", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll().filter { $0.bookId == main.book.id }
        XCTAssertTrue(allExpenses.contains { $0.id == expense.id })
        XCTAssertEqual(allExpenses.reduce(0) { $0 + $1.amount }, 3000)
    }

    // MARK: - 締め日をまたぐ集計（billingPeriod再現ロジック）

    func testExpenseBeforeClosingDayBelongsToCurrentCycle() throws {
        // 締め日15日・引き落とし日10日 → 6/16〜7/15 が 8/10引き落とし分
        let withdrawalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let period = billingPeriod(for: withdrawalDate, closingDay: 15, withdrawalDay: 10)

        let expectedStart = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let expectedEnd = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        XCTAssertEqual(Calendar.current.startOfDay(for: period.start), Calendar.current.startOfDay(for: expectedStart))
        XCTAssertEqual(Calendar.current.startOfDay(for: period.end), Calendar.current.startOfDay(for: expectedEnd))
    }

    func testExpenseAfterClosingDayBelongsToNextCycle() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let withdrawalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let period = billingPeriod(for: withdrawalDate, closingDay: 15, withdrawalDay: 10)
        let periodStart = Calendar.current.startOfDay(for: period.start)
        let periodEndExclusive = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: period.end))!

        // 締め日(7/15)当日の支出は今サイクルに含まれる
        let onClosingDay = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        QARegressionTestFactory.makeExpense(amount: 1000, date: onClosingDay, paymentMethod: "テストカード", category: "食費", bookId: main.book.id)
        // 締め日翌日(7/16)の支出は次サイクルに含まれる(今回のperiodには含まれない)
        let afterClosingDay = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 16))!
        QARegressionTestFactory.makeExpense(amount: 2000, date: afterClosingDay, paymentMethod: "テストカード", category: "食費", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll().filter { $0.bookId == main.book.id }
        let amountInCycle = allExpenses
            .filter { $0.paymentMethod == "テストカード" && $0.date >= periodStart && $0.date < periodEndExclusive }
            .reduce(0) { $0 + $1.amount }

        XCTAssertEqual(amountInCycle, 1000)
    }

    // MARK: - 土日祝の引き落とし日補正

    func testWeekendWithdrawalDateShiftsToNextBusinessDayWhenAdjustmentEnabled() throws {
        // 2026/8/8は土曜日
        let saturdayWithdrawal = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        XCTAssertTrue(HolidayCalendarService.isNonBusinessDay(saturdayWithdrawal))

        let shifted = HolidayCalendarService.nextBusinessDay(from: saturdayWithdrawal)
        XCTAssertFalse(HolidayCalendarService.isNonBusinessDay(shifted))
        XCTAssertGreaterThan(shifted, saturdayWithdrawal)
    }

    func testAdjustmentDisabledKeepsWithdrawalDateOnWeekend() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var creditCard = main.creditCard
        creditCard.adjustPaymentDateToNextBusinessDay = false
        PaymentMethodSettingDataSync.update(creditCard)

        let saturdayWithdrawal = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 8))!
        // adjustPaymentDateToNextBusinessDay=false の場合、CreditCardDueCard.dueInfo は
        // withdrawalDateをそのまま使う（HolidayCalendarServiceを呼ばない）
        let displayDate: Date = {
            guard creditCard.adjustPaymentDateToNextBusinessDay,
                  HolidayCalendarService.isNonBusinessDay(saturdayWithdrawal) else { return saturdayWithdrawal }
            return HolidayCalendarService.nextBusinessDay(from: saturdayWithdrawal)
        }()
        XCTAssertEqual(displayDate, saturdayWithdrawal)
    }

    func testHolidayCalendarServiceRecognizesJapaneseHoliday() throws {
        // 2026/1/1 元日
        let newYearsDay = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        XCTAssertTrue(HolidayCalendarService.isJapaneseHoliday(newYearsDay))
        XCTAssertTrue(HolidayCalendarService.isNonBusinessDay(newYearsDay))
    }

    // MARK: - 同名カードが別帳簿にあっても混ざらない

    func testSameNameCreditCardDoesNotMixAcrossBooks() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var mainCard = main.creditCard
        mainCard.closingDay = 15
        PaymentMethodSettingDataSync.update(mainCard)
        var businessCard = business.creditCard
        businessCard.closingDay = 20
        PaymentMethodSettingDataSync.update(businessCard)

        XCTAssertNotEqual(mainCard.id, businessCard.id)
        XCTAssertEqual(mainCard.methodName, businessCard.methodName)
        XCTAssertNotEqual(mainCard.closingDay, businessCard.closingDay)
    }

    func testCannotCreateDuplicateCreditCardNameInSameBook() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertTrue(
            DuplicateNameChecker.isDuplicatePaymentMethodName(
                "テストカード", type: PaymentMethodType.creditCard.rawValue, bookId: main.book.id, excluding: nil
            )
        )
    }
}
