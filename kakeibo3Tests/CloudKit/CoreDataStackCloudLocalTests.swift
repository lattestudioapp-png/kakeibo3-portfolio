import XCTest
import CoreData
@testable import kakeibo3

// MARK: - CloudKit Step 2A: Cloud/Local 2ストア構成のテスト
//
// 対象: NSPersistentCloudKitContainerへの切り替え・Cloud/Local 2ストア構成・
// persistent history tracking / remote change通知・viewContextのmergePolicy/
// transactionAuthor・テスト/Migration用ストアがCloudKitへ絶対に繋がらないこと。
//
// Step 2Aの時点では既存Kakeibo3.sqliteからの実データ移行はまだ実装していないため、
// ここでは常に新規・空の一時ディレクトリ上でCloud/Local 2ストアを構築して検証する。

final class CoreDataStackCloudLocalTests: XCTestCase {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoreDataStackCloudLocalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 1〜2. Cloud/Localそれぞれが自分のConfigurationだけをロードする

    func testCloudStoreDescriptionUsesCloudConfiguration() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloudDescription = CoreDataStack.cloudStoreDescription(baseDirectory: dir, enableCloudKit: false)
        XCTAssertEqual(cloudDescription.configuration, CoreDataStack.cloudConfigurationName)
        XCTAssertEqual(cloudDescription.url?.lastPathComponent, CoreDataStack.cloudStoreFileName)
    }

    func testLocalStoreDescriptionUsesLocalConfiguration() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let localDescription = CoreDataStack.localStoreDescription(baseDirectory: dir)
        XCTAssertEqual(localDescription.configuration, CoreDataStack.localConfigurationName)
        XCTAssertEqual(localDescription.url?.lastPathComponent, CoreDataStack.localStoreFileName)
    }

    // MARK: - 3〜4. Cloud storeにLocal Entityが作られない・Local storeにCloud Entityが作られない

    func testCloudEntityIsRoutedToCloudStoreNotLocalStore() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        let context = stack.container.viewContext

        let book = CDBookData(context: context)
        book.id = UUID()
        book.name = "帳簿A"
        book.createdAt = Date()
        try context.save()

        let cloudStore = try XCTUnwrap(store(named: CoreDataStack.cloudStoreFileName, in: stack))
        let localStore = try XCTUnwrap(store(named: CoreDataStack.localStoreFileName, in: stack))

        XCTAssertEqual(book.objectID.persistentStore, cloudStore, "Cloud EntityはCloud storeへ書き込まれること")
        XCTAssertNotEqual(book.objectID.persistentStore, localStore, "Cloud EntityはLocal storeへ書き込まれないこと")

        // Local store側だけを対象にBookDataをfetchしても0件であること
        let request = CDBookData.fetchRequest()
        request.affectedStores = [localStore]
        let resultsInLocalStore = try context.fetch(request)
        XCTAssertTrue(resultsInLocalStore.isEmpty, "Local storeにCloud Entity(BookData)が作られていないこと")
    }

    func testLocalEntityIsRoutedToLocalStoreNotCloudStore() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        let context = stack.container.viewContext

        let snapshot = CDDailySnapshot(context: context)
        snapshot.bookId = UUID()
        snapshot.date = Date()
        snapshot.updatedAt = Date()
        try context.save()

        let cloudStore = try XCTUnwrap(store(named: CoreDataStack.cloudStoreFileName, in: stack))
        let localStore = try XCTUnwrap(store(named: CoreDataStack.localStoreFileName, in: stack))

        XCTAssertEqual(snapshot.objectID.persistentStore, localStore, "Local EntityはLocal storeへ書き込まれること")
        XCTAssertNotEqual(snapshot.objectID.persistentStore, cloudStore, "Local EntityはCloud storeへ書き込まれないこと")

        // Cloud store側だけを対象にDailySnapshotをfetchしても0件であること
        let request = CDDailySnapshot.fetchRequest()
        request.affectedStores = [cloudStore]
        let resultsInCloudStore = try context.fetch(request)
        XCTAssertTrue(resultsInCloudStore.isEmpty, "Cloud storeにLocal Entity(DailySnapshot)が作られていないこと")
    }

    // MARK: - 5〜6. CloudKit optionがCloud storeだけに設定される
    //
    // 実際にストアをロードする(NSPersistentCloudKitContainerのCloudKitミラーリング機構を
    // 起動する)と、同一プロセス内で本番の`CoreDataStack.shared`(テストホストアプリ起動時に
    // 一度だけ実CloudKit接続で生成される)と接続先が重複し、エクスポート活動登録の競合を
    // 起こすことを実測で確認した。この項目は「descriptionにどの値が設定されるか」だけを
    // 検証すればよいため、cloudStoreDescription(baseDirectory:enableCloudKit:)を直接呼び、
    // ロードは一切行わない。

    func testOnlyCloudStoreHasCloudKitContainerOptions() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cloudDescription = CoreDataStack.cloudStoreDescription(baseDirectory: dir, enableCloudKit: true)

        XCTAssertNotNil(cloudDescription.cloudKitContainerOptions, "Cloud storeにはcloudKitContainerOptionsが設定されていること")
        XCTAssertEqual(
            cloudDescription.cloudKitContainerOptions?.containerIdentifier,
            CoreDataStack.cloudKitContainerIdentifier
        )
    }

    func testLocalStoreHasNoCloudKitContainerOptionsByDescription() throws {
        // Local側はenableCloudKitフラグの影響を受けず常にnilであることの確認
        // (Local storeはenableCloudKit: falseで安全にロードできるため、実際に
        // ロードして検証する)。
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }

        let localDescription = try XCTUnwrap(
            stack.container.persistentStoreDescriptions.first { $0.configuration == CoreDataStack.localConfigurationName }
        )
        XCTAssertNil(localDescription.cloudKitContainerOptions, "Local storeはcloudKitContainerOptionsがnilであること")
    }

    // MARK: - 7. テスト用stack(inMemory)でCloudKit option nil

    func testInMemoryStackHasNoCloudKitContainerOptions() {
        let stack = CoreDataStack(inMemory: true)
        let description = stack.container.persistentStoreDescriptions.first
        XCTAssertNotNil(description)
        XCTAssertNil(description?.cloudKitContainerOptions, "テスト用in-memory stackはCloudKitへ絶対に繋がらないこと")
        XCTAssertNil(description?.configuration, "テスト用stackはConfiguration指定無し(Default=全17エンティティ)であること")
    }

    func testExplicitStoreURLStackHasNoCloudKitContainerOptions() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("test.sqlite")
        let stack = CoreDataStack(storeURL: storeURL)
        let description = stack.container.persistentStoreDescriptions.first
        XCTAssertNotNil(description)
        XCTAssertNil(description?.cloudKitContainerOptions, "storeURL指定のテスト用stackもCloudKitへ絶対に繋がらないこと")
    }

    // MARK: - 8. Migration用stack(throwingStoreURL)でCloudKit option nil

    func testMigrationStackHasNoCloudKitContainerOptions() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("migration_temp.sqlite")
        let stack = try CoreDataStack(throwingStoreURL: storeURL)
        let description = stack.container.persistentStoreDescriptions.first
        XCTAssertNotNil(description)
        XCTAssertNil(description?.cloudKitContainerOptions, "Migration用一時stackはCloudKitへ絶対に繋がらないこと")
    }

    // MARK: - 8b. isCloudSyncActive: テスト用stackは「iCloud同期」ユーザー設定に関わらず常にfalse
    //
    // CloudSyncSettings.isUserEnabledPreference()がtrueを返す状態でも、inMemory/storeURL/
    // throwingStoreURLの各テスト用init経路は絶対にCloudKitへ繋がらないことを保証する
    // （「テスト用CoreDataStackはこれまで通りCloudKit無効固定にする」という要件そのものの検証）。

    func testTestPathsHaveCloudSyncInactiveEvenWhenUserPreferenceIsEnabled() throws {
        let previous = UserDefaults.standard.object(forKey: CloudSyncSettings.isUserEnabledKey) as? Bool
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: CloudSyncSettings.isUserEnabledKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isUserEnabledKey)
            }
        }
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isUserEnabledKey)
        XCTAssertTrue(CloudSyncSettings.isUserEnabledPreference())

        XCTAssertFalse(CoreDataStack(inMemory: true).isCloudSyncActive)

        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(CoreDataStack(storeURL: dir.appendingPathComponent("test.sqlite")).isCloudSyncActive)
        XCTAssertFalse(try CoreDataStack(throwingStoreURL: dir.appendingPathComponent("migration_temp.sqlite")).isCloudSyncActive)
    }

    func testCloudLocalStackIsCloudSyncActiveMatchesEnableCloudKitParameter() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let enabled = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: true, enableHistoryTracking: false)
        defer { try? enabled.releasePersistentStoresForMigration() }
        XCTAssertTrue(enabled.isCloudSyncActive)

        let dir2 = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir2) }
        let disabled = try CoreDataStack(cloudLocalDirectory: dir2, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? disabled.releasePersistentStoresForMigration() }
        XCTAssertFalse(disabled.isCloudSyncActive)
    }

    // MARK: - 9〜10. persistent history tracking / remote change通知が両ストアで有効

    // これらはdescriptionの設定値だけを見ればよいため、他のテストと違い実際にストアを
    // ロードしない(CoreDataStackCloudLocalTestsが本番相当の2ストアを繰り返しロードする
    // ことそのものが、無関係な別テストを巻き込んでプロセスを不安定化させることを
    // 実測で確認したため、ロードが不要な検証はできるだけロード無しで済ませる)。

    func testBothStoresHavePersistentHistoryTrackingEnabled() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let descriptions = [
            CoreDataStack.cloudStoreDescription(baseDirectory: dir, enableCloudKit: false),
            CoreDataStack.localStoreDescription(baseDirectory: dir),
        ]
        for description in descriptions {
            let value = description.options[NSPersistentHistoryTrackingKey] as? Bool
            XCTAssertEqual(value, true, "\(description.configuration ?? "?") storeでpersistent history trackingが有効であること")
        }
    }

    func testBothStoresHaveRemoteChangeNotificationEnabled() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let descriptions = [
            CoreDataStack.cloudStoreDescription(baseDirectory: dir, enableCloudKit: false),
            CoreDataStack.localStoreDescription(baseDirectory: dir),
        ]
        for description in descriptions {
            let value = description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? Bool
            XCTAssertEqual(value, true, "\(description.configuration ?? "?") storeでremote change通知が有効であること")
        }
    }

    // MARK: - 11〜13. viewContextのautomaticallyMergesChangesFromParent / mergePolicy / transactionAuthor

    func testViewContextAutomaticallyMergesChangesFromParent() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        XCTAssertTrue(stack.container.viewContext.automaticallyMergesChangesFromParent)
    }

    func testViewContextMergePolicyIsExplicit() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        let mergePolicy = stack.container.viewContext.mergePolicy as? NSMergePolicy
        XCTAssertTrue(mergePolicy === (NSMergeByPropertyObjectTrumpMergePolicy as? NSMergePolicy), "mergePolicyがNSMergeByPropertyObjectTrumpMergePolicyであること")
    }

    func testViewContextTransactionAuthorIsSet() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        XCTAssertEqual(stack.container.viewContext.transactionAuthor, CoreDataStack.transactionAuthor)
    }

    // MARK: - 14. 2ストアとも実SQLiteで再オープン可能

    func testBothStoresSurviveRealSQLiteRestart() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bookId = UUID()
        let snapshotBookId = UUID()

        do {
            let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
            defer { try? stack.releasePersistentStoresForMigration() }
            let context = stack.container.viewContext
            let book = CDBookData(context: context)
            book.id = bookId
            book.name = "帳簿A"
            book.createdAt = Date()

            let snapshot = CDDailySnapshot(context: context)
            snapshot.bookId = snapshotBookId
            snapshot.date = Date()
            snapshot.updatedAt = Date()
            snapshot.expenseTotal = 1234

            try context.save()
        }

        // 同じディレクトリを指して開き直す(アプリ再起動を模す)
        let reopened = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? reopened.releasePersistentStoresForMigration() }
        let context = reopened.container.viewContext

        let bookRequest = CDBookData.fetchRequest()
        bookRequest.predicate = NSPredicate(format: "id == %@", bookId as CVarArg)
        let books = try context.fetch(bookRequest)
        XCTAssertEqual(books.count, 1, "Cloud storeの再起動後もBookDataが残っていること")

        let snapshotRequest = CDDailySnapshot.fetchRequest()
        snapshotRequest.predicate = NSPredicate(format: "bookId == %@", snapshotBookId as CVarArg)
        let snapshots = try context.fetch(snapshotRequest)
        XCTAssertEqual(snapshots.count, 1, "Local storeの再起動後もDailySnapshotが残っていること")
        XCTAssertEqual(snapshots.first?.expenseTotal, 1234)

        // 実ファイルとして両方のsqliteが存在すること
        XCTAssertTrue(FileManager.default.fileExists(atPath: CoreDataStack.cloudStoreURL(baseDirectory: dir).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CoreDataStack.localStoreURL(baseDirectory: dir).path))
    }

    // MARK: - Helpers

    private func store(named fileName: String, in stack: CoreDataStack) -> NSPersistentStore? {
        stack.container.persistentStoreCoordinator.persistentStores.first { $0.url?.lastPathComponent == fileName }
    }
}
