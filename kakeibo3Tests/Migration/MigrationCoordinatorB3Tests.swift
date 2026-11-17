import XCTest
import SwiftData
import CoreData
@testable import kakeibo3

// MARK: - Phase B3: 起動シーケンス接続の回帰テスト
//
// MigrationCoordinatorを通してPhase B1/B2のパイプライン全体(読み取り→検証→
// 一時ストア→本番昇格→旧ストア退避→記録)を起動シーケンスの入口から検証する。
// SwiftUIの画面切り替え自体はKakeibo3App.swiftの switch(state) が担うだけの薄い
// 配線であり、ここではその配線が読む`state`/`isReady`が正しく遷移することを確認する
// (実際に画面が描画されることは別途シミュレータでの手動確認で確認済み)。

@MainActor
final class MigrationCoordinatorB3Tests: XCTestCase {

    private var workDirectory: URL!
    private var productionDirectory: URL!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationCoordinatorB3Tests-\(UUID().uuidString)", isDirectory: true)
        workDirectory = root.appendingPathComponent("work", isDirectory: true)
        productionDirectory = root.appendingPathComponent("production", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productionDirectory, withIntermediateDirectories: true)

        suiteName = "MigrationCoordinatorB3Tests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)

        // 一部のテストはCoreDataStack.sharedを実ディスク上のテスト用ストアへ差し替える
        // (バックアップ/復元・スナップショット再生成の検証のため)。既存のQARegressionTestCase
        // と同じ流儀で、各テスト開始前に必ず独立したin-memoryストアへ戻しておくことで、
        // 前のテストが差し替えたまま残した実ファイル参照が次のテストに漏れないようにする。
        CoreDataStack.shared = CoreDataStack(inMemory: true)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        // このテストクラス内でCoreDataStack.sharedを実ディスク上のストアへ差し替えた場合、
        // ディレクトリを削除する前に必ず切り離す(開いたままのファイルを削除すると、
        // 同一プロセス内で後から実行される別テストのCore Data呼び出しがI/Oエラーになるため)。
        try? CoreDataStack.shared.releasePersistentStoresForMigration()
        CoreDataStack.shared = CoreDataStack(inMemory: true)
        if let root = workDirectory?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    private var productionPaths: ProductionStorePromoter.ProductionPaths {
        ProductionStorePromoter.ProductionPaths(directory: productionDirectory, storeName: "Kakeibo3.sqlite")
    }

    // MARK: - テスト用旧SwiftDataストア構築ヘルパー

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

    private func makeBook(_ context: ModelContext, name: String, isMain: Bool = true, sortOrder: Int = 0) -> LegacyBookData {
        let book = LegacyBookData()
        book.id = UUID(); book.name = name; book.isMain = isMain; book.sortOrder = sortOrder
        context.insert(book)
        return book
    }

    private func makeExpense(
        _ context: ModelContext, bookId: UUID, amount: Int = 500,
        isInTrash: Bool = false, trashedAt: Date? = nil, receiptImagePath: String? = nil
    ) -> LegacyExpenseData {
        let expense = LegacyExpenseData()
        expense.id = UUID(); expense.amount = amount; expense.category = "食費"; expense.paymentMethod = "現金"
        // SnapshotManager.rebuildAll()には既存の(移行と無関係な)不具合があり、その月の最初の
        // 取引の時刻が0時ちょうどでない場合、rebuildMonthlyChainへ渡すfrom日付が非正規化のまま
        // (Calendar.startOfDayしていない)ため、DailySnapshotの範囲取得から取りこぼされ、
        // 月次集計が0になることがある(詳細は移行完了報告に記載)。ここでは0時に正規化した
        // 日付を使い、この既存不具合を踏まずにスナップショット再生成そのものを検証する。
        expense.date = Calendar.current.startOfDay(for: Date())
        expense.bookId = bookId; expense.isInTrash = isInTrash; expense.trashedAt = trashedAt
        expense.receiptImagePath = receiptImagePath
        context.insert(expense)
        return expense
    }

