import XCTest

final class TempExpenseVerification: XCTestCase {
    func testCreateExpenseDebug() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // 入力タブは起動直後のデフォルトタブのため、再タップするとresetToInitialState()が
        // 発火してカテゴリー選択が空になってしまう。タップせずそのまま使う。
        XCTAssertTrue(app.buttons["入力"].firstMatch.waitForExistence(timeout: 5))

        let amountRow = app.staticTexts["金額"].firstMatch
        XCTAssertTrue(amountRow.waitForExistence(timeout: 5))
        amountRow.tap()

        let digit1 = app.buttons["1"].firstMatch
        XCTAssertTrue(digit1.waitForExistence(timeout: 5))
        digit1.tap()
        app.buttons["2"].firstMatch.tap()
        app.buttons["3"].firstMatch.tap()
        app.buttons["4"].firstMatch.tap()

        // 保存を押す前に、金額が正しく入力されているかスクリーンショットで確認する
        var attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "before-save"
        attachment.lifetime = .keepAlways
        add(attachment)

        let saveButton = app.buttons["保存"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isHittable, "保存ボタンがヒットテスト不可能（キーボードに隠れている可能性）")
        saveButton.tap()

        sleep(2)

        attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "after-save"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
