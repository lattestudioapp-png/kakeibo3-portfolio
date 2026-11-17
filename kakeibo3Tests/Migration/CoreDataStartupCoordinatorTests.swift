import XCTest
import CoreData
@testable import kakeibo3

// MARK: - Split Migrationを本番起動へ接続する配線(CoreDataStartupCoordinator)の回帰テスト
//
// 「Split Migrationが実装済みなのに本番起動から一度も呼ばれておらず、Cloud/Localストアが
// 常に空からスタートしていた」ことが、実機で確認されたメイン帳簿重複バグの根本原因だった。
// このテストは、CoreDataStartupCoordinator.runIfNeeded()が実際にSplitMigrationBootstrapを
// 呼び、CoreDataStack.sharedへ触れるのがその後であることを、MigrationCoordinatorB3Testsと
// 同じ「テスト専用の本番ディレクトリ・UserDefaultsスイートを直接指定する」流儀で検証する。

@MainActor
final class CoreDataStartupCoordinatorTests: XCTestCase {

    private var workDirectory: URL!
    private var productionDirectory: URL!
    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var standardUserDefaultsSnapshot: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoreDataStartupCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        workDirectory = root.appendingPathComponent("work", isDirectory: true)
        productionDirectory = root.appendingPathComponent("production", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productionDirectory, withIntermediateDirectories: true)

        suiteName = "CoreDataStartupCoordinatorTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)

        // 【重要】BookMigrationService.migrateIfNeeded()はUserDefaults.standardを直接
        // 読み書きする(BookSettings.storageKey / establishedMainBookIdKey、依存注入されていない)。
        // ここで使うテスト専用の`userDefaults`(suiteName)とは別物のため、このファイル独自に
        // UserDefaults.standardもスナップショット/復元しないと、このテストが書き込んだ値が
        // 実機のシミュレータ上に残り、以後の別テスト実行（別のxcodebuild test起動）まで
        // 汚染が持ち越ってしまう(実機調査で確認済み：QARegressionTestCaseの流儀をここにも適用する)。
        standardUserDefaultsSnapshot = UserDefaults.standard.dictionaryRepresentation()

        CoreDataStack.shared = CoreDataStack(inMemory: true)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults.standard
        let currentKeys = Set(defaults.dictionaryRepresentation().keys)
        let snapshotKeys = Set(standardUserDefaultsSnapshot.keys)
        for key in currentKeys.subtracting(snapshotKeys) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in standardUserDefaultsSnapshot {
            defaults.set(value, forKey: key)
        }
        try? CoreDataStack.shared.releasePersistentStoresForMigration()
        CoreDataStack.shared = CoreDataStack(inMemory: true)
        if let root = workDirectory?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    // MARK: - 旧Kakeibo3.sqlite(分割前の単一ストア)構築ヘルパー(SplitMigrationBootstrapTestsと同じ流儀)

