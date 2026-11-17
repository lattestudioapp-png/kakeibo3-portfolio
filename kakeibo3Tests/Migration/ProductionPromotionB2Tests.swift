import XCTest
import SwiftData
import CoreData
@testable import kakeibo3

// MARK: - Phase B2: 本番ストアへの安全な昇格の回帰テスト
//
// この段階でもKakeibo3App / CoreDataStack.shared(通常起動での使用) / CloudKit関連には
// 一切触れない。productionDirectoryは実際のApplication Supportではなく、テストごとに
// 独立した一時ディレクトリを渡す。UserDefaultsも専用スイートを使い、実際の
// UserDefaults.standardを汚染しない。

final class ProductionPromotionB2Tests: XCTestCase {

    private var workDirectory: URL!
    private var productionDirectory: URL!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProductionPromotionB2Tests-\(UUID().uuidString)", isDirectory: true)
        workDirectory = root.appendingPathComponent("work", isDirectory: true)
        productionDirectory = root.appendingPathComponent("production", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productionDirectory, withIntermediateDirectories: true)

        suiteName = "ProductionPromotionB2Tests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        if let root = workDirectory?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    private var productionPaths: ProductionStorePromoter.ProductionPaths {
        ProductionStorePromoter.ProductionPaths(directory: productionDirectory, storeName: "Kakeibo3.sqlite")
    }

    // MARK: - テスト用旧SwiftDataストア構築ヘルパー(B1と同じ流儀)

    @discardableResult
    private func makeLegacyStore(
        name: String = "legacy",
        _ build: (ModelContext) -> Void
    ) throws -> SwiftDataLegacyReader.LegacyStorePaths {
        let dir = workDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("default.store")
        let schema = Schema(LegacySchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        build(context)
        try context.save()
        return SwiftDataLegacyReader.LegacyStorePaths(
            store: storeURL,
            wal: dir.appendingPathComponent("default.store-wal"),
            shm: dir.appendingPathComponent("default.store-shm")
        )
    }

    private func makeBookAndExpense(_ context: ModelContext, bookName: String = "帳簿A") -> UUID {
        let book = LegacyBookData()
        book.id = UUID(); book.name = bookName; book.isMain = true
        context.insert(book)
        let expense = LegacyExpenseData()
        expense.id = UUID(); expense.amount = 500; expense.category = "食費"; expense.paymentMethod = "現金"; expense.bookId = book.id
        context.insert(expense)
        return book.id
    }

    private func migrate(_ legacyPaths: SwiftDataLegacyReader.LegacyStorePaths) -> MigrationOutcome {
        MigrationBootstrap.migrateAndPromote(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
    }

    /// 本番ディレクトリに、実データを含むCore Dataストアを直接作る(Case C再現用)。
    private func makeProductionStoreWithRealData() throws {
        let stack = try CoreDataStack(throwingStoreURL: productionPaths.store)
        let context = stack.container.viewContext
        let expense = NSEntityDescription.insertNewObject(forEntityName: "ExpenseData", into: context)
        expense.setValue(UUID(), forKey: "id")
        expense.setValue(Int64(12345), forKey: "amount")
        expense.setValue("食費", forKey: "category")
        expense.setValue("現金", forKey: "paymentMethod")
        try context.save()
        try stack.releasePersistentStoresForMigration()
    }

    /// 注意: ここでストアを閉じてはいけない。releasePersistentStoresForMigration()を
    /// deferで呼ぶと、呼び出し元がまだ返り値のNSManagedObjectから属性を読み取っていない
    /// 時点でストアが切り離され、フェッチ済みオブジェクトがフォルト化されて値がnilに
    /// なってしまう(実際にこの実装ミスでtestCaseCRefusesAutomaticOverwriteが誤って
    /// 失敗した)。呼び出し元が読み終わるまでstackを生かしたままにする。
    private func fetchAll(_ entityName: String, from url: URL) throws -> [NSManagedObject] {
        let stack = try CoreDataStack(throwingStoreURL: url)
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try stack.container.viewContext.fetch(request)
    }

    // MARK: - 1. 本番昇格中断からの復旧

    func testRecoveryFromStagingReadyLeavesProductionUntouched() throws {
        try "OLD-PRODUCTION".write(to: productionPaths.store, atomically: true, encoding: .utf8)
        try "INCOMING".write(to: productionPaths.incomingStore, atomically: true, encoding: .utf8)
        try PromotionJournal(phase: .stagingReady, startedAt: Date(), tempStoreSourcePath: "/dummy").write(to: productionDirectory)

        ProductionStorePromoter.recoverIfNeeded(paths: productionPaths)

        let content = try String(contentsOf: productionPaths.store, encoding: .utf8)
        XCTAssertEqual(content, "OLD-PRODUCTION", "stagingReady中断時は本番パスへ一切手を付けていないはず")
    }

    func testRecoveryFromLegacyEvacuatedPromotesIncoming() throws {
        try "OLD-BACKUP".write(to: productionPaths.backupStore, atomically: true, encoding: .utf8)
        try "NEW-INCOMING".write(to: productionPaths.incomingStore, atomically: true, encoding: .utf8)
        try PromotionJournal(phase: .legacyEvacuated, startedAt: Date(), tempStoreSourcePath: "/dummy").write(to: productionDirectory)

        ProductionStorePromoter.recoverIfNeeded(paths: productionPaths)

        let content = try String(contentsOf: productionPaths.store, encoding: .utf8)
        XCTAssertEqual(content, "NEW-INCOMING", "legacyEvacuated中断時は.incomingを本番へ昇格し直すべき")
        XCTAssertNil(PromotionJournal.load(from: productionDirectory))
    }

    func testRecoveryFromIncomingPromotedJustClearsJournal() throws {
        try "ALREADY-NEW".write(to: productionPaths.store, atomically: true, encoding: .utf8)
        try PromotionJournal(phase: .incomingPromoted, startedAt: Date(), tempStoreSourcePath: "/dummy").write(to: productionDirectory)

        ProductionStorePromoter.recoverIfNeeded(paths: productionPaths)

        let content = try String(contentsOf: productionPaths.store, encoding: .utf8)
        XCTAssertEqual(content, "ALREADY-NEW")
        XCTAssertNil(PromotionJournal.load(from: productionDirectory))
    }

    // MARK: - 2. Manifest不一致

    func testManifestMismatchFailsAndRollsBackToPreviousProductionState() throws {
        try "PRE-EXISTING-PRODUCTION".write(to: productionPaths.store, atomically: true, encoding: .utf8)

        let legacyPaths = try makeLegacyStore { context in _ = self.makeBookAndExpense(context) }
        let snapshot = try SwiftDataLegacyReader.readSnapshot(paths: legacyPaths)
        let tempStoreURL = workDirectory.appendingPathComponent("fake-temp.sqlite")
        let tempStack = try CoreDataStack(throwingStoreURL: tempStoreURL)
        try TempCoreDataWriter.write(snapshot, into: tempStack.container.viewContext)
        try tempStack.releasePersistentStoresForMigration()

        let verifyStack = try CoreDataStack(throwingStoreURL: tempStoreURL)
        var wrongManifest = try MigrationVerifier.verify(snapshot: snapshot, context: verifyStack.container.viewContext)
        try verifyStack.releasePersistentStoresForMigration()
        wrongManifest.entityCounts["ExpenseData"] = 999 // わざと不一致にする

        let result = ProductionStorePromoter.promote(tempStoreURL: tempStoreURL, manifest: wrongManifest, paths: productionPaths)
        guard case .failure(.verificationFailed) = result else {
            return XCTFail("Manifest不一致は失敗するべき: \(result)")
        }

        let content = try String(contentsOf: productionPaths.store, encoding: .utf8)
        XCTAssertEqual(content, "PRE-EXISTING-PRODUCTION", "検証失敗時は昇格前の本番状態へロールバックされるべき")
        XCTAssertNil(PromotionJournal.load(from: productionDirectory), "ロールバック後はジャーナルも残さない")
    }

    // MARK: - 3. 旧SwiftDataストアのファイル組み合わせ(sqlite/wal/shmの有無)

    private func writeLegacyFiles(store: Bool, wal: Bool, shm: Bool) throws -> SwiftDataLegacyReader.LegacyStorePaths {
        let dir = workDirectory.appendingPathComponent("combo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = SwiftDataLegacyReader.LegacyStorePaths(
            store: dir.appendingPathComponent("default.store"),
            wal: dir.appendingPathComponent("default.store-wal"),
            shm: dir.appendingPathComponent("default.store-shm")
        )
        if store { try "S".write(to: paths.store, atomically: true, encoding: .utf8) }
        if wal { try "W".write(to: paths.wal, atomically: true, encoding: .utf8) }
        if shm { try "H".write(to: paths.shm, atomically: true, encoding: .utf8) }
        return paths
    }

    func testEvacuationHandlesSqliteOnly() throws {
        let paths = try writeLegacyFiles(store: true, wal: false, shm: false)
        try LegacyStoreEvacuator.evacuate(paths: paths)
        XCTAssertTrue(LegacyStoreEvacuator.isFullyEvacuated(paths: paths))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.store).path))
    }

    func testEvacuationHandlesWalOnly() throws {
        let paths = try writeLegacyFiles(store: false, wal: true, shm: false)
        try LegacyStoreEvacuator.evacuate(paths: paths)
        XCTAssertTrue(LegacyStoreEvacuator.isFullyEvacuated(paths: paths))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.wal).path))
    }

    func testEvacuationHandlesShmOnly() throws {
        let paths = try writeLegacyFiles(store: false, wal: false, shm: true)
        try LegacyStoreEvacuator.evacuate(paths: paths)
        XCTAssertTrue(LegacyStoreEvacuator.isFullyEvacuated(paths: paths))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.shm).path))
    }

    func testEvacuationHandlesSqliteAndWalOnly() throws {
        let paths = try writeLegacyFiles(store: true, wal: true, shm: false)
        try LegacyStoreEvacuator.evacuate(paths: paths)
        XCTAssertTrue(LegacyStoreEvacuator.isFullyEvacuated(paths: paths))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.store).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.wal).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.shm).path))
    }

    func testEvacuationHandlesSqliteAndShmOnly() throws {
        let paths = try writeLegacyFiles(store: true, wal: false, shm: true)
        try LegacyStoreEvacuator.evacuate(paths: paths)
        XCTAssertTrue(LegacyStoreEvacuator.isFullyEvacuated(paths: paths))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.store).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.shm).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.wal).path))
    }

    // MARK: - 4. Core Data実データあり(Case C)は自動上書きしない

    func testCaseCRefusesAutomaticOverwrite() throws {
        try makeProductionStoreWithRealData()
        let legacyPaths = try makeLegacyStore { context in _ = self.makeBookAndExpense(context) }

        let outcome = migrate(legacyPaths)
        guard case .failed(.productionStoreHasExistingData) = outcome else {
            return XCTFail("Case Cでは自動上書きせずエラーになるべき: \(outcome)")
        }

        // 実データは変更されていないこと
        let expenses = try fetchAll("ExpenseData", from: productionPaths.store)
        XCTAssertEqual(expenses.count, 1)
        let amount = (expenses.first?.value(forKey: "amount") as? NSNumber)?.int64Value
        XCTAssertEqual(amount, 12345)
    }

    // MARK: - 5. MigrationManifest破損 / 6. MigrationManifest欠落

    func testCorruptManifestDoesNotCountAsAlreadyMigrated() throws {
        try makeProductionStoreWithRealData()
        try "{ not valid json".write(to: productionDirectory.appendingPathComponent(MigrationCompletionRecorder.manifestFileName), atomically: true, encoding: .utf8)
        MigrationCompletionRecorder.markCompleted(in: userDefaults)

        let legacyPaths = try makeLegacyStore { context in _ = self.makeBookAndExpense(context) }
        let outcome = migrate(legacyPaths)
        guard case .failed(.productionStoreHasExistingData) = outcome else {
            return XCTFail("Manifestが壊れている場合は「既に移行済み」と判定してはいけない: \(outcome)")
        }
    }

    func testMissingManifestDoesNotCountAsAlreadyMigrated() throws {
        try makeProductionStoreWithRealData()
        MigrationCompletionRecorder.markCompleted(in: userDefaults) // フラグだけtrueにする

        let legacyPaths = try makeLegacyStore { context in _ = self.makeBookAndExpense(context) }
        let outcome = migrate(legacyPaths)
        guard case .failed(.productionStoreHasExistingData) = outcome else {
            return XCTFail("Manifestが無い場合は「既に移行済み」と判定してはいけない: \(outcome)")
        }
    }

    // MARK: - 7. 退避途中で失敗

    func testPartialEvacuationIsDetected() throws {
        let paths = try writeLegacyFiles(store: true, wal: true, shm: true)
        var callCount = 0
        do {
            try LegacyStoreEvacuator.evacuate(paths: paths) { source, destination in
                callCount += 1
                if callCount == 2 {
                    throw NSError(domain: "test", code: 1) // 2件目(wal)で失敗させる
                }
                try FileManager.default.moveItem(at: source, to: destination)
            }
            XCTFail("2件目で失敗するはず")
        } catch let error as LegacyStoreEvacuator.EvacuationError {
            guard case let .partialEvacuation(movedFiles, failedFile) = error else {
                return XCTFail("想定外のエラー: \(error)")
            }
            XCTAssertEqual(movedFiles, ["default.store"])
            XCTAssertEqual(failedFile, "default.store-wal")
        }

        // 1件目(store)は移動済み、2件目(wal)は元の場所に残ったまま、という
        // 「途中状態」が外から検出できること。
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.store.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: paths.store).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.wal.path))
        XCTAssertFalse(LegacyStoreEvacuator.isFullyEvacuated(paths: paths))
    }

    // MARK: - 8. 本番再オープン後Manifest一致(成功フロー全体)

    func testProductionReopenMatchesManifestAfterSuccessfulPromotion() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyStore { context in
            bookId = self.makeBookAndExpense(context, bookName: "帳簿A")
        }

        let outcome = migrate(legacyPaths)
        guard case let .promoted(manifest, _) = outcome else {
            return XCTFail("正常系は昇格成功するはず: \(outcome)")
        }

        XCTAssertNotNil(manifest.targetStoreIdentifier)
        XCTAssertEqual(manifest.entityCounts["ExpenseData"], 1)

        // 独立した3回目のオープンで、本番ストアの中身がManifestと一致することを確認する
        let stack = try CoreDataStack(throwingStoreURL: productionPaths.store)
        defer { try? stack.releasePersistentStoresForMigration() }
        try MigrationVerifier.reverify(manifest: manifest, context: stack.container.viewContext)
        try MigrationVerifier.verifyBookIdsExist(manifest: manifest, context: stack.container.viewContext)

        // 実際のNSStoreUUIDKeyもManifestと一致すること
        let identifier = ProductionStorePromoter.storeIdentifier(for: stack)
        XCTAssertEqual(identifier, manifest.targetStoreIdentifier)

        // 旧SwiftDataストアは退避されていること
        XCTAssertTrue(LegacyStoreEvacuator.isFullyEvacuated(paths: legacyPaths))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LegacyStoreEvacuator.backupURL(for: legacyPaths.store).path))

        // 完了記録(Manifest永続化・UserDefaultsフラグ)が残っていること
        XCTAssertTrue(MigrationCompletionRecorder.isFlagSet(in: userDefaults))
        XCTAssertNotNil(MigrationCompletionRecorder.loadPersistedManifest(from: productionDirectory))

        // 二重実行しても重複せず「既に移行済み」と判定されること
        let secondLegacyPaths = try makeLegacyStore(name: "legacy2") { context in _ = self.makeBookAndExpense(context) }
        let secondOutcome = migrate(secondLegacyPaths)
        guard case .alreadyMigrated = secondOutcome else {
            return XCTFail("2回目は既に移行済みと判定されるべき: \(secondOutcome)")
        }
    }
}
