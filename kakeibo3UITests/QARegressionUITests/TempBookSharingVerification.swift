import XCTest

final class TempBookSharingVerification: XCTestCase {
    func testOpenBookSharingSetting() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.buttons["設定"].firstMatch.tap()

        let sharingRow = app.staticTexts["帳簿の共有"].firstMatch
        XCTAssertTrue(sharingRow.waitForExistence(timeout: 5))

        var attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-list"
        attachment.lifetime = .keepAlways
        add(attachment)

        sharingRow.tap()

        XCTAssertTrue(app.staticTexts["この帳簿は共有されていません"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["共有する家計簿"].firstMatch.exists)
        XCTAssertTrue(app.buttons["共有を開始"].firstMatch.exists)

        attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "book-sharing-not-shared"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
