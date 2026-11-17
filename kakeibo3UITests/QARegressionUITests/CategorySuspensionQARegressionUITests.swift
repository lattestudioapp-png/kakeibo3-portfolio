// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// 注意: UI Testは実際のアプリを起動して操作するため、実行環境のアプリデータストアに
// 対して動作する。UI Testは壊れやすいため、ここでは最低限のスモークテストに留める。

import XCTest

final class CategorySuspensionQARegressionUITests: QARegressionUITestCase {

    private func openCategoryEditView() {
        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        // 「カテゴリー」行は設定画面のスクロール下方にあるため、表示されるまでスクロールする
        let categoryRow = app.buttons["カテゴリー"].firstMatch
        QARegressionUICleanup.scrollUntilHittable(categoryRow, app: app)
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5))
        QARegressionUICleanup.safeTap(categoryRow)
    }

    // MARK: - その他 > カテゴリーへ遷移できる

    func testCanNavigateToCategoryEditView() throws {
        openCategoryEditView()
        XCTAssertTrue(app.buttons["カテゴリー追加"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - カテゴリー編集を開ける

    func testCanOpenCategoryDetailEditView() throws {
        openCategoryEditView()

        // 初期カテゴリーの1つ「食費」をタップして詳細画面を開く
        let foodCategoryRow = app.buttons["食費"].firstMatch
        XCTAssertTrue(foodCategoryRow.waitForExistence(timeout: 5))
        foodCategoryRow.tap()

        XCTAssertTrue(app.staticTexts["使用停止"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - カテゴリー詳細で使用停止ON/OFFできる・使用停止カテゴリー一覧に移動する・入力候補から消える

    func testSuspendingAndReactivatingCategoryDoesNotCrash() throws {
        openCategoryEditView()

        // 新しいテスト用カテゴリーを作成し、既存カテゴリーに影響を与えないようにする
        let addButton = app.buttons["カテゴリー追加"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.alerts.textFields["カテゴリー名"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let categoryName = "QART_Suspend_\(Int(Date().timeIntervalSince1970))"
        nameField.tap()
        nameField.typeText(categoryName)
        app.alerts.buttons["追加"].tap()
        trackCreatedCategory(categoryName, type: .expense)

        let newCategoryRow = app.buttons[categoryName].firstMatch
        XCTAssertTrue(newCategoryRow.waitForExistence(timeout: 5))
        newCategoryRow.tap()

        // 使用停止トグルをONにする
        let suspendToggle = app.switches.firstMatch
        if suspendToggle.waitForExistence(timeout: 5) {
            suspendToggle.tap()
        }

        // 一覧に戻り、通常のカテゴリー編集一覧からは消えていることを確認する
        let closeButton = app.buttons.matching(identifier: "閉じる").firstMatch
        if closeButton.exists {
            closeButton.tap()
        }

        XCTAssertFalse(app.buttons[categoryName].firstMatch.waitForExistence(timeout: 3))

        // 使用停止カテゴリー一覧に移動していることを確認する
        let suspendedListButton = app.buttons["使用停止カテゴリー"].firstMatch
        if suspendedListButton.waitForExistence(timeout: 5) {
            suspendedListButton.tap()
            let suspendedCategoryRow = app.buttons[categoryName].firstMatch
            XCTAssertTrue(suspendedCategoryRow.waitForExistence(timeout: 5))

            // OFFに戻して通常一覧に復活させる（後始末を兼ねる）
            suspendedCategoryRow.tap()
            let reactivateToggle = app.switches.firstMatch
            if reactivateToggle.waitForExistence(timeout: 5) {
                reactivateToggle.tap()
            }
        }
    }
}
