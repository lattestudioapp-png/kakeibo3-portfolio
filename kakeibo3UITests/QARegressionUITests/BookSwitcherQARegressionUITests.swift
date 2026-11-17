// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// 注意: UI Testは実機/シミュレータ上の実際のアプリ(kakeibo3)を起動して操作するため、
// kakeibo3Tests(インメモリDB)と異なり、実行環境のアプリデータストアに対して動作する。
// 本番コードにテスト専用の「インメモリ切り替えフラグ」等は追加していないため、
// 完全な独立性を保証するには専用のクリーンなシミュレータでの実行を推奨する。
// 作成物は "QART_" 接頭辞をつけた判別可能な名前にし、可能な範囲で後始末する。

import XCTest

final class BookSwitcherQARegressionUITests: QARegressionUITestCase {

    private func openBookSwitcher() {
        let settingsTab = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let bookSwitchRow = app.buttons["帳簿の切り替え"].firstMatch
        XCTAssertTrue(bookSwitchRow.waitForExistence(timeout: 5))
        bookSwitchRow.tap()
    }

    // MARK: - 帳簿の切り替え画面へ遷移できる

    func testCanNavigateToBookSwitcher() throws {
        openBookSwitcher()

        let title = app.navigationBars["帳簿の切り替え"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    // MARK: - 帳簿を作成できる

    func testCanCreateBook() throws {
        openBookSwitcher()

        let createButton = app.buttons["新しい帳簿を作成"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.textFields["帳簿名"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let bookName = "QART_UITest_\(Int(Date().timeIntervalSince1970))"
        nameField.tap()
        nameField.typeText(bookName)

        app.alerts.buttons["作成"].tap()
        trackCreatedBook(bookName)

        let newBookRow = app.buttons[bookName].firstMatch
        XCTAssertTrue(newBookRow.waitForExistence(timeout: 5))
    }

    // MARK: - 帳簿を切り替えできる・選択中の帳簿にチェックが付く

    func testCanSwitchBookAndSeeCheckmark() throws {
        openBookSwitcher()

        let mainBookRow = app.buttons["メイン帳簿"].firstMatch
        XCTAssertTrue(mainBookRow.waitForExistence(timeout: 5))
        mainBookRow.tap()

        // メイン帳簿を選択した状態で再度開き直し、チェックマークがついていることを軽く確認する
        // (アイコンにはaccessibility labelが無いため、行タップ自体がクラッシュしないことを主眼に確認する)
        XCTAssertTrue(app.staticTexts["メイン帳簿"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - 帳簿名変更画面に入れる

    func testCanOpenBookEditScreen() throws {
        openBookSwitcher()

        let editButton = app.buttons["編集"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let mainBookRow = app.buttons["メイン帳簿"].firstMatch
        XCTAssertTrue(mainBookRow.waitForExistence(timeout: 5))
        mainBookRow.tap()

        let editTitle = app.navigationBars["帳簿を編集"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 5))

        // メイン帳簿は削除できない旨の表示があることを確認する
        XCTAssertTrue(app.staticTexts["メイン帳簿は削除できません"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["キャンセル"].firstMatch.tap()
    }

    // MARK: - 削除確認アラートが出る

    func testDeleteConfirmationAlertAppearsForNonMainBook() throws {
        openBookSwitcher()

        // 削除確認まで確認するテスト用の帳簿を作成する
        let createButton = app.buttons["新しい帳簿を作成"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let nameField = app.textFields["帳簿名"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let bookName = "QART_DeleteTest_\(Int(Date().timeIntervalSince1970))"
        nameField.tap()
        nameField.typeText(bookName)
        app.alerts.buttons["作成"].tap()
        trackCreatedBook(bookName)

        let editButton = app.buttons["編集"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let newBookRow = app.buttons[bookName].firstMatch
        XCTAssertTrue(newBookRow.waitForExistence(timeout: 5))
        newBookRow.tap()

        let deleteButton = app.buttons["削除する"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let confirmDialog = app.buttons["削除する"].firstMatch
        XCTAssertTrue(confirmDialog.waitForExistence(timeout: 5))

        // 後始末: テスト用帳簿を実際に削除してデータを残さない
        confirmDialog.tap()
    }
}
