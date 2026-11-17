import XCTest
@testable import kakeibo3

// MARK: - CloudSyncSettingsのテスト
//
// CloudSyncSettingsは`static let shared`の真のシングルトン(privateなinit)で、一度生成されると
// currentSessionEnabledは以後不変なので、複数の起動状態パターンをシングルトン経由で作り分けて
// テストすることはできない。そのため状態遷移ロジック(computeState/needsRestart/outcome)は
// シングルトンを介さない純粋関数として切り出してあり、ここではそれらを直接検証する
// （CloudSyncSettings.swiftのコメント参照）。シングルトン自体が絡む項目
// （isUserEnabledPreference()の既定値、CoreDataStack.isCloudSyncActiveとの連動）は
// UserDefaults直接操作、およびCoreDataStackの各テスト用init経路を通して検証する。
final class CloudSyncSettingsTests: XCTestCase {

    private var userDefaultsSnapshot: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaultsSnapshot = UserDefaults.standard.dictionaryRepresentation()
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isUserEnabledKey)
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        let currentKeys = Set(defaults.dictionaryRepresentation().keys)
        let snapshotKeys = Set(userDefaultsSnapshot.keys)
        for key in currentKeys.subtracting(snapshotKeys) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in userDefaultsSnapshot {
            defaults.set(value, forKey: key)
        }
        try super.tearDownWithError()
    }

    // MARK: - 初期値: 既存ユーザー/新規インストールとも「キーが無ければON」

    func testIsUserEnabledPreferenceDefaultsToTrueWhenKeyIsAbsent() {
        // このトグル機能が存在する前のユーザー(＝キーが一度も書き込まれていない)と、
        // 新規インストール直後は、どちらもUserDefaultsにキーが無い状態で区別できない。
        // 既存ユーザーが更新後に突然同期OFFにならないことを優先し、両方ともtrueを既定値にする。
        XCTAssertNil(UserDefaults.standard.object(forKey: CloudSyncSettings.isUserEnabledKey))
        XCTAssertTrue(CloudSyncSettings.isUserEnabledPreference())
    }

    func testIsUserEnabledPreferenceReflectsExplicitlyStoredFalse() {
        UserDefaults.standard.set(false, forKey: CloudSyncSettings.isUserEnabledKey)
        XCTAssertFalse(CloudSyncSettings.isUserEnabledPreference())
    }

    func testIsUserEnabledPreferenceReflectsExplicitlyStoredTrue() {
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isUserEnabledKey)
        XCTAssertTrue(CloudSyncSettings.isUserEnabledPreference())
    }

    // MARK: - ON/OFF状態(state)の導出

    func testStateIsDisabledWhenCurrentSessionIsNotCloudEnabled() {
        // 今回のセッションがCloudKit無効で起動していれば、希望値に関わらずdisabled
        // (次回起動を待っている最中でも、"このセッションでは実際にOFF"という事実を表す)。
        XCTAssertEqual(
            CloudSyncSettings.computeState(
                isUserEnabled: true, currentSessionEnabled: false, hasCompletedInitialSync: false, lastErrorMessage: nil
            ),
            .disabled
        )
    }

    func testStateIsDisablingWhenSessionEnabledButUserTurnedOff() {
        XCTAssertEqual(
            CloudSyncSettings.computeState(
                isUserEnabled: false, currentSessionEnabled: true, hasCompletedInitialSync: true, lastErrorMessage: nil
            ),
            .disabling
        )
    }

    func testStateIsEnablingWhenSessionEnabledButNoSuccessfulSyncYet() {
        XCTAssertEqual(
            CloudSyncSettings.computeState(
                isUserEnabled: true, currentSessionEnabled: true, hasCompletedInitialSync: false, lastErrorMessage: nil
            ),
            .enabling
        )
    }

    func testStateIsEnabledAfterSuccessfulSync() {
        XCTAssertEqual(
            CloudSyncSettings.computeState(
                isUserEnabled: true, currentSessionEnabled: true, hasCompletedInitialSync: true, lastErrorMessage: nil
            ),
            .enabled
        )
    }

    func testStateIsErrorRegardlessOfOtherFlagsWhenErrorMessagePresent() {
        XCTAssertEqual(
            CloudSyncSettings.computeState(
                isUserEnabled: true, currentSessionEnabled: true, hasCompletedInitialSync: true, lastErrorMessage: "network"
            ),
            .error("network")
        )
    }

    // MARK: - 再起動反映バナーの判定

    func testNeedsRestartIsTrueWhenPreferenceDiffersFromSession() {
        XCTAssertTrue(CloudSyncSettings.needsRestart(isUserEnabled: true, currentSessionEnabled: false))
        XCTAssertTrue(CloudSyncSettings.needsRestart(isUserEnabled: false, currentSessionEnabled: true))
    }

    func testNeedsRestartIsFalseWhenPreferenceMatchesSession() {
        XCTAssertFalse(CloudSyncSettings.needsRestart(isUserEnabled: true, currentSessionEnabled: true))
        XCTAssertFalse(CloudSyncSettings.needsRestart(isUserEnabled: false, currentSessionEnabled: false))
    }

    // MARK: - NSPersistentCloudKitContainer.Eventの解釈

    func testOutcomeIsNilWhileEventStillInProgress() {
        XCTAssertNil(CloudSyncSettings.outcome(forEventEndDate: nil, errorDescription: nil))
        XCTAssertNil(CloudSyncSettings.outcome(forEventEndDate: nil, errorDescription: "should be ignored until endDate"))
    }

    func testOutcomeIsSucceededWhenEventFinishesWithoutError() {
        XCTAssertEqual(
            CloudSyncSettings.outcome(forEventEndDate: Date(), errorDescription: nil), .succeeded
        )
    }

    func testOutcomeIsFailedWhenEventFinishesWithError() {
        XCTAssertEqual(
            CloudSyncSettings.outcome(forEventEndDate: Date(), errorDescription: "CKError.networkUnavailable"),
            .failed("CKError.networkUnavailable")
        )
    }

    // MARK: - apply(_:)がインスタンスの状態をどう更新するか

    func testApplySucceededClearsErrorAndMarksInitialSyncComplete() {
        let settings = CloudSyncSettings.shared
        settings.apply(.failed("temporary"))
        XCTAssertEqual(settings.lastErrorMessage, "temporary")

        settings.apply(.succeeded)
        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(settings.hasCompletedInitialSync)
    }

    func testApplyFailedSetsErrorMessage() {
        let settings = CloudSyncSettings.shared
        settings.apply(.failed("CKError.notAuthenticated"))
        XCTAssertEqual(settings.lastErrorMessage, "CKError.notAuthenticated")
    }

    // MARK: - lastSyncEventAt(複数端末の同時初回起動対策・CoreDataStartupCoordinatorが
    // 「CloudKit側で同期活動が最近あったか」を判定するために使う)

    func testApplySucceededRecordsLastSyncEventAt() {
        let settings = CloudSyncSettings.shared
        let before = Date()
        settings.apply(.succeeded)
        XCTAssertNotNil(settings.lastSyncEventAt)
        XCTAssertGreaterThanOrEqual(settings.lastSyncEventAt!, before)
    }

    func testApplyFailedAlsoRecordsLastSyncEventAt() {
        // 成否に関わらず「CloudKit側で何らかのイベントが起きた」ことそのものを記録する
        // (失敗したイベントも、同期活動が続いている証拠であることに変わりないため)。
        let settings = CloudSyncSettings.shared
        let before = Date()
        settings.apply(.failed("CKError.networkUnavailable"))
        XCTAssertNotNil(settings.lastSyncEventAt)
        XCTAssertGreaterThanOrEqual(settings.lastSyncEventAt!, before)
    }

    func testApplyNilOutcomeDoesNotChangeLastSyncEventAt() {
        let settings = CloudSyncSettings.shared
        settings.apply(.succeeded)
        let recordedAt = settings.lastSyncEventAt
        settings.apply(nil)
        XCTAssertEqual(settings.lastSyncEventAt, recordedAt)
    }

    func testApplyNilOutcomeDoesNotChangeState() {
        let settings = CloudSyncSettings.shared
        settings.apply(.succeeded)
        let hadCompleted = settings.hasCompletedInitialSync
        let hadError = settings.lastErrorMessage
        settings.apply(nil)
        XCTAssertEqual(settings.hasCompletedInitialSync, hadCompleted)
        XCTAssertEqual(settings.lastErrorMessage, hadError)
    }

    // MARK: - isUserEnabledのdidSetがUserDefaultsへ即座に反映される

    func testTogglingIsUserEnabledPersistsToUserDefaultsImmediately() {
        let settings = CloudSyncSettings.shared
        let original = settings.isUserEnabled
        defer { settings.isUserEnabled = original }

        settings.isUserEnabled = !original
        XCTAssertEqual(CloudSyncSettings.isUserEnabledPreference(), !original)

        settings.isUserEnabled = original
        XCTAssertEqual(CloudSyncSettings.isUserEnabledPreference(), original)
    }
}
