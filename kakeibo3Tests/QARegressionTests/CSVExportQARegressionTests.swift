// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 発見した既存バグ: CSVExportService.exportCSV は元々 bookId で絞り込んでおらず、
// 全帳簿の取引が1つのCSVに混ざって出力される状態だった。本テスト作成の過程で発見したため、
// Services/CSVExportService.swift に bookId パラメータを追加し、呼び出し元
// (Views/Other/CSVExportSettingsView.swift) から現在帳簿のIDを渡すよう修正した
// （本番コードの修正であり、QA専用の分岐は追加していない）。

import XCTest
@testable import kakeibo3

final class CSVExportQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    private func readCSV(at url: URL, encoding: String.Encoding = .utf8) throws -> String {
        let data = try Data(contentsOf: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return String(data: data, encoding: encoding) ?? ""
    }

    // MARK: - 帳簿スコープ（既知バグの回帰防止）

    func testCSVOnlyContainsCurrentBookTransactions() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 123, paymentMethod: "現金", category: "食費", memo: "メイン帳簿の支出", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 456, paymentMethod: "現金", category: "食費", memo: "事業用帳簿の支出", bookId: business.book.id)

        let url = try CSVExportService.exportCSV(
            bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil
        )
        let csv = try readCSV(at: url)

        XCTAssertTrue(csv.contains("123"))
        XCTAssertTrue(csv.contains("メイン帳簿の支出"))
        XCTAssertFalse(csv.contains("456"))
        XCTAssertFalse(csv.contains("事業用帳簿の支出"))
    }

    func testDifferentBooksProduceDifferentCSVContents() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 111, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeExpense(amount: 222, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        let mainURL = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let mainCSV = try readCSV(at: mainURL)
        XCTAssertTrue(mainCSV.contains("111"))
        XCTAssertFalse(mainCSV.contains("222"))

        let businessURL = try CSVExportService.exportCSV(bookId: business.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let businessCSV = try readCSV(at: businessURL)
        XCTAssertTrue(businessCSV.contains("222"))
        XCTAssertFalse(businessCSV.contains("111"))
    }

    // MARK: - 支出/収入/対象種別

    func testExpenseIsIncluded() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)
        XCTAssertTrue(csv.contains("支出"))
    }

    func testIncomeIsIncluded() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)
        XCTAssertTrue(csv.contains("収入"))
    }

    func testExpenseOnlyTargetExcludesIncome() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 999999, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .expenseOnly, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)
        XCTAssertTrue(csv.contains("500"))
        XCTAssertFalse(csv.contains("999999"))
    }

    func testIncomeOnlyTargetExcludesExpense() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 888888, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .incomeOnly, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)
        XCTAssertTrue(csv.contains("5000"))
        XCTAssertFalse(csv.contains("888888"))
    }

    // MARK: - カテゴリー名・支払い方法名・受け取り方法名・メモ・日付・金額

    func testCategoryPaymentMethodMemoAndAmountAreCorrect() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 1234, paymentMethod: "PayPay", category: "食費", memo: "テストメモ", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)

        XCTAssertTrue(csv.contains("食費"))
        XCTAssertTrue(csv.contains("PayPay"))
        XCTAssertTrue(csv.contains("テストメモ"))
        XCTAssertTrue(csv.contains("1234"))
    }

    func testDateFormatIsYYYYMMDD() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 9))!
        QARegressionTestFactory.makeExpense(amount: 100, date: date, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)
        XCTAssertTrue(csv.contains("2026/07/09"))
    }

    // MARK: - 使用停止カテゴリーも過去取引として出力される

    func testSuspendedCategoryNameIsStillExportedForPastTransactions() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 700, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url)
        XCTAssertTrue(csv.contains("食費"))
        XCTAssertTrue(csv.contains("700"))
    }

    // MARK: - 文字化けしない（UTF-8 / Shift_JIS）

    func testUTF8EncodingDoesNotCorruptJapaneseText() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", memo: "日本語のメモ", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url, encoding: .utf8)
        XCTAssertTrue(csv.contains("日本語のメモ"))
    }

    func testShiftJISEncodingDoesNotCorruptJapaneseText() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", memo: "日本語のメモ", bookId: main.book.id)

        let url = try CSVExportService.exportCSV(bookId: main.book.id, encoding: .shiftJIS, target: .all, startDate: nil, endDate: nil)
        let csv = try readCSV(at: url, encoding: .shiftJIS)
        XCTAssertTrue(csv.contains("日本語のメモ"))
    }

    // MARK: - 空データ

    func testEmptyDataThrowsNoDataError() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertThrowsError(
            try CSVExportService.exportCSV(bookId: main.book.id, encoding: .utf8, target: .all, startDate: nil, endDate: nil)
        ) { error in
            XCTAssertEqual(error as? CSVExportError, .noData)
        }
    }
}
