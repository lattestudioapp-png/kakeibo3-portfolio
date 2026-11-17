// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 注意: このアプリには「No Money Day」に相当する機能が存在しない（調査で確認済み）。
// そのため関連項目は dailyTotal.expense == 0 を代替指標として検証する。

import XCTest
@testable import kakeibo3

final class CalendarQARegressionTests: QARegressionTestCase {
    private let calculator = CalendarTransactionCalculator()
    private let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 帳簿スコープ

    func testCalendarOnlyIncludesCurrentBookExpenses() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 300, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 999, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        let allExpenses = ExpenseDataSync.fetchAll()
        let mainTotal = calculator.monthlyTotal(
            selectedDate: referenceDate,
            incomeDataList: [],
            expenseDataList: allExpenses.filter { $0.bookId == main.book.id }
        )
        XCTAssertEqual(mainTotal.expense, 300)
    }

    func testCalendarOnlyIncludesCurrentBookIncomes() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeIncome(amount: 5000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 9999, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: business.book.id)

        let allIncomes = IncomeDataSync.fetchAll()
        let mainTotal = calculator.monthlyTotal(
            selectedDate: referenceDate,
            incomeDataList: allIncomes.filter { $0.bookId == main.book.id },
            expenseDataList: []
        )
        XCTAssertEqual(mainTotal.income, 5000)
    }

    func testOtherBookTransactionsAreNotIncludedInCalendarAtAll() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        let allExpenses = ExpenseDataSync.fetchAll()
        let mainTotal = calculator.monthlyTotal(
            selectedDate: referenceDate,
            incomeDataList: [],
            expenseDataList: allExpenses.filter { $0.bookId == main.book.id }
        )
        XCTAssertEqual(mainTotal.expense, 0)
    }

    // MARK: - 日別/月別合計

    func testDailyTotalIsCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 200, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 300, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let daily = calculator.dailyTotal(date: referenceDate, incomeDataList: [], expenseDataList: allExpenses)
        XCTAssertEqual(daily.expense, 500)
    }

    func testMonthlyExpenseTotalIsCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 100, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: referenceDate)!
        QARegressionTestFactory.makeExpense(amount: 5000, date: nextMonth, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let total = calculator.monthlyTotal(selectedDate: referenceDate, incomeDataList: [], expenseDataList: allExpenses)
        XCTAssertEqual(total.expense, 100) // 翌月分は含まれない
    }

    func testMonthlyIncomeTotalIsCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeIncome(amount: 250000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let allIncomes = IncomeDataSync.fetchAll(bookId: main.book.id)
        let total = calculator.monthlyTotal(selectedDate: referenceDate, incomeDataList: allIncomes, expenseDataList: [])
        XCTAssertEqual(total.income, 250000)
    }

    func testMonthlyBalanceIsIncomeMinusExpense() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeIncome(amount: 3000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 1200, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allIncomes = IncomeDataSync.fetchAll(bookId: main.book.id)
        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let total = calculator.monthlyTotal(selectedDate: referenceDate, incomeDataList: allIncomes, expenseDataList: allExpenses)
        XCTAssertEqual(total.balance, 1800)
    }

    // MARK: - 支出が0の日(No Money Day相当)

    func testDayWithNoExpenseHasZeroExpenseTotal() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeIncome(amount: 1000, date: referenceDate, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let allIncomes = IncomeDataSync.fetchAll(bookId: main.book.id)
        let daily = calculator.dailyTotal(date: referenceDate, incomeDataList: allIncomes, expenseDataList: [])
        XCTAssertEqual(daily.expense, 0) // 収入のみの日は支出0円
    }

    // MARK: - 月/年またぎ

    func testCalculationAcrossYearBoundary() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let decDate = Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 20))!
        let janDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        QARegressionTestFactory.makeExpense(amount: 1000, date: decDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 2000, date: janDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let decTotal = calculator.monthlyTotal(selectedDate: decDate, incomeDataList: [], expenseDataList: allExpenses)
        let janTotal = calculator.monthlyTotal(selectedDate: janDate, incomeDataList: [], expenseDataList: allExpenses)

        XCTAssertEqual(decTotal.expense, 1000)
        XCTAssertEqual(janTotal.expense, 2000)
    }

    // MARK: - 会計月の開始日設定（月開始日10日）

    func testAccountingMonthStartDaySettingAffectsPeriodBounds() throws {
        UserDefaults.standard.set(10, forKey: AccountingMonthSettings.startDayStorageKey)

        let range = AccountingMonthCalculator.range(containing: referenceDate)
        XCTAssertNotNil(range)
        // 開始日=10なら、7/15は7/10〜8/9の期間に属する
        let startComponents = Calendar.current.dateComponents([.month, .day], from: range!.actualStartDate)
        XCTAssertEqual(startComponents.day, 10)
        XCTAssertEqual(startComponents.month, 7)
    }

    func testDefaultAccountingMonthStartDayMatchesCalendarMonth() throws {
        UserDefaults.standard.removeObject(forKey: AccountingMonthSettings.startDayStorageKey)

        let range = AccountingMonthCalculator.range(containing: referenceDate)
        XCTAssertNotNil(range)
        let startComponents = Calendar.current.dateComponents([.day], from: range!.actualStartDate)
        XCTAssertEqual(startComponents.day, 1)
    }

    // MARK: - カレンダー開始曜日設定

    func testCalendarWeekStartWeekdaySettingIsRespected() throws {
        UserDefaults.standard.set(2, forKey: CalendarWeekStartSettings.storageKey) // 月曜始まり
        let mondayStartCalendar = calculator.calendar
        XCTAssertEqual(mondayStartCalendar.firstWeekday, 2)

        UserDefaults.standard.set(1, forKey: CalendarWeekStartSettings.storageKey) // 日曜始まり
        let sundayStartCalendar = calculator.calendar
        XCTAssertEqual(sundayStartCalendar.firstWeekday, 1)
    }

    // MARK: - 編集後の反映

    func testEditingTransactionReflectsInSameBookOnly() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var expense = QARegressionTestFactory.makeExpense(amount: 500, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        expense.amount = 1500
        ExpenseDataSync.update(expense)

        let allExpenses = ExpenseDataSync.fetchAll()
        let mainTotal = calculator.monthlyTotal(selectedDate: referenceDate, incomeDataList: [], expenseDataList: allExpenses.filter { $0.bookId == main.book.id })
        let businessTotal = calculator.monthlyTotal(selectedDate: referenceDate, incomeDataList: [], expenseDataList: allExpenses.filter { $0.bookId == business.book.id })

        XCTAssertEqual(mainTotal.expense, 1500)
        XCTAssertEqual(businessTotal.expense, 0)
    }

    func testDeletingTransactionUpdatesCalendarTotal() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let expense = QARegressionTestFactory.makeExpense(amount: 500, date: referenceDate, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        ExpenseDataSync.delete(id: expense.id)

        let allExpenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        let total = calculator.monthlyTotal(selectedDate: referenceDate, incomeDataList: [], expenseDataList: allExpenses)
        XCTAssertEqual(total.expense, 0)
    }

    // MARK: - 不具合回帰：カレンダー下部の取引履歴リストが月切り替え後も古い月のまま
    //
    // 背景：MonthlyTransactionListViewは@StateObjectでCore Data observerの
    // NSPredicate（日付範囲・bookId）をinit時点に一度だけ構築する。SwiftUIは同じ型・同じ
    // 構造上の位置にある子Viewを明示的なIDの変更なしに再利用し続けるため、.id()を
    // 付けていないと、カレンダーの月を切り替えても（またはbookIdが別の帳簿に変わっても）
    // 一番最初に表示した月のobserverのまま固定され、以後ずっと古い月の取引が表示され
    // 続けていた（実機で確認：9月1日の支出がカレンダーの日付セル・日付別一覧には
    // 正しく表示されるのに、下部の取引履歴リストには10月の取引が表示されたままだった）。
    //
    // 修正：CalendarView.monthlyTransactionListIdentity(bookId:selectedDate:)で
    // 会計月のanchor(月の開始日設定を反映した実際の期間の単位)とbookIdからキーを作り、
    // MonthlyTransactionListViewへ.id()として渡すことで、月またぎ・帳簿切り替え時に
    // 確実に新しいobserverへ作り直させる。このテストは、そのキー計算自体を
    // SwiftUIのView識別機構やCore Data接続を介さずに決定的に検証する。

    func testMonthlyTransactionListIdentityChangesWhenAccountingMonthChanges() throws {
        let bookId = UUID()
        let septemberDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let octoberDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19))!

        let septemberKey = CalendarView.monthlyTransactionListIdentity(bookId: bookId, selectedDate: septemberDate)
        let octoberKey = CalendarView.monthlyTransactionListIdentity(bookId: bookId, selectedDate: octoberDate)

        XCTAssertNotEqual(
            septemberKey, octoberKey,
            "異なる会計月を選択した場合、取引履歴リストのobserverを作り直すため識別キーが変わること"
        )
    }

    func testMonthlyTransactionListIdentityChangesWhenBookChanges() throws {
        let bookA = UUID()
        let bookB = UUID()

        let keyA = CalendarView.monthlyTransactionListIdentity(bookId: bookA, selectedDate: referenceDate)
        let keyB = CalendarView.monthlyTransactionListIdentity(bookId: bookB, selectedDate: referenceDate)

        XCTAssertNotEqual(
            keyA, keyB,
            "帳簿を切り替えた場合、取引履歴リストのobserverを作り直すため識別キーが変わること"
        )
    }

    func testMonthlyTransactionListIdentityStaysStableWithinSameAccountingMonth() throws {
        let bookId = UUID()
        let septemberFirst = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let septemberFifteenth = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15))!

        let keyFirst = CalendarView.monthlyTransactionListIdentity(bookId: bookId, selectedDate: septemberFirst)
        let keyFifteenth = CalendarView.monthlyTransactionListIdentity(bookId: bookId, selectedDate: septemberFifteenth)

        XCTAssertEqual(
            keyFirst, keyFifteenth,
            "同じ会計月内で選択日だけが変わっても、識別キーは変えずobserverを不要に作り直さないこと" +
            "(スクロール位置等を無駄に失わないため)"
        )
    }

    func testMonthlyTransactionListIdentityRespectsCustomAccountingMonthStartDay() throws {
        UserDefaults.standard.set(10, forKey: AccountingMonthSettings.startDayStorageKey)
        defer { UserDefaults.standard.removeObject(forKey: AccountingMonthSettings.startDayStorageKey) }

        let bookId = UUID()
        // 開始日=10の設定では、9/9はまだ8/10〜9/9の会計期間に属し、9/10から新しい会計期間になる。
        let stillPreviousPeriod = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let newPeriodStart = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10))!

        let keyBefore = CalendarView.monthlyTransactionListIdentity(bookId: bookId, selectedDate: stillPreviousPeriod)
        let keyAfter = CalendarView.monthlyTransactionListIdentity(bookId: bookId, selectedDate: newPeriodStart)

        XCTAssertNotEqual(
            keyBefore, keyAfter,
            "会計月の開始日をカスタム設定している場合も、実際の会計期間の境界をまたいだら識別キーが変わること"
        )
    }
}
