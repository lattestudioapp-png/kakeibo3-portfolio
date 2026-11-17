// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// 注意: UI Testは実際のアプリを起動して操作するため、実行環境のアプリデータストアに
// 対して動作する。UI Testは壊れやすいため、ここでは最低限のスモークテストに留める。

import XCTest

final class CalendarAnalysisQARegressionUITests: QARegressionUITestCase {

    // MARK: - カレンダーに支出が表示される(画面が開いてクラッシュしない)

    func testCalendarScreenOpensWithoutCrashing() throws {
        let calendarTab = app.buttons["カレンダー"].firstMatch
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5))
        calendarTab.tap()

        // カレンダーグリッドが表示される（タブバーが生きていることをもってクラッシュしないことを確認）
        XCTAssertTrue(app.buttons["カレンダー"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 帳簿切り替え後に別帳簿の支出が表示されない(画面遷移がクラッシュしない)

    func testCalendarSurvivesBookSwitch() throws {
        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let bookSwitchRow = app.buttons["帳簿の切り替え"].firstMatch
        XCTAssertTrue(bookSwitchRow.waitForExistence(timeout: 5))
        bookSwitchRow.tap()

        let mainBookRow = app.staticTexts["メイン帳簿"].firstMatch
        XCTAssertTrue(mainBookRow.waitForExistence(timeout: 5))
        mainBookRow.tap()

        let closeButton = app.buttons["閉じる"].firstMatch
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        }

        let calendarTab = app.buttons["カレンダー"].firstMatch
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5))
        calendarTab.tap()

        XCTAssertTrue(app.buttons["カレンダー"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 分析Viewに支出合計が表示される

    func testAnalysisScreenOpensWithoutCrashing() throws {
        let analysisTab = app.buttons["分析"].firstMatch
        XCTAssertTrue(analysisTab.waitForExistence(timeout: 5))
        analysisTab.tap()

        XCTAssertTrue(app.buttons["分析"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 帳簿切り替え後に分析が切り替わる(画面遷移がクラッシュしない)

    func testAnalysisSurvivesBookSwitch() throws {
        let analysisTab = app.buttons["分析"].firstMatch
        XCTAssertTrue(analysisTab.waitForExistence(timeout: 5))
        analysisTab.tap()

        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let bookSwitchRow = app.buttons["帳簿の切り替え"].firstMatch
        XCTAssertTrue(bookSwitchRow.waitForExistence(timeout: 5))
        bookSwitchRow.tap()

        let mainBookRow = app.staticTexts["メイン帳簿"].firstMatch
        XCTAssertTrue(mainBookRow.waitForExistence(timeout: 5))
        mainBookRow.tap()

        let closeButton = app.buttons["閉じる"].firstMatch
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        }

        analysisTab.tap()
        XCTAssertTrue(app.buttons["分析"].firstMatch.waitForExistence(timeout: 5))
    }
}
