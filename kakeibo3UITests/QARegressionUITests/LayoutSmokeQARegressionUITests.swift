// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// 注意: UI Testは実際のアプリを起動して操作するため、実行環境のアプリデータストアに
// 対して動作する。UI Testは壊れやすいため、ここでは最低限のスモークテストに留める。
//
// 画面サイズ違いの確認について: XCUITestは1プロセス内でシミュレータの画面サイズを
// 切り替えられないため、iPhone SEサイズ/Proサイズそれぞれの確認は、この同じテストクラスを
// 異なる `-destination` (シミュレータ機種) を指定して2回実行することで行う想定。
// (例: xcodebuild test -only-testing:kakeibo3UITests/LayoutSmokeQARegressionUITests
//      -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max')

import XCTest

final class LayoutSmokeQARegressionUITests: QARegressionUITestCase {

    // MARK: - 主要画面を開いてクラッシュしない

    func testMainScreensOpenWithoutCrashing() throws {
        for tabLabel in ["入力", "カレンダー", "分析", "予算", "設定"] {
            let tab = app.buttons[tabLabel].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(tabLabel)タブが見つからない")
            tab.tap()
            XCTAssertTrue(app.buttons[tabLabel].firstMatch.waitForExistence(timeout: 5), "\(tabLabel)画面表示後にクラッシュした可能性がある")
        }
    }

    // MARK: - キーボード表示時に保存ボタンが極端に隠れない

    func testSaveButtonRemainsReachableWhenKeyboardIsShown() throws {
        let inputTab = app.buttons["入力"].firstMatch
        XCTAssertTrue(inputTab.waitForExistence(timeout: 5))
        inputTab.tap()

        let digitOne = app.buttons["1"].firstMatch
        if digitOne.waitForExistence(timeout: 3) {
            digitOne.tap()
        }

        let saveButton = app.buttons["保存"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        // 電卓キーボード表示中でも保存ボタンにアクセスできる(hittable)ことを確認する
        XCTAssertTrue(saveButton.isHittable, "電卓キーボード表示中に保存ボタンが隠れている可能性がある")
    }

    // MARK: - 長い帳簿名でクラッシュしない

    func testVeryLongBookNameDoesNotCrashUI() throws {
        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let bookSwitchRow = app.buttons["帳簿の切り替え"].firstMatch
        XCTAssertTrue(bookSwitchRow.waitForExistence(timeout: 5))
        bookSwitchRow.tap()

        let createButton = app.buttons["新しい帳簿を作成"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.alerts.textFields["帳簿名"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        // "QART_"接頭辞 + 長い文字列(帳簿名編集画面には20文字までの入力制限があるため、
        // 制限を超えた入力でもクラッシュしないことを主眼に確認する)
        let longName = "QART_" + String(repeating: "あ", count: 200)
        nameField.tap()
        nameField.typeText(longName)
        app.alerts.buttons["作成"].tap()
        trackCreatedBook(longName)

        // アラートが閉じ、一覧画面がクラッシュせず表示され続けていることを確認する
        XCTAssertTrue(app.navigationBars["帳簿の切り替え"].waitForExistence(timeout: 5))
    }

    // MARK: - 長いカテゴリー名でクラッシュしない

    func testVeryLongCategoryNameDoesNotCrashUI() throws {
        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let categoryRow = app.buttons["カテゴリー"].firstMatch
        QARegressionUICleanup.scrollUntilHittable(categoryRow, app: app)
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5))
        QARegressionUICleanup.safeTap(categoryRow)

        let addButton = app.buttons["カテゴリー追加"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.alerts.textFields["カテゴリー名"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let longName = "QART_" + String(repeating: "ま", count: 200)
        nameField.tap()
        nameField.typeText(longName)
        app.alerts.buttons["追加"].tap()
        trackCreatedCategory(longName, type: .expense)

        XCTAssertTrue(app.buttons["カテゴリー追加"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 長いカード名でクラッシュしない

    func testVeryLongCreditCardNameDoesNotCrashUI() throws {
        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let creditCardRow = app.buttons["クレジットカード"].firstMatch
        QARegressionUICleanup.scrollUntilHittable(creditCardRow, app: app)
        if creditCardRow.waitForExistence(timeout: 5) {
            QARegressionUICleanup.safeTap(creditCardRow)

            let addButton = app.buttons["クレジットカードを追加"].firstMatch
            if addButton.waitForExistence(timeout: 5) {
                addButton.tap()

                let nameField = app.textFields.firstMatch
                if nameField.waitForExistence(timeout: 5) {
                    nameField.tap()
                    nameField.typeText("QART_" + String(repeating: "カ", count: 200))
                }

                let cancelButton = app.buttons["キャンセル"].firstMatch
                if cancelButton.waitForExistence(timeout: 3) {
                    cancelButton.tap()
                }
            }
        }

        // どの段階で終わってもタブバーが生きていることを確認する
        XCTAssertTrue(app.buttons["設定"].firstMatch.waitForExistence(timeout: 5))
    }
}
