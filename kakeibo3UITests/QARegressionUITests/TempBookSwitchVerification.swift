import XCTest

final class TempBookSwitchVerification: XCTestCase {
    func testCreateAndSwitchBook() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.buttons["設定"].firstMatch.tap()
        let bookSwitchRow = app.staticTexts["帳簿の切り替え"].firstMatch
        XCTAssertTrue(bookSwitchRow.waitForExistence(timeout: 5))
        bookSwitchRow.tap()

        var attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "book-switch-list"
        attachment.lifetime = .keepAlways
        add(attachment)

        let createButton = app.staticTexts["新しい帳簿を作成"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.textFields["帳簿名"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("検証用帳簿")
        app.buttons["作成"].firstMatch.tap()

        sleep(1)
        attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "after-create"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(app.staticTexts["検証用帳簿"].firstMatch.waitForExistence(timeout: 5))
    }
}
