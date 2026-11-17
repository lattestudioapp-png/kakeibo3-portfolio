import XCTest
import CoreData
@testable import kakeibo3

// MARK: - persistent history削除停止の回帰テスト
//
// 実機調査で判明した不具合：RemoteChangeObserver.processHistorySynchronously()が
// 処理済みのpersistent historyを都度`deleteHistory(before:)`でpurgeしていたことが、
// 直後の`NSCocoaErrorDomain Code=134301`（persistent historyトークン無効化）→
// `NSCloudKitMirroringDelegate.reset`（CloudKit同期側がCloud構成のローカルミラー全体を
// 削除して再インポートする内部処理）を誘発し、BookData・CategoryData・ExpenseData等が
// 丸ごと消える不具合につながっていた（診断ログの直接観測で確認済み）。
//
// 修正：deleteHistory呼び出しを完全に削除し、履歴は一切削除しない設計にした
// （CloudKitミラーリング機構が内部的にどこまで処理済みかはアプリ側から正確に把握できないため、
// 「CloudKit処理済みの範囲だけ削除する」という推測に基づく実装はしない）。
//
// RemoteChangeObserverTests.swiftと同じパターン（enableCloudKit: false,
// enableHistoryTracking: true の実ストア・実persistent historyを使い、CloudKitへは繋がない）。
final class RemoteChangeObserverHistoryPreservationRegressionTests: XCTestCase {

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
            .appendingPathComponent("RemoteChangeObserverHistoryPreservationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func writeBook(to stack: CoreDataStack, bookId: UUID, author: String) throws -> UUID {
        let context = stack.container.newBackgroundContext()
        context.transactionAuthor = author
        try context.performAndWait {
            let book = CDBookData(context: context)
            book.id = bookId
            book.name = "RemoteChangeObserverHistoryPreservationTests"
            book.isMain = true
            book.createdAt = Date()
            try context.save()
        }
        return bookId
    }

    @discardableResult
    private func writeCategory(to stack: CoreDataStack, bookId: UUID, name: String, author: String) throws -> UUID {
        let context = stack.container.newBackgroundContext()
        context.transactionAuthor = author
        let categoryId = UUID()
        try context.performAndWait {
            let category = CDCategoryData(context: context)
            category.id = categoryId
            category.name = name
            category.colorHex = "#CFCFCF"
            category.type = "支出"
            category.sortOrder = 0
            category.bookId = bookId
            category.createdAt = Date()
            try context.save()
        }
        return categoryId
    }

    @discardableResult
    private func writeExpense(to stack: CoreDataStack, bookId: UUID, author: String) throws -> UUID {
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

    private func processOnce(context: NSManagedObjectContext) async -> RemoteChangeObserver.HistoryProcessingResult {
        await context.perform {
            RemoteChangeObserver.processHistorySynchronously(context: context)
        }
    }

    /// token=nil(最初から)で履歴を取得した件数を返す。deleteHistoryが実行されていれば
    /// 処理済み分はここに出てこなくなる。
    private func rawHistoryCountFromBeginning(context: NSManagedObjectContext) -> Int {
        context.performAndWait {
            let fetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            guard let result = try? context.execute(fetchRequest) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction]
            else { return 0 }
            return transactions.count
        }
    }

    // MARK: - 1. 処理後もpersistent historyが削除されないこと

    func testProcessingHistoryDoesNotDeleteItFromTheStore() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let bookId = UUID()
        try writeBook(to: stack, bookId: bookId, author: "otherDevice")
        try writeExpense(to: stack, bookId: bookId, author: "otherDevice")

        let context = stack.container.newBackgroundContext()
        let beforeCount = rawHistoryCountFromBeginning(context: context)
        XCTAssertGreaterThan(beforeCount, 0, "事前条件：履歴が記録されていること")

        _ = await processOnce(context: context)