    @discardableResult
    private func insert(_ entityName: String, into context: NSManagedObjectContext, _ attributes: [String: Any?]) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
        for (key, value) in attributes {
            object.setValue(value, forKey: key)
        }
        return object
    }

    private func makeLegacyUnifiedStoreWithOneBook(bookName: String = "メイン帳簿") throws {
        let storeURL = productionDirectory.appendingPathComponent(LegacyUnifiedStoreLocator.storeFileName)
        let stack = try CoreDataStack(throwingStoreURL: storeURL)
        let context = stack.container.viewContext
        let bookId = UUID()
        insert("BookData", into: context, ["id": bookId, "name": bookName, "isMain": true, "sortOrder": Int64(0), "createdAt": Date()])
        try context.save()
        try stack.releasePersistentStoresForMigration()
    }

    // MARK: - 旧ストア無し → Split Migrationはnotneeded、本当に新規インストールなので
    // .readyへ直進せず.awaitingFreshInstallConfirmation(C1の確認ゲート)で止まる

    func testNoLegacyStoreEntersFreshInstallConfirmationGateInsteadOfReady() async {
        // 【C1:複数端末の同時初回起動対策】以前はここで直接.readyへ進んでいたが、
        // 「ローカルが空・かつこの端末でも未確立」という、まさに新規メイン帳簿が
        // 作られようとしている状況なので、ユーザーの明示的な「開始する」確認を待つ
        // 状態を経由するようになった。
        let coordinator = CoreDataStartupCoordinator()
        await coordinator.runIfNeeded(
            productionDirectory: productionDirectory, workDirectory: workDirectory, userDefaults: userDefaults
        )
        XCTAssertEqual(coordinator.state, .awaitingFreshInstallConfirmation)
        XCTAssertFalse(coordinator.isReady, "確認ゲートの間はisReadyもfalseのまま(通常画面へは進めない)")
        // CloudKit無効(テスト用ディレクトリなのでaps-environment等は無関係だが、
        // 本番経路のCoreDataStack()を実際に生成している以上、シミュレータのXCTest実行中は
        // isRunningUnderXCTestガードにより必ずCloudKit無効でロードされる)。
        XCTAssertFalse(CoreDataStack.shared.isCloudSyncActive)

        // 「開始する」が選ばれた後は、通常通り.readyへ進む。
        coordinator.confirmFreshInstall()
        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertTrue(coordinator.isReady)
    }

    // MARK: - 既にBookがある端末(Split Migration済み等)では確認ゲートを経由しない

    func testRunIfNeededSkipsConfirmationGateWhenLocalBookAlreadyExists() async throws {
        try makeLegacyUnifiedStoreWithOneBook(bookName: "既存ユーザーの帳簿")
        let coordinator = CoreDataStartupCoordinator()
        await coordinator.runIfNeeded(
            productionDirectory: productionDirectory, workDirectory: workDirectory, userDefaults: userDefaults
        )
        XCTAssertEqual(
            coordinator.state, .ready,
            "既にBookがある端末では確認ゲートを経由せず.readyへ直進すること(既存ユーザーには一切影響しない)"
        )
    }

    // MARK: - 確認ゲートの状態でない時にconfirmFreshInstall()を呼んでも何も起きない

    func testConfirmFreshInstallIsNoOpWhenNotAwaitingConfirmation() {
        let coordinator = CoreDataStartupCoordinator()
        coordinator.confirmFreshInstall()
        XCTAssertEqual(coordinator.state, .pending)
    }

    // MARK: - 旧ストアあり → Split Migrationが実際に走り、移行済みのBookがCoreDataStack.sharedに反映される

    func testLegacyStoreGetsMigratedBeforeCoreDataStackIsTouched() async throws {
        try makeLegacyUnifiedStoreWithOneBook(bookName: "既存ユーザーの帳簿")

        let coordinator = CoreDataStartupCoordinator()
        await coordinator.runIfNeeded(
            productionDirectory: productionDirectory, workDirectory: workDirectory, userDefaults: userDefaults
        )

        XCTAssertEqual(coordinator.state, .ready)
        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1, "Split Migrationで移行された1件だけが存在し、重複していないこと")
        XCTAssertEqual(books.first?.name, "既存ユーザーの帳簿")

        // 旧ストアは退避され、本来の場所には残っていない(再実行しても再migrationされない)ことを確認
        XCTAssertNil(LegacyUnifiedStoreLocator.paths(directory: productionDirectory, requireExists: true))
    }

    // MARK: - Split Migration後にBookMigrationServiceを実行しても、移行済みBookをそのまま使い重複しない

    func testBookMigrationServiceUsesExistingBookAfterSplitMigration() async throws {
        try makeLegacyUnifiedStoreWithOneBook(bookName: "既存ユーザーの帳簿")

        let coordinator = CoreDataStartupCoordinator()
        await coordinator.runIfNeeded(
            productionDirectory: productionDirectory, workDirectory: workDirectory, userDefaults: userDefaults
        )
        XCTAssertEqual(coordinator.state, .ready)

        // Kakeibo3App.onAppearと同じ順序で、Split Migration完了後にBookMigrationServiceを呼ぶ。
        // 実際の起動と同じくlegacyUnifiedStoreExistsは省略時のデフォルト(本番ディレクトリを見る)
        // ではなく、Split Migration後は既に退避済みのため明示的にfalseを渡して確定的に検証する。
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1, "Split Migration済みのBookをそのまま使い、新規のメイン帳簿を作らないこと")
        XCTAssertEqual(books.first?.name, "既存ユーザーの帳簿")
    }

    // MARK: - 二重起動しても安全(実行中に再度runIfNeededを呼んでも無視される)

    func testRunIfNeededIgnoresConcurrentReentry() async throws {
        try makeLegacyUnifiedStoreWithOneBook()
        let coordinator = CoreDataStartupCoordinator()

        async let first: Void = coordinator.runIfNeeded(
            productionDirectory: productionDirectory, workDirectory: workDirectory, userDefaults: userDefaults
        )
        async let second: Void = coordinator.runIfNeeded(
            productionDirectory: productionDirectory, workDirectory: workDirectory, userDefaults: userDefaults
        )
        _ = await (first, second)

        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertEqual(BookDataSync.fetchAll().count, 1)
    }

    // MARK: - 複数端末の同時初回起動対策(freshInstallGraceWindow)の単体テスト
    //
    // CoreDataStartupCoordinator.needsFreshInstallGraceWindow(_:)の純粋関数版。
    // 実際のCloudKit接続・非同期待機を伴わずに判定条件だけを決定的に検証する。

    func testNeedsFreshInstallGraceWindowOnlyWhenTrulyFreshAndUnestablished() {
        XCTAssertTrue(
            CoreDataStartupCoordinator.needsFreshInstallGraceWindow(
                existingBooksIsEmpty: true, establishedMainBookId: nil
            ),
            "ローカルが空・かつ未確立の場合のみ、競合緩和のための待機が必要"
        )
        XCTAssertFalse(
            CoreDataStartupCoordinator.needsFreshInstallGraceWindow(
                existingBooksIsEmpty: true, establishedMainBookId: UUID()
            ),
            "確立済みなら(ローカルが空でも)待機不要。既存のestablishedMainBookId分岐が既に安全に処理する"
        )
        XCTAssertFalse(
            CoreDataStartupCoordinator.needsFreshInstallGraceWindow(
                existingBooksIsEmpty: false, establishedMainBookId: nil
            ),
            "ローカルに既にBookがあるなら待機不要(ほとんどの通常起動がこのケース)"
        )
    }

    // MARK: - waitOutFreshInstallRaceWindowIfNeeded()の統合確認(C2:適応的待機)
    //
    // 固定秒数のsleepではなく、(1)ポーリングして帳簿が届いたら即座に抜ける、
    // (2)静穏期間(freshInstallQuietPeriod)が経過したら上限(freshInstallGraceWindow)まで
    // 待たずに早期に抜ける、という2点を短い待機時間で決定的に検証する。
    // CloudSyncSettings.sharedはプロセス全体で共有される真のシングルトンのため、
    // initialImportState/lastSyncEventAtProviderを明示的に注入し、実際のシングルトンの
    // 状態(他のテストの実行順)に左右されないようにしている。

    func testWaitOutFreshInstallRaceWindowExitsAfterQuietPeriodWhenNoCompetitorAppears() async {
        let coordinator = CoreDataStartupCoordinator()
        coordinator.freshInstallGraceWindow = 5
        coordinator.freshInstallPollInterval = 0.05
        coordinator.freshInstallQuietPeriod = 0.2
        UserDefaults.standard.removeObject(forKey: BookMigrationService.establishedMainBookIdKey)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty, "事前条件：ローカルにBookDataが無いこと")

        let start = Date()
        await coordinator.waitOutFreshInstallRaceWindowIfNeeded(
            initialImportState: .completed,
            lastSyncEventAtProvider: { nil }
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.15, "静穏期間(freshInstallQuietPeriod)が経過するまでは待つこと")
        XCTAssertLessThan(
            elapsed, 1.0,
            "競合相手がいなければ、上限(freshInstallGraceWindow=5秒)まで待たず、" +
            "静穏期間の経過だけで早期に終えること(単独端末の新規インストールが不必要に遅くならないこと)"
        )
    }

    func testWaitOutFreshInstallRaceWindowSkipsEntirelyWhenInitialImportIsNotCompleted() async {
        // 初回importが完了していない(オフライン・ネットワーク不調等でpendingのまま)場合、
        // decideMainBookCreationはどのみちwaitAndRetryを返すため、この待機自体を行う意味がない。
        let coordinator = CoreDataStartupCoordinator()
        coordinator.freshInstallGraceWindow = 5
        UserDefaults.standard.removeObject(forKey: BookMigrationService.establishedMainBookIdKey)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty)

        let start = Date()
        await coordinator.waitOutFreshInstallRaceWindowIfNeeded(
            initialImportState: .pending,
            lastSyncEventAtProvider: { nil }
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(
            elapsed, 0.5,
            "初回importが完了していない場合は、上限秒数を設定していても即座に返ること(無駄な待機を課さないための分岐)"
        )
    }

    func testWaitOutFreshInstallRaceWindowExitsEarlyWhenBookAppearsMidPoll() async {
        let coordinator = CoreDataStartupCoordinator()
        coordinator.freshInstallGraceWindow = 5
        coordinator.freshInstallPollInterval = 0.05
        coordinator.freshInstallQuietPeriod = 5 // 静穏期間では絶対に抜けないよう長く設定する
        UserDefaults.standard.removeObject(forKey: BookMigrationService.establishedMainBookIdKey)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty)

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15秒後に他端末の帳簿が届いたことを模す
            BookDataSync.insert(BookData(name: "メイン帳簿", sortOrder: 0, isMain: true))
        }

        let start = Date()
        await coordinator.waitOutFreshInstallRaceWindowIfNeeded(
            initialImportState: .completed,
            lastSyncEventAtProvider: { Date() } // 常に「直近に同期活動あり」を模し、静穏期間では絶対に抜けないようにする
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "待機の途中で他端末の帳簿が届いたら、上限まで待たず即座に抜けること")
        XCTAssertFalse(BookDataSync.fetchAll().isEmpty)
    }

    func testWaitOutFreshInstallRaceWindowStopsAtHardCapWhenActivityNeverQuiets() async {
        // lastSyncEventAtProviderが常に「ついさっき」を返す(＝同期活動が絶え間なく続いている)
        // 状況でも、freshInstallGraceWindow(上限)に達したら必ず待機を終えること
        // (以前の固定5秒sleepと同じ「最後は必ず進む」という安全側フォールバックの性質を保つ)。
        let coordinator = CoreDataStartupCoordinator()
        coordinator.freshInstallGraceWindow = 0.3
        coordinator.freshInstallPollInterval = 0.05
        coordinator.freshInstallQuietPeriod = 5
        UserDefaults.standard.removeObject(forKey: BookMigrationService.establishedMainBookIdKey)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty)

        let start = Date()
        await coordinator.waitOutFreshInstallRaceWindowIfNeeded(
            initialImportState: .completed,
            lastSyncEventAtProvider: { Date() }
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.25)
        XCTAssertLessThan(elapsed, 1.0, "同期活動が続いていても、上限(freshInstallGraceWindow)で必ず待機を終えること")
    }

    func testWaitOutFreshInstallRaceWindowReturnsImmediatelyWhenAlreadyEstablished() async throws {
        let coordinator = CoreDataStartupCoordinator()
        coordinator.freshInstallGraceWindow = 5 // 長く設定しても、確立済みなら待たないことを確認する
        UserDefaults.standard.set(UUID().uuidString, forKey: BookMigrationService.establishedMainBookIdKey)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty)

        let start = Date()
        await coordinator.waitOutFreshInstallRaceWindowIfNeeded(
            initialImportState: .completed,
            lastSyncEventAtProvider: { nil }
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "確立済みの端末は、5秒の猶予設定があっても待たずに即座に返ること")
    }

    func testWaitOutFreshInstallRaceWindowReturnsImmediatelyWhenBookAlreadyExists() async throws {
        let coordinator = CoreDataStartupCoordinator()
        coordinator.freshInstallGraceWindow = 5
        UserDefaults.standard.removeObject(forKey: BookMigrationService.establishedMainBookIdKey)
        BookDataSync.insert(BookData(name: "メイン帳簿", sortOrder: 0, isMain: true))

        let start = Date()
        await coordinator.waitOutFreshInstallRaceWindowIfNeeded(
            initialImportState: .completed,
            lastSyncEventAtProvider: { nil }
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "ローカルに既にBookがあるなら、未確立(establishedMainBookId=nil)でも待たないこと")
    }

    // MARK: - shouldContinueWaitingForFreshInstallRace(_:)の純粋関数テスト

    func testShouldContinueWaitingTrueWithinHardCapAndQuietPeriodNotYetElapsed() {
        let start = Date()
        XCTAssertTrue(
            CoreDataStartupCoordinator.shouldContinueWaitingForFreshInstallRace(
                now: start.addingTimeInterval(0.1),
                waitStartedAt: start, hardCap: 5, quietPeriod: 1.5, lastSyncEventAt: nil
            )
        )
    }

    func testShouldContinueWaitingFalseOnceHardCapElapsedEvenIfQuietPeriodNotElapsed() {
        let start = Date()
        XCTAssertFalse(
            CoreDataStartupCoordinator.shouldContinueWaitingForFreshInstallRace(
                now: start.addingTimeInterval(5.1),
                waitStartedAt: start, hardCap: 5, quietPeriod: 1.5,
                lastSyncEventAt: start.addingTimeInterval(5.0) // ついさっき同期イベントがあったとしても
            ),
            "hardCapを過ぎたら、静穏期間が未経過でも必ず待機を終えること(安全側フォールバック)"
        )
    }

    func testShouldContinueWaitingFalseOnceQuietPeriodElapsedSinceStartWithNoSyncEvent() {
        let start = Date()
        XCTAssertFalse(
            CoreDataStartupCoordinator.shouldContinueWaitingForFreshInstallRace(
                now: start.addingTimeInterval(2.0),
                waitStartedAt: start, hardCap: 5, quietPeriod: 1.5, lastSyncEventAt: nil
            ),
            "同期イベントを一度も観測していない場合、待機開始時刻を基準に静穏期間を測ること"
        )
    }

    func testShouldContinueWaitingTrueWhenRecentSyncEventKeepsExtendingQuietPeriod() {
        let start = Date()
        XCTAssertTrue(
            CoreDataStartupCoordinator.shouldContinueWaitingForFreshInstallRace(
                now: start.addingTimeInterval(4.0),
                waitStartedAt: start, hardCap: 5, quietPeriod: 1.5,
                lastSyncEventAt: start.addingTimeInterval(3.9) // 0.1秒前に同期イベントがあった
            ),
            "最近の同期イベントがあれば、待機開始からの経過時間に関わらず静穏期間をそこから測り直し、待ち続けること"
        )
    }
}
