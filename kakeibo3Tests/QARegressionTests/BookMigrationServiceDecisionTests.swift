import XCTest
@testable import kakeibo3

// MARK: - BookMigrationService.decideMainBookCreation(_:)の単体テスト
//
// 実機で確認された「メイン帳簿の重複生成」バグの再発防止用。CloudKit同期ON時に、
// 初回importが完了する前に「Bookが0件だから新規作成してよい」と誤判定していたことが
// 原因だったため、その判定ロジックを純粋関数として切り出し、A〜Dの各ケースを
// シングルトンやCore Dataに触れず決定的に検証する。
final class BookMigrationServiceDecisionTests: XCTestCase {

    private func makeBook(isMain: Bool, sortOrder: Int = 0) -> BookData {
        BookData(name: isMain ? "メイン帳簿" : "帳簿", sortOrder: sortOrder, isMain: isMain)
    }

    // MARK: - 既存Bookがある場合は常にそれを使う(新規作成しない)

    func testUsesExistingMainBookWhenPresent() {
        let main = makeBook(isMain: true)
        let other = makeBook(isMain: false, sortOrder: 1)
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [other, main],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .pending
        )
        XCTAssertEqual(decision, .useExisting(main.id), "isMainなBookが1件でもあれば、CloudKit状態に関わらずそれを使う")
    }

    func testUsesLowestSortOrderBookWhenNoBookIsFlaggedMain() {
        let first = makeBook(isMain: false, sortOrder: 0)
        let second = makeBook(isMain: false, sortOrder: 1)
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [second, first],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: false,
            initialImportState: .notApplicable
        )
        XCTAssertEqual(decision, .useExisting(first.id))
    }

    // MARK: - A. 完全な新規インストール(旧ストア無し、CloudKit OFF) → 作ってよい

    func testFreshInstallWithCloudSyncOffCreatesNewMainBook() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: false,
            initialImportState: .notApplicable
        )
        XCTAssertEqual(decision, .createNew)
    }

    // MARK: - C. 旧Kakeibo3.sqliteがまだ存在する(Split Migration未完了/失敗) → 待つ

    func testLegacyStoreStillPresentWaitsRegardlessOfCloudState() {
        XCTAssertEqual(
            BookMigrationService.decideMainBookCreation(
                existingBooks: [], legacyUnifiedStoreExists: true, cloudSyncActive: false, initialImportState: .notApplicable
            ),
            .waitAndRetry
        )
        XCTAssertEqual(
            BookMigrationService.decideMainBookCreation(
                existingBooks: [], legacyUnifiedStoreExists: true, cloudSyncActive: true, initialImportState: .completed
            ),
            .waitAndRetry,
            "CloudKit importが完了済みでも、旧ストアがまだ退避されていないなら作らない"
        )
    }

    // MARK: - D. CloudKit同期ONで初回import未完了 → 待つ

    func testCloudSyncActiveWithPendingImportWaits() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .pending
        )
        XCTAssertEqual(decision, .waitAndRetry, "初回importが終わるまでは他端末の既存メイン帳簿かもしれないため作らない")
    }

    // MARK: - CloudKit同期ONで初回import完了後もなお0件 → 本当に新規なので作ってよい

    func testCloudSyncActiveWithCompletedImportAndStillEmptyCreatesNewMainBook() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .completed
        )
        XCTAssertEqual(decision, .createNew)
    }

    // MARK: - D. CloudKit同期OFF、ローカルも空 → 作ってよい

    func testCloudSyncInactiveWithEmptyLocalStoreCreatesNewMainBook() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: false,
            initialImportState: .notApplicable
        )
        XCTAssertEqual(decision, .createNew)
    }

    // MARK: - 矛盾した入力(cloudSyncActive=trueなのにnotApplicable)は安全側(待つ)に倒す

    func testInconsistentStateFallsBackToWaiting() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .notApplicable
        )
        XCTAssertEqual(decision, .waitAndRetry)
    }

    // MARK: - 既知の残課題の解消確認：
    //
    // 一度でもメイン帳簿を確立済みのデバイスでは、CloudKit側の内部resetによる
    // 一時的な「existingBooksが0件」状態を、initialImportStateが既にcompletedでも
    // 二度と新規作成の根拠にしない(以前はここでcreateNewしてしまい、重複メイン帳簿の
    // 量産につながっていた＝実機調査で確認済みの不具合そのもの)。

    func testEstablishedMainBookIdPreventsCreationEvenWhenImportStateIsCompletedAndLocalIsEmpty() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .completed,
            establishedMainBookId: UUID()
        )
        XCTAssertEqual(
            decision, .waitAndRetry,
            "確立済みのメイン帳簿がある状態で0件に見えても、新規作成せず再表示を待つこと" +
            "(CloudKit内部resetによる一時的な空白の可能性を排除できないため)"
        )
    }

    func testEstablishedMainBookIdPreventsCreationEvenWhenCloudSyncIsOff() {
        // CloudKit同期OFFであっても、一度確立済みのメイン帳簿がある以上は
        // 「0件＝新規作成してよい」という判断をしない(安全側に倒す)。
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: false,
            initialImportState: .notApplicable,
            establishedMainBookId: UUID()
        )
        XCTAssertEqual(decision, .waitAndRetry)
    }

    func testFreshInstallWithoutEstablishedMainBookIdStillCreatesNewMainBook() {
        // establishedMainBookIdを渡さない(nil)既存の全テストが期待する動作に回帰が無いことの確認。
        // 本当に初めて起動するデバイスでは、この安全弁が新規作成の邪魔をしてはいけない。
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .completed,
            establishedMainBookId: nil
        )
        XCTAssertEqual(decision, .createNew)
    }

    // MARK: - BookMigrationService.hasUbiquityIdentityChanged(_:)の単体テスト
    //
    // iCloudアカウント変更時に、establishedMainBookIdKeyが残ったままになり
    // 新規帳簿を二度と作れなくなる(詰み)問題への対策。この判定自体は
    // FileManager.ubiquityIdentityTokenの実物を使わずに、アーカイブ済みDataの
    // 比較だけで決定的に検証できる(実際のiCloudアカウント状態には依存しない)。

    func testUbiquityIdentityUnchangedWhenNoPriorRecordExists() {
        // まだ一度も記録していない(この機能追加前からの既存ユーザー・または初回起動)場合は
        // 「変化なし」として扱う。ここで誤って「変化した」と判定すると、既存ユーザーの
        // establishedMainBookIdが起動直後に無条件でクリアされてしまう。
        XCTAssertFalse(
            BookMigrationService.hasUbiquityIdentityChanged(storedTokenData: nil, currentTokenData: nil)
        )
        XCTAssertFalse(
            BookMigrationService.hasUbiquityIdentityChanged(storedTokenData: nil, currentTokenData: Data([1, 2, 3]))
        )
    }

    func testUbiquityIdentityUnchangedWhenSameTokenData() {
        let token = Data([1, 2, 3])
        XCTAssertFalse(
            BookMigrationService.hasUbiquityIdentityChanged(storedTokenData: token, currentTokenData: token)
        )
    }

    func testUbiquityIdentityChangedWhenTokenDataDiffers() {
        XCTAssertTrue(
            BookMigrationService.hasUbiquityIdentityChanged(
                storedTokenData: Data([1, 2, 3]), currentTokenData: Data([4, 5, 6])
            )
        )
    }

    func testUbiquityIdentityChangedWhenSignedOutOfICloudEntirely() {
        // 記録済みのアカウントが有ったのに、今回はiCloud自体にサインインしていない(nil)
        // ＝サインアウトまたは別アカウントへの切り替え中。「変化した」として扱う。
        XCTAssertTrue(
            BookMigrationService.hasUbiquityIdentityChanged(storedTokenData: Data([1, 2, 3]), currentTokenData: nil)
        )
    }
}
