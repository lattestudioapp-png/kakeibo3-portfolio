// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// お問い合わせ機能（⑤）の回帰テスト。
// mailto:を開く実処理自体はUIKit/@Environment(\.openURL)に依存するため実機/UIテスト向きだが、
// ここではCore Data・SwiftDataに依存しない周辺要素（DeviceInfo・UI部品の非クラッシュ）を確認する。

import XCTest
@testable import kakeibo3

final class ContactQARegressionTests: QARegressionTestCase {

    // MARK: - DeviceInfo

    func testDeviceInfoAppVersionIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.appVersion.isEmpty)
    }

    func testDeviceInfoIOSVersionIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.iOSVersion.isEmpty)
    }

    func testDeviceInfoDeviceModelNameIsNotEmpty() {
        XCTAssertFalse(DeviceInfo.deviceModelName.isEmpty)
    }

    // MARK: - ContactEmailFallbackView（メール未設定時のフォールバック表示）のスモークテスト

    @MainActor
    func testContactEmailFallbackViewDoesNotCrash() {
        let view = ContactEmailFallbackView(email: "test@example.com", onClose: {})
        _ = view.body
    }
}