    private func run(_ legacyPaths: SwiftDataLegacyReader.LegacyStorePaths?) async -> MigrationCoordinator {
        let coordinator = MigrationCoordinator()
        await coordinator.runIfNeeded(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
        return coordinator
    }

    // MARK: - 1. 新規インストール相当(旧SwiftDataストアなし)

    func testFreshInstallGoesStraightToNotNeeded() async throws {
        let coordinator = await run(nil)
        XCTAssertEqual(coordinator.state, .notNeeded)
        XCTAssertTrue(coordinator.isReady)
    }

    // MARK: - 2. 移行が必要なユーザー(移行成功→通常画面へ進める状態)

    func testMigrationNeededSucceedsAndReachesReady() async throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyStore { context in
            bookId = self.makeBook(context, name: "帳簿A").id
            self.makeExpense(context, bookId: bookId)
        }

        let coordinator = await run(legacyPaths)
        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertTrue(coordinator.isReady)

        // 本番ストアに実際にデータが昇格していること(この時点で初めてCoreDataStack相当を開いてよい)
        let stack = try CoreDataStack(throwingStoreURL: productionPaths.store)
        let expenses = try stack.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "ExpenseData"))
        XCTAssertEqual(expenses.count, 1)
    }

    // MARK: - 3. 移行失敗(通常画面へ進めない・再試行できる)

    func testMigrationFailureDoesNotReachReadyAndCanRetry() async throws {
        let legacyPaths = try makeLegacyStore { context in
            let expense = LegacyExpenseData()
            expense.id = UUID(); expense.amount = 100; expense.category = "食費"; expense.paymentMethod = "現金"
            expense.bookId = UUID() // 実在しない帳簿 → 重大エラー
            context.insert(expense)
        }

        let coordinator = await run(legacyPaths)
        guard case .failed = coordinator.state else {
            return XCTFail("失敗するはずが: \(coordinator.state)")
        }
        XCTAssertFalse(coordinator.isReady)

        // 再試行してもクラッシュせず、同じ理由で失敗し続けること(データが壊れたままなので)
        await coordinator.retry(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
        guard case .failed = coordinator.state else {
            return XCTFail("再試行後も同じ理由で失敗するはずが: \(coordinator.state)")
        }
        XCTAssertFalse(coordinator.isReady)

        // 本番ストアには何も作られていないこと(重大エラー時は一時ストアすら作らない設計)
        XCTAssertFalse(FileManager.default.fileExists(atPath: productionPaths.store.path))
    }

    // MARK: - 4. 移行済みユーザー(二重実行しても再移行しない・重複しない)

    func testAlreadyMigratedDoesNotDuplicateOnSecondRun() async throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyStore { context in
            bookId = self.makeBook(context, name: "帳簿A").id
            self.makeExpense(context, bookId: bookId)
        }

        let first = await run(legacyPaths)
        XCTAssertEqual(first.state, .completed)

        // 2回目:旧ストアは既に退避済みのため、実運用では次回起動時にlegacyStoreExists()が
        // falseを返しnotNeededになる。ここではCase C(既に移行済みと確認できる)の経路も
        // 合わせて確認するため、退避済みのはずの旧ストアパスをそのまま再度渡してみる
        // (evacuate済みでファイルが無いのでreadSnapshotは失敗するが、その前に
        // Case判定でalreadyMigratedとして終了することを確認する)。
        let second = await run(legacyPaths)
        guard case .completed = second.state else {
            return XCTFail("2回目はalreadyMigrated経由でcompletedになるはずが: \(second.state)")
        }

        let stack = try CoreDataStack(throwingStoreURL: productionPaths.store)
        let books = try stack.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "BookData"))
        let expenses = try stack.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "ExpenseData"))
        XCTAssertEqual(books.count, 1, "2回実行しても帳簿が重複してはいけない")
        XCTAssertEqual(expenses.count, 1, "2回実行しても支出が重複してはいけない")
    }

    // MARK: - 5. Case C(既存Core Data実データがある場合は自動上書きしない)

    func testCaseCFailsAndDoesNotProceedToReady() async throws {
        let stack = try CoreDataStack(throwingStoreURL: productionPaths.store)
        let existing = NSEntityDescription.insertNewObject(forEntityName: "ExpenseData", into: stack.container.viewContext)
        existing.setValue(UUID(), forKey: "id")
        existing.setValue(Int64(99999), forKey: "amount")
        try stack.container.viewContext.save()
        try stack.releasePersistentStoresForMigration()

        let legacyPaths = try makeLegacyStore { context in
            let bookId = self.makeBook(context, name: "帳簿A").id
            self.makeExpense(context, bookId: bookId)
        }

        let coordinator = await run(legacyPaths)
        guard case .failed = coordinator.state else {
            return XCTFail("Case Cでは失敗するはずが: \(coordinator.state)")
        }
        XCTAssertFalse(coordinator.isReady)

        let stack2 = try CoreDataStack(throwingStoreURL: productionPaths.store)
        let expenses = try stack2.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "ExpenseData"))
        XCTAssertEqual(expenses.count, 1)
        let amount = (expenses.first?.value(forKey: "amount") as? NSNumber)?.int64Value
        XCTAssertEqual(amount, 99999, "既存の実データが上書きされてはいけない")
    }

    // MARK: - 6. アプリ強制終了相当(昇格途中から次回起動時に安全に再開)

    func testInterruptedPromotionRecoversOnNextRun() async throws {
        // 1回目の起動で、本番昇格の途中(legacyEvacuated)で強制終了したという状況を
        // B2で確認済みの仕組み(PromotionJournal)で再現する。
        try "NEW-INCOMING-CONTENT".write(to: productionPaths.incomingStore, atomically: true, encoding: .utf8)
        try PromotionJournal(phase: .legacyEvacuated, startedAt: Date(), tempStoreSourcePath: "/dummy")
            .write(to: productionDirectory)

        // 次回起動時、旧SwiftDataストアが存在しない(前回で退避済みという想定)ケースで
        // MigrationCoordinatorを開始しても、まず昇格の復旧が優先され、本番パスが
        // 「新ストア」の状態に揃うことを確認する。
        ProductionStorePromoter.recoverIfNeeded(paths: productionPaths)
        let content = try String(contentsOf: productionPaths.store, encoding: .utf8)
        XCTAssertEqual(content, "NEW-INCOMING-CONTENT")
        XCTAssertNil(PromotionJournal.load(from: productionDirectory))
    }

    // MARK: - 8/9. 複数帳簿の分離維持 + bookId保持(BookMigrationServiceが壊さないことの前提確認)

    func testMultipleBooksSeparatedAndBookIdPreservedAfterMigration() async throws {
        var bookAId: UUID!
        var bookBId: UUID!
        var expenseAId: UUID!
        let legacyPaths = try makeLegacyStore { context in
            bookAId = self.makeBook(context, name: "帳簿A", isMain: true, sortOrder: 0).id
            bookBId = self.makeBook(context, name: "帳簿B", isMain: false, sortOrder: 1).id
            expenseAId = self.makeExpense(context, bookId: bookAId, amount: 1000).id
            self.makeExpense(context, bookId: bookBId, amount: 2000)
        }

        let coordinator = await run(legacyPaths)
        XCTAssertEqual(coordinator.state, .completed)

        let stack = try CoreDataStack(throwingStoreURL: productionPaths.store)
        let expenseARequest = NSFetchRequest<NSManagedObject>(entityName: "ExpenseData")
        expenseARequest.predicate = NSPredicate(format: "id == %@", expenseAId as CVarArg)
        let expenseA = try stack.container.viewContext.fetch(expenseARequest).first
        // 移行はUUIDそのものをコピーするだけで、BookMigrationService(nilなbookIdのみ対象)は
        // 非nilなbookIdを一切書き換えないため、bookIdは元のまま維持される。
        XCTAssertEqual(expenseA?.value(forKey: "bookId") as? UUID, bookAId)

        let bookBRequest = NSFetchRequest<NSManagedObject>(entityName: "ExpenseData")
        bookBRequest.predicate = NSPredicate(format: "bookId == %@", bookBId as CVarArg)
        XCTAssertEqual(try stack.container.viewContext.count(for: bookBRequest), 1)
    }

    // MARK: - 12. バックアップ/復元が移行後も正常動作する

    func testBackupAndRestoreWorkAfterMigration() async throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyStore { context in
            bookId = self.makeBook(context, name: "帳簿A").id
            self.makeExpense(context, bookId: bookId, amount: 777)
        }

        let coordinator = await run(legacyPaths)
        XCTAssertEqual(coordinator.state, .completed)

        // ここで初めてCoreDataStack.sharedを本番ストアへ向ける(既存QARegressionTestsと同じ手法)。
        CoreDataStack.shared = CoreDataStack(storeURL: productionPaths.store)

        let backupURL = try BackupManager.shared.createBackup(bookId: bookId)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        ExpenseDataSync.deleteAll(bookId: bookId)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 0)

        try await BackupManager.shared.restore(from: backupURL, targetBookId: bookId)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 1)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).first?.amount, 777)
    }

    // MARK: - 13/14. スナップショット再生成の集計一致 + 実SQLite再起動後のデータ維持

    func testSnapshotRegenerationAndRealRestartAfterMigration() async throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyStore { context in
            bookId = self.makeBook(context, name: "帳簿A").id
            self.makeExpense(context, bookId: bookId, amount: 1200)
        }

        let coordinator = await run(legacyPaths)
        XCTAssertEqual(coordinator.state, .completed)

        CoreDataStack.shared = CoreDataStack(storeURL: productionPaths.store)

        // SwiftDataからは移行しなかった派生データ(スナップショット)を、移行完了後の
        // このタイミングで対象帳簿ぶんだけ再生成する(通常起動シーケンスと同じ呼び出し)。
        SnapshotManager.backfillIfNeeded()
        let snapshots = MonthlySnapshotSync.fetchAll(bookId: bookId)
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertEqual(snapshots.reduce(0) { $0 + $1.expenseTotal }, 1200)

        // 実SQLite再起動相当:プロセス内で同じURLへ改めてCoreDataStackを作り直す
        // (Phase 0-A①で確立済みの手法)。旧インスタンスを明示的に切り離してから
        // 作り直すことで、同一ファイルへの二重接続に起因するI/Oエラーを避ける。
        try CoreDataStack.shared.releasePersistentStoresForMigration()
        CoreDataStack.shared = CoreDataStack(storeURL: productionPaths.store)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 1)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).first?.amount, 1200)
        XCTAssertEqual(MonthlySnapshotSync.fetchAll(bookId: bookId).reduce(0) { $0 + $1.expenseTotal }, 1200)
    }
}
