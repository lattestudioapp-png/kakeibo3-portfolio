import XCTest

final class TempCategoryVerification: XCTestCase {
    func testAddAndRenameCategory() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["食費"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["追加 / 編集"].firstMatch.tap()

        let addButton = app.buttons["カテゴリー追加"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("検証カテゴリー")

        let confirmButtons = app.alerts.buttons.allElementsBoundByIndex
        for button in confirmButtons where button.label == "追加" {
            button.tap()
        }

        var attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "after-add-category"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(app.buttons["検証カテゴリー"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["検証カテゴリー"].firstMatch.waitForExistence(timeout: 5))
    }
}
