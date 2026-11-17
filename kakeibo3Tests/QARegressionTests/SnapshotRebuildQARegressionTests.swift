// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
import CoreData
@testable import kakeibo3

// MARK: - SnapshotManager/AnalysisSnapshotManager.rebuildAll()の書き直しに対する回帰テスト
//
// 対象: 帳簿単位のトランザクション分離・決定性・他帳簿非影響・save失敗時のロールバック・
// AssetGraphCacheとの扱いの統一・AccountingMonthCalculatorのSnapshot非依存。

final class SnapshotRebuildQARegressionTests: QARegressionTestCase {

    // MARK: - save失敗を確実に起こすヘルパー
    //
    // 以下は試したが不採用:
    // - POSIXパーミッション(chmod)・chflags(immutable): シミュレータのサンドボックス内では
    //   所有プロセスの書き込みまでは防げなかった。
    // - persistentStoreCoordinatorからのストア切り離し: 「ストア無し状態でのsave」は
    //   Core Data側がキャッチ不能なNSException(プログラマーエラー扱い)として送出するため、
    //   Swiftのdo/catchでは捕まえられずプロセスごと落ちる。
    // - ストアファイルの一時退避(rename): ファイルが無い状態でのfetchはCore Data内部で
    //   静かに空扱いになることがあり、save自体まで到達しないままエラーなく完了してしまう
    //   ケースがあった。
    //
    // 最終的に採用したのは、ストアファイルの中身をその場で破壊する方法。ファイル自体は
    // 存在し続けるため「見つからない」系の扱いにはならず、SQLite側が
    // 「database disk image is malformed」として検知し、Core Dataがこれを
    // 回復可能なSwift Errorとして投げる。元のバイト列を保持しておき、
    // 検証後に書き戻すことで、退避前に確定していたデータは失わない。
    private func corruptStoreFile(storeURL: URL) throws -> Data {
        let original = try Data(contentsOf: storeURL)
        let garbage = Data(repeating: 0xFF, count: max(original.count, 4096))
        try garbage.write(to: storeURL)
        // -wal/-shmが残っていると、SQLiteが本体ではなくそちら側の内容を優先して
        // 読んでしまい、本体を壊した意味が無くなるため合わせて削除する。
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
        }
        return original
    }

    private func restoreStoreFile(_ original: Data, storeURL: URL) throws {
        try original.write(to: storeURL)
    }

    // MARK: - 同一ストアの開き直しヘルパー
    //
    // `CoreDataStack.shared = CoreDataStack(storeURL:)` で単純に再代入するだけだと、
    // 直前の`CoreDataStack`が保持していたNSPersistentStoreCoordinator/SQLite接続が
    // 「いつ実際にクローズされるか」の保証がない(ARCによる解放タイミングと、Core Data内部の
    // 非同期クローズ処理が競合しうる)。この状態のまま同じファイルへ新しい接続を開こうとすると、
    // 稀に「ファイルを開けませんでした(SQLite I/Oエラー)」で新しい接続の生成自体が失敗し、
    // (非throwingの)CoreDataStack.init(storeURL:)がfatalErrorしてテストプロセスごと落ちる。
    //
    // 再代入の前に明示的に`remove(_:)`でストアをコーディネータから切り離すことで、
    // クローズが同期的に完了してから次の接続を開けるようにする。
    private func reopenStore(storeURL: URL) throws {
        let oldCoordinator = CoreDataStack.shared.container.persistentStoreCoordinator
        for store in oldCoordinator.persistentStores {
            try oldCoordinator.remove(store)
        }
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)
    }

    // MARK: - 1. 単一帳簿rebuild成功

    func testSingleBookRebuildSucceeds() throws {
        let fixture = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        var expense = ExpenseData(amount: 500, date: Date(), paymentMethod: fixture.cash.methodName, category: fixture.expenseCategory.name, memo: "")
        expense.bookId = fixture.book.id
        ExpenseDataSync.insert(expense)

        try SnapshotManager.rebuildAll(bookId: fixture.book.id)

        let monthly = MonthlySnapshotSync.fetchAll(bookId: fixture.book.id)
        XCTAssertFalse(monthly.isEmpty)
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 500)
    }

    // MARK: - 2. 複数帳簿rebuild成功

    func testMultipleBookRebuildSucceeds() throws {
        let books = QARegressionTestFactory.makeThreeStandardBooks()
        for fixture in [books.main, books.business, books.travel] {
            var expense = ExpenseData(amount: 1000, date: Date(), paymentMethod: fixture.cash.methodName, category: fixture.expenseCategory.name, memo: "")
            expense.bookId = fixture.book.id
            ExpenseDataSync.insert(expense)
        }

        let result = SnapshotManager.rebuildAll()
        XCTAssertEqual(Set(result.succeededBookIds), Set([books.main.book.id, books.business.book.id, books.travel.book.id]))
        XCTAssertTrue(result.failedBooks.isEmpty)

        for fixture in [books.main, books.business, books.travel] {
            let monthly = MonthlySnapshotSync.fetchAll(bookId: fixture.book.id)
            XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 1000)
        }
    }

    // MARK: - 3. 帳簿B失敗時に帳簿Aの結果は維持される / 4. 失敗bookIdが結果に含まれる

    func testBookBFailureDoesNotAffectBookAResults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotRebuildQATests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("test.sqlite")
        try reopenStore(storeURL: storeURL)

        let bookA = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        let bookB = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿B"))
        var expenseA = ExpenseData(amount: 300, date: Date(), paymentMethod: bookA.cash.methodName, category: bookA.expenseCategory.name, memo: "")
        expenseA.bookId = bookA.book.id
        ExpenseDataSync.insert(expenseA)
        var expenseB = ExpenseData(amount: 700, date: Date(), paymentMethod: bookB.cash.methodName, category: bookB.expenseCategory.name, memo: "")
        expenseB.bookId = bookB.book.id
        ExpenseDataSync.insert(expenseB)

        // 帳簿Aはストアが生きている状態で先に成功させる
        try SnapshotManager.rebuildAll(bookId: bookA.book.id)
        XCTAssertFalse(MonthlySnapshotSync.fetchAll(bookId: bookA.book.id).isEmpty)

        // 一度開き直してWALをチェックポイントし、帳簿Aの分を本体ファイルへ確実に
        // 反映させてから、本体ファイルを破壊して帳簿Bを再構築 → save失敗で例外が投げられるはず
        try reopenStore(storeURL: storeURL)
        let original = try corruptStoreFile(storeURL: storeURL)
        XCTAssertThrowsError(try SnapshotManager.rebuildAll(bookId: bookB.book.id))

        // ファイルを元へ戻し、同じストアを開き直してから検証する。帳簿Aの分は
        // 破壊前に既にディスクへ確定済みのため、帳簿Bの失敗が帳簿Aのデータを
        // 失わせていないことを確認できる。
        try restoreStoreFile(original, storeURL: storeURL)
        try reopenStore(storeURL: storeURL)
        let bookAMonthly = MonthlySnapshotSync.fetchAll(bookId: bookA.book.id)
        XCTAssertFalse(bookAMonthly.isEmpty)
        XCTAssertEqual(bookAMonthly.reduce(0) { $0 + $1.expenseTotal }, 300)
    }

    func testFailedBookIdIsIncludedInResultWithoutStoppingOtherBooks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotRebuildQATests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("test.sqlite")
        try reopenStore(storeURL: storeURL)

        let bookA = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        let bookB = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿B"))
        for fixture in [bookA, bookB] {
            var expense = ExpenseData(amount: 100, date: Date(), paymentMethod: fixture.cash.methodName, category: fixture.expenseCategory.name, memo: "")
            expense.bookId = fixture.book.id
            ExpenseDataSync.insert(expense)
        }

        // ストア本体のファイルを破壊してから、SnapshotManager.rebuildAll()(全帳簿版)が
        // 内部で行っているのと同じ「帳簿ごとに独立してtry/catchする」処理をここで直接
        // 再現する(全帳簿版の内部実装は帳簿一覧の取得も同じストアに依存するため、
        // ファイルが壊れた状態では一覧取得自体ができず、この検証ができない)。
        // SnapshotRebuildResultは実装と同じ型を使う。
        try reopenStore(storeURL: storeURL)
        _ = try corruptStoreFile(storeURL: storeURL)

        var result = SnapshotRebuildResult()
        for bookId in [bookA.book.id, bookB.book.id] {
            do {
                try SnapshotManager.rebuildAll(bookId: bookId)
                result.recordSuccess(bookId: bookId)
            } catch {
                result.recordFailure(bookId: bookId, error: error)
            }
        }

        XCTAssertEqual(Set(result.failedBooks.map(\.bookId)), Set([bookA.book.id, bookB.book.id]), "1件目の失敗で処理が止まらず、2件目も失敗として記録されるべき")
        XCTAssertTrue(result.succeededBookIds.isEmpty)
    }

    // MARK: - 5. 他帳簿非影響

    func testRebuildingOneBookDoesNotTouchOtherBookSnapshots() throws {
        let bookA = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        let bookB = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿B"))
        for fixture in [bookA, bookB] {
            var expense = ExpenseData(amount: 200, date: Date(), paymentMethod: fixture.cash.methodName, category: fixture.expenseCategory.name, memo: "")
            expense.bookId = fixture.book.id
            ExpenseDataSync.insert(expense)
        }
        try SnapshotManager.rebuildAll(bookId: bookA.book.id)
        try SnapshotManager.rebuildAll(bookId: bookB.book.id)

        let bookBBefore = MonthlySnapshotSync.fetchAll(bookId: bookB.book.id)

        // 帳簿Aだけ再構築する(帳簿Bのデータは触らない)
        try SnapshotManager.rebuildAll(bookId: bookA.book.id)

        let bookBAfter = MonthlySnapshotSync.fetchAll(bookId: bookB.book.id)
        XCTAssertEqual(bookBBefore.count, bookBAfter.count)
        XCTAssertEqual(bookBBefore.reduce(0) { $0 + $1.expenseTotal }, bookBAfter.reduce(0) { $0 + $1.expenseTotal })
    }

    // MARK: - 6. save失敗時rollback

    func testSaveFailureLeavesNoPartialSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotRebuildQATests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("test.sqlite")
        try reopenStore(storeURL: storeURL)

        let book = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        var expense = ExpenseData(amount: 900, date: Date(), paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
        expense.bookId = book.book.id
        ExpenseDataSync.insert(expense)

        // 一度開き直してWALをチェックポイントし、挿入済みの取引データを本体ファイルへ
        // 確実に反映させてから、本体ファイルを破壊する。
        try reopenStore(storeURL: storeURL)
        let original = try corruptStoreFile(storeURL: storeURL)
        XCTAssertThrowsError(try SnapshotManager.rebuildAll(bookId: book.book.id))

        // ファイルを元へ戻し、同じストアを開き直してから検証する。
        try restoreStoreFile(original, storeURL: storeURL)
        try reopenStore(storeURL: storeURL)

        // save失敗時は削除も挿入も一切確定していないはず(元々0件だったので0件のまま)
        XCTAssertTrue(MonthlySnapshotSync.fetchAll(bookId: book.book.id).isEmpty)
        XCTAssertTrue(DailySnapshotSync.fetchAll(bookId: book.book.id).isEmpty)
    }

    // MARK: - 7. 2回rebuildして結果一致(決定性)

    func testRebuildTwiceProducesIdenticalResults() throws {
        let book = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        for (offset, amount) in [(0, 500), (1, 300), (35, 700)] {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()).addingTimeInterval(-40 * 86400))!
            var expense = ExpenseData(amount: amount, date: date, paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
            expense.bookId = book.book.id
            ExpenseDataSync.insert(expense)
        }

        try SnapshotManager.rebuildAll(bookId: book.book.id)
        let daily1 = DailySnapshotSync.fetchAll(bookId: book.book.id).sorted { $0.date < $1.date }
        let monthly1 = MonthlySnapshotSync.fetchAll(bookId: book.book.id).sorted { $0.yearMonth < $1.yearMonth }

        try SnapshotManager.rebuildAll(bookId: book.book.id)
        let daily2 = DailySnapshotSync.fetchAll(bookId: book.book.id).sorted { $0.date < $1.date }
        let monthly2 = MonthlySnapshotSync.fetchAll(bookId: book.book.id).sorted { $0.yearMonth < $1.yearMonth }

        XCTAssertEqual(daily1.count, daily2.count)
        for (a, b) in zip(daily1, daily2) {
            XCTAssertEqual(a.date, b.date)
            XCTAssertEqual(a.bookId, b.bookId)
            XCTAssertEqual(a.incomeTotal, b.incomeTotal)
            XCTAssertEqual(a.expenseTotal, b.expenseTotal)
            XCTAssertEqual(a.creditCardExpenseTotal, b.creditCardExpenseTotal)
            XCTAssertEqual(a.transferFeeTotal, b.transferFeeTotal)
            // updatedAtは再生成時刻のため決定性比較の対象外
        }

        XCTAssertEqual(monthly1.count, monthly2.count)
        for (a, b) in zip(monthly1, monthly2) {
            XCTAssertEqual(a.yearMonth, b.yearMonth)
            XCTAssertEqual(a.bookId, b.bookId)
            XCTAssertEqual(a.incomeTotal, b.incomeTotal)
            XCTAssertEqual(a.expenseTotal, b.expenseTotal)
            XCTAssertEqual(a.carryoverBalance, b.carryoverBalance)
            XCTAssertEqual(a.rawCarryoverBalance, b.rawCarryoverBalance)
        }
    }

    // MARK: - 8. ゴミ箱除外

    func testTrashedExpenseIsExcludedFromRebuild() throws {
        let book = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        var visible = ExpenseData(amount: 400, date: Date(), paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
        visible.bookId = book.book.id
        ExpenseDataSync.insert(visible)

        var trashed = ExpenseData(amount: 9999, date: Date(), paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
        trashed.bookId = book.book.id
        trashed.isInTrash = true
        trashed.trashedAt = Date()
        ExpenseDataSync.insert(trashed)

        try SnapshotManager.rebuildAll(bookId: book.book.id)

        let monthly = MonthlySnapshotSync.fetchAll(bookId: book.book.id)
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 400, "ゴミ箱の支出は集計に含まれてはいけない")
    }

    // MARK: - 9. 使用停止カテゴリーの過去データ集計維持

    func testSuspendedCategoryHistoricalExpenseStillCounted() throws {
        let book = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        var expense = ExpenseData(amount: 600, date: Date(), paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
        expense.bookId = book.book.id
        ExpenseDataSync.insert(expense)

        var suspendedCategory = book.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        try SnapshotManager.rebuildAll(bookId: book.book.id)

        let monthly = MonthlySnapshotSync.fetchAll(bookId: book.book.id)
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 600, "使用停止カテゴリーでも過去の取引は集計に含める")
    }

    // MARK: - 10. AssetGraphCache再生成

    func testAssetGraphCacheRebuildsSuccessfully() async throws {
        let book = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        var expense = ExpenseData(amount: 250, date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!, paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
        expense.bookId = book.book.id
        ExpenseDataSync.insert(expense)

        try await AssetGraphCacheService.rebuildTotalAssetsCache(bookId: book.book.id, maxPoints: 100)

        let cache = AssetGraphCacheService.fetchTotalAssetsCache(bookId: book.book.id)
        XCTAssertNotNil(cache)
        XCTAssertFalse(cache?.points.isEmpty ?? true)
    }

    // MARK: - 11. Snapshot/AnalysisSnapshot/AssetGraphCacheのbookId分離

    func testAllThreeDerivedDataTypesAreSeparatedPerBook() async throws {
        let bookA = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        let bookB = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿B"))
        for (fixture, amount) in [(bookA, 111), (bookB, 222)] {
            var expense = ExpenseData(amount: amount, date: Date(), paymentMethod: fixture.cash.methodName, category: fixture.expenseCategory.name, memo: "")
            expense.bookId = fixture.book.id
            ExpenseDataSync.insert(expense)
        }

        try SnapshotManager.rebuildAll(bookId: bookA.book.id)
        try SnapshotManager.rebuildAll(bookId: bookB.book.id)
        try AnalysisSnapshotManager.rebuildAll(bookId: bookA.book.id)
        try AnalysisSnapshotManager.rebuildAll(bookId: bookB.book.id)
        try await AssetGraphCacheService.rebuildTotalAssetsCache(bookId: bookA.book.id, maxPoints: 100)
        try await AssetGraphCacheService.rebuildTotalAssetsCache(bookId: bookB.book.id, maxPoints: 100)

        XCTAssertEqual(MonthlySnapshotSync.fetchAll(bookId: bookA.book.id).reduce(0) { $0 + $1.expenseTotal }, 111)
        XCTAssertEqual(MonthlySnapshotSync.fetchAll(bookId: bookB.book.id).reduce(0) { $0 + $1.expenseTotal }, 222)
        XCTAssertEqual(AnalysisMonthlySnapshotSync.fetchAll(bookId: bookA.book.id).reduce(0) { $0 + $1.expenseTotal }, 111)
        XCTAssertEqual(AnalysisMonthlySnapshotSync.fetchAll(bookId: bookB.book.id).reduce(0) { $0 + $1.expenseTotal }, 222)

        let cacheA = AssetGraphCacheService.fetchTotalAssetsCache(bookId: bookA.book.id)
        let cacheB = AssetGraphCacheService.fetchTotalAssetsCache(bookId: bookB.book.id)
        XCTAssertEqual(cacheA?.bookId, bookA.book.id)
        XCTAssertEqual(cacheB?.bookId, bookB.book.id)
    }

    // MARK: - 12. 実SQLite再起動後も結果維持

    func testResultsSurviveRealSQLiteRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotRebuildQATests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("test.sqlite")
        try reopenStore(storeURL: storeURL)

        let book = QARegressionTestFactory.seedStandardData(book: QARegressionTestFactory.makeBook(name: "帳簿A"))
        var expense = ExpenseData(amount: 1500, date: Date(), paymentMethod: book.cash.methodName, category: book.expenseCategory.name, memo: "")
        expense.bookId = book.book.id
        ExpenseDataSync.insert(expense)

        try SnapshotManager.rebuildAll(bookId: book.book.id)

        // 実SQLite再起動相当: 同じURLへ改めてCoreDataStackを作り直す
        try reopenStore(storeURL: storeURL)

        let monthly = MonthlySnapshotSync.fetchAll(bookId: book.book.id)
        XCTAssertFalse(monthly.isEmpty)
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 1500)
    }

    // MARK: - 13. AccountingMonthCalculatorがSnapshotに依存していないこと

    func testAccountingMonthCalculatorWorksWithoutAnySnapshotData() throws {
        // DailySnapshot/MonthlySnapshotは一切作らない(意図的にrebuildを呼ばない)。
        // それでもAccountingMonthCalculatorが正しく動作すれば、Snapshotへ依存していないと言える。
        XCTAssertEqual(MonthlySnapshotSync.fetchAll().count, 0)
        XCTAssertEqual(DailySnapshotSync.fetchAll().count, 0)

        let range = AccountingMonthCalculator.range(containing: Date())
        XCTAssertNotNil(range, "Snapshotデータが無くても会計月の範囲計算は成立するはず")

        let anchorRange = AccountingMonthCalculator.range(anchorYear: 2026, anchorMonth: 7)
        XCTAssertNotNil(anchorRange)
    }
}