        let afterCount = rawHistoryCountFromBeginning(context: context)
        XCTAssertEqual(
            afterCount, beforeCount,
            "処理後も、token=nilから再取得した履歴件数が減っていないこと（deleteHistoryを呼んでいないこと）"
        )
    }

    // MARK: - 2. 同じ履歴を何度処理しても安全（3回目以降も再計算が暴発しない・クラッシュしない）

    func testProcessingSameHistoryManyTimesInARowIsSafe() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let bookId = UUID()
        try writeExpense(to: stack, bookId: bookId, author: "otherDevice")

        let context = stack.container.newBackgroundContext()

        let first = await processOnce(context: context)
        XCTAssertTrue(first.shouldRebuildSnapshots, "1回目はリモート変更を検出すること")

        for iteration in 2...10 {
            let result = await processOnce(context: context)
            XCTAssertFalse(
                result.shouldRebuildSnapshots,
                "\(iteration)回目は同じtransactionを再処理せず、再計算をトリガーしないこと"
            )
        }
    }

    // MARK: - 3. 繰り返しのremote change通知処理でも、BookData/CategoryData/ExpenseDataが消えないこと

    func testRepeatedHistoryProcessingNeverDeletesBookCategoryOrExpenseData() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        let bookId = try writeBook(to: stack, bookId: UUID(), author: "otherDevice")
        try writeCategory(to: stack, bookId: bookId, name: "食費", author: "otherDevice")
        try writeExpense(to: stack, bookId: bookId, author: "otherDevice")

        let context = stack.container.newBackgroundContext()

        for _ in 0..<10 {
            _ = await processOnce(context: context)

            XCTAssertEqual(BookDataSync.fetchAll().count, 1, "帳簿が繰り返しの履歴処理で消えないこと")
            XCTAssertEqual(CategoryDataSync.fetchAll(bookId: bookId).count, 1, "カテゴリーが繰り返しの履歴処理で消えないこと")
            XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 1, "支出が繰り返しの履歴処理で消えないこと")
        }
    }

    // MARK: - 4. context再生成（アプリ再起動相当）後もデータが残っていること

    func testDataSurvivesContextRecreationAfterHistoryProcessing() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        CoreDataStack.shared = stack

        let bookId = try writeBook(to: stack, bookId: UUID(), author: "otherDevice")
        try writeCategory(to: stack, bookId: bookId, name: "食費", author: "otherDevice")
        try writeExpense(to: stack, bookId: bookId, author: "otherDevice")

        let context = stack.container.newBackgroundContext()
        _ = await processOnce(context: context)

        // アプリ再起動相当：NSPersistentContainer（CoreDataStack）を破棄し、同じURLから再生成する。
        try stack.releasePersistentStoresForMigration()
        stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: true)
        CoreDataStack.shared = stack
        defer { try? stack.releasePersistentStoresForMigration() }

        XCTAssertEqual(BookDataSync.fetchAll().count, 1, "再起動相当後も帳簿が残っていること")
        XCTAssertEqual(CategoryDataSync.fetchAll(bookId: bookId).count, 1, "再起動相当後もカテゴリーが残っていること")
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 1, "再起動相当後も支出が残っていること")
    }

    // MARK: - 5. 既知の残課題のクローズ確認（establishedMainBookIdによる恒久対策）
    //
    // 以前のBookMigrationServiceは「CloudKit初回importが完了済みか」だけを見ており、
    // 「CloudKit同期側が現在resetの最中かどうか」は判定材料に含めていなかった。そのため、
    // 何らかの理由でローカルのBookDataが一時的に0件になった場合（reset直後の再インポート待ち等）、
    // initialImportStateが既に.completedであれば新しいメイン帳簿を作ってしまっていた
    // （実機調査で確認された重複メイン帳簿量産バグの直接の引き金）。
    //
    // 今回の修正（deleteHistory停止）はresetの発生自体を防ぐための修正だが、万が一別の理由で
    // resetが発生した場合にも備え、BookMigrationService側にも恒久的な安全弁を追加した：
    // 一度でもメイン帳簿を確立済みのデバイスでは(establishedMainBookIdKeyに記録済み)、
    // 「existingBooksが0件」を二度と新規作成の根拠にしない(迷ったら作らず待つ)。
    // このテストは、その安全弁が実際に効いていることを確認する（以前はXCTAssertEqualの期待値が
    // .createNewだった＝バグを許容する内容だったが、今は.waitAndRetryになっている＝バグが閉じた）。
    func testEstablishedMainBookIdClosesTheKnownGap_LocalStoreMomentarilyEmptyAfterInitialImportCompleted() {
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: [],
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .completed,
            establishedMainBookId: UUID()
        )
        XCTAssertEqual(
            decision, .waitAndRetry,
            "一度でもメイン帳簿を確立済みなら、初回import完了後にローカルが一時的に空になっても" +
            "(resetの再インポート待ち等)、新しいメイン帳簿を作らず待つこと。"
        )
    }
}
