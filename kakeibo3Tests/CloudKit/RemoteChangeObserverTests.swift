import XCTest
import CoreData
@testable import kakeibo3

// MARK: - RemoteChangeObserverのテスト
//
// CoreDataStackCloudLocalTests.swiftと同じcloudLocalDirectoryパターン（enableCloudKit: false,
// enableHistoryTracking: true）で、実ストア・実persistent historyを使って検証する
// （CloudKitへは繋がない）。「別端末からのCloudKit取り込み」は、同じディレクトリを指す
// 別のNSManagedObjectContextにtransactionAuthorをこのデバイス（"app"）とは異なる値へ
// 明示的に設定してから書き込むことでシミュレートする（本番コードは変更不要）。
final class RemoteChangeObserverTests: XCTestCase {

    private var userDefaultsSnapshot: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaultsSnapshot = UserDefaults.standard.dictionaryRepresentation()
        UserDefaults.standard.removeObject(forKey: RemoteChangeObserver.lastHistoryTokenKey)
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

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteChangeObserverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // SnapshotManager.rebuildAll()（引数無し・全帳簿版）はCDBookDataから対象帳簿一覧を
    // 列挙するため（SnapshotSourceDataLoader.loadAllBookIds参照）、CDExpenseDataだけでなく
    // CDBookDataも作っておかないと、対象帳簿として拾われずsnapshotが永遠に作られない。
    private func writeBook(to stack: CoreDataStack, bookId: UUID, author: String) throws {
        let context = stack.container.newBackgroundContext()
        context.transactionAuthor = author
        try context.performAndWait {
            let book = CDBookData(context: context)
            book.id = bookId
            book.name = "RemoteChangeObserverTests"
            book.createdAt = Date()
            try context.save()
        }
    }

    @discardableResult
    private func writeExpense(
        to stack: CoreDataStack, bookId: UUID, author: String
    ) throws -> UUID {
        let context = stack.container.newBackgroundContext()
        context.transactionAuthor = author
        let expenseId = UUID()
        try context.performAndWait {
            let expense = CDExpenseData(context: context)
            expense.id = expenseId
            expense.amount = 1000
            expense.date = Date()
            expense.paymentMethod = "現金"
            expense.category = "食費"
            expense.memo = ""
            expense.createdAt = Date()
            expense.bookId = bookId
            expense.isTestData = true
            try context.save()
        }
        return expenseId
    }

    private func writeLocalOnlySnapshot(to stack: CoreDataStack, bookId: UUID, author: String) throws {
        let context = stack.container.newBackgroundContext()
        context.transactionAuthor = author
        try context.performAndWait {
            let snapshot = CDDailySnapshot(context: context)
            snapshot.bookId = bookId
            snapshot.date = Date()
            snapshot.updatedAt = Date()
            try context.save()
        }
    }

    // MARK: - 1. リモート由来（author != "app"）のCloud store変更 → requestRebuildが呼ばれ、Snapshotが再計算される

    func testRemoteAuthoredCloudChangeTriggersSnapshotRebuild() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let bookId = UUID()
        try writeBook(to: stack, bookId: bookId, author: "otherDevice")
        try writeExpense(to: stack, bookId: bookId, author: "otherDevice")

        XCTAssertTrue(MonthlySnapshotSync.fetchAll(bookId: bookId).isEmpty, "処理前はまだsnapshotが無いこと")

        await RemoteChangeObserver.shared.processNewHistory()
        // SnapshotRebuildQueueは自身のactor上で非同期に処理するため、完了をポーリングで待つ。
        try await waitUntil(timeout: 5) {
            !MonthlySnapshotSync.fetchAll(bookId: bookId).isEmpty
        }

