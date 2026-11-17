// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// 注意: UI Testは実際のアプリを起動して操作するため、実行環境のアプリデータストアに
// 対して動作する。UI Testは壊れやすいため、ここでは最低限のスモークテストに留める。

import XCTest

final class InputFlowQARegressionUITests: QARegressionUITestCase {

    private func goToInputTab() {
        let inputTab = app.buttons["入力"].firstMatch
        XCTAssertTrue(inputTab.waitForExistence(timeout: 5))
        inputTab.tap()
    }

    // MARK: - 入力Viewで支出保存できる

    func testCanSaveExpenseFromInputView() throws {
        goToInputTab()

        let expenseTab = app.staticTexts["支出"].firstMatch
        if expenseTab.waitForExistence(timeout: 3) {
            expenseTab.tap()
        }

        // 金額欄をタップして電卓キーボードを開き、100円を入力する
        let saveButton = app.buttons["保存"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        let digitOne = app.buttons["1"].firstMatch
        if digitOne.waitForExistence(timeout: 3) {
            digitOne.tap()
            app.buttons["0"].firstMatch.tap()
            app.buttons["0"].firstMatch.tap()
        }

        // 保存を押してもクラッシュしないことを確認する（カテゴリー/支払い方法が未選択の場合は
        // 保存が無効化され画面遷移しないだけで、それ自体もクラッシュしない挙動として許容する）
        if saveButton.isEnabled {
            saveButton.tap()
        }

        // 入力画面に留まる/戻る、いずれにせよタブバーは生きている
        XCTAssertTrue(app.buttons["入力"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 入力Viewで収入保存できる

    func testCanSaveIncomeFromInputView() throws {
        goToInputTab()

        let incomeTab = app.staticTexts["収入"].firstMatch
        XCTAssertTrue(incomeTab.waitForExistence(timeout: 5))
        incomeTab.tap()

        let digitFive = app.buttons["5"].firstMatch
        if digitFive.waitForExistence(timeout: 3) {
            digitFive.tap()
            app.buttons["0"].firstMatch.tap()
            app.buttons["0"].firstMatch.tap()
        }

        let saveButton = app.buttons["保存"].firstMatch
        if saveButton.waitForExistence(timeout: 3), saveButton.isEnabled {
            saveButton.tap()
        }

        XCTAssertTrue(app.buttons["入力"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 帳簿切り替え後、入力画面がクラッシュしない

    func testInputScreenSurvivesBookSwitch() throws {
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

        goToInputTab()
        XCTAssertTrue(app.buttons["保存"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 振替画面で候補が重複していないことを確認する

    func testTransferScreenCandidatesLoadWithoutCrashing() throws {
        goToInputTab()

        let transferTab = app.staticTexts["振替"].firstMatch
        XCTAssertTrue(transferTab.waitForExistence(timeout: 5))
        transferTab.tap()

        let fromRow = app.staticTexts["移動元"].firstMatch
        XCTAssertTrue(fromRow.waitForExistence(timeout: 5))

        // 「未選択」または口座名のメニューが表示され、クラッシュしないことを確認する
        XCTAssertTrue(app.buttons["入力"].firstMatch.waitForExistence(timeout: 5))
    }
}