        let monthly = MonthlySnapshotSync.fetchAll(bookId: bookId)
        XCTAssertFalse(monthly.isEmpty, "リモート由来の変更でMonthlySnapshotが再計算されること")
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 1000)
    }

    // MARK: - 2. このデバイス自身（author == "app"）の変更 → 再計算をトリガーしない

    func testAppAuthoredChangeDoesNotTriggerAdditionalRebuild() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let bookId = UUID()
        try writeExpense(to: stack, bookId: bookId, author: CoreDataStack.transactionAuthor)

        let shouldRebuild = await processAndReportWhetherRebuildWasRequested()
        XCTAssertFalse(shouldRebuild, "このデバイス自身の書き込みはSnapshotUpdateService側で既に処理済みのため、二重に再計算をトリガーしないこと")
    }

    // MARK: - 3. Local storeだけの変更 → author不問で再計算をトリガーしない

    func testLocalStoreOnlyChangeDoesNotTriggerRebuild() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        try writeLocalOnlySnapshot(to: stack, bookId: UUID(), author: "otherDevice")

        let shouldRebuild = await processAndReportWhetherRebuildWasRequested()
        XCTAssertFalse(shouldRebuild, "Local storeの変更はCloudKit起因のリモート変更ではありえないため対象外であること")
    }

    // MARK: - 4. 同じtransactionを2回処理しない（tokenが前進する）

    func testProcessingTwiceDoesNotReprocessSameTransaction() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let bookId = UUID()
        try writeExpense(to: stack, bookId: bookId, author: "otherDevice")

        let first = await processAndReportWhetherRebuildWasRequested()
        XCTAssertTrue(first, "1回目はリモート変更を検出して再計算をトリガーすること")

        let second = await processAndReportWhetherRebuildWasRequested()
        XCTAssertFalse(second, "2回目は同じtransactionを再処理せず、再計算をトリガーしないこと")
    }

    // MARK: - 5. リモート由来のReceiptPhotoDataが、ローカルのDocuments/receiptsへ書き出される

    private func writeReceiptPhoto(
        to stack: CoreDataStack, id: String, transactionId: UUID, bookId: UUID, imageData: Data, author: String
    ) throws {
        let context = stack.container.newBackgroundContext()
        context.transactionAuthor = author
        try context.performAndWait {
            let photo = CDReceiptPhotoData(context: context)
            photo.id = id
            photo.transactionType = "expense"
            photo.transactionId = transactionId
            photo.bookId = bookId
            photo.sortOrder = 0
            photo.imageData = imageData
            photo.createdAt = Date()
            try context.save()
        }
    }

    func testRemotePhotoIsMaterializedToLocalDocumentsDirectory() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let filename = "\(UUID().uuidString).jpg"
        defer { ReceiptImageHelper.delete(filename) }
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])

        try writeReceiptPhoto(
            to: stack, id: filename, transactionId: UUID(), bookId: UUID(),
            imageData: imageBytes, author: "otherDevice"
        )

        XCTAssertNil(ReceiptImageHelper.loadData(filename), "処理前はまだローカルファイルが無いこと")

        await RemoteChangeObserver.shared.processNewHistory()

        XCTAssertEqual(
            ReceiptImageHelper.loadData(filename), imageBytes,
            "リモート由来のReceiptPhotoDataがローカルファイルとして元のバイト列のまま書き出されること（再圧縮されないこと）"
        )
    }

    // MARK: - 6. ローカルに既に同名ファイルがある場合は上書きしない

    func testExistingLocalPhotoFileIsNeverOverwrittenByRemoteData() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let filename = "\(UUID().uuidString).jpg"
        defer { ReceiptImageHelper.delete(filename) }
        let originalLocalBytes = Data([0x01, 0x02, 0x03])
        ReceiptImageHelper.writeIfMissing(originalLocalBytes, filename: filename)

        try writeReceiptPhoto(
            to: stack, id: filename, transactionId: UUID(), bookId: UUID(),
            imageData: Data([0xFF, 0xFF, 0xFF]), author: "otherDevice"
        )

        await RemoteChangeObserver.shared.processNewHistory()

        XCTAssertEqual(
            ReceiptImageHelper.loadData(filename), originalLocalBytes,
            "既存のローカル写真ファイルは絶対に上書きしないこと"
        )
    }

    // MARK: - Helpers

    /// processNewHistory()はrequestRebuildを呼ぶかどうかを外部から直接観測できないため、
    /// SnapshotRebuildQueue.shared.requestRebuild()の呼び出し有無を、同等のロジックを持つ
    /// RemoteChangeObserverの内部メソッドを直接呼んで確認する。
    private func processAndReportWhetherRebuildWasRequested() async -> Bool {
        let context = CoreDataStack.shared.container.newBackgroundContext()
        return await context.perform {
            RemoteChangeObserver.processHistorySynchronously(context: context).shouldRebuildSnapshots
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition did not become true within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
