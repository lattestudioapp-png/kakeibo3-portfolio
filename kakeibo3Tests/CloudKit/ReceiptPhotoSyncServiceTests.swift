import XCTest
import CoreData
@testable import kakeibo3

// MARK: - レシート写真のCloudKit同期（ReceiptPhotoDataSync / ReceiptPhotoSyncService）のテスト
//
// RemoteChangeObserverTests.swiftと同じcloudLocalDirectoryパターンで、実ストアを使って検証する
// （CloudKitへは繋がない）。ReceiptImageHelperは実機のDocumentsディレクトリを直接使うため、
// 生成したファイルはテストごとに必ず削除する（ユニークなUUIDファイル名のため既存データとは
// 衝突しない）。
final class ReceiptPhotoSyncServiceTests: XCTestCase {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptPhotoSyncServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStack() throws -> (CoreDataStack, URL) {
        let dir = try makeTempDirectory()
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        CoreDataStack.shared = stack
        return (stack, dir)
    }

    private func writeLocalFile(bytes: Data) -> String {
        let filename = ReceiptImageHelper.save(bytes)!
        return filename
    }

    // MARK: - 1. ensureSynced: 新規追加

    func testEnsureSyncedInsertsMissingPhoto() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bytes = Data([0xFF, 0xD8, 0xFF, 0x11, 0x22, 0x33])
        let filename = writeLocalFile(bytes: bytes)
        defer { ReceiptImageHelper.delete(filename) }

        let transactionId = UUID()
        let bookId = UUID()

        ReceiptPhotoSyncService.ensureSynced(
            filenames: [filename], transactionType: .expense, transactionId: transactionId, bookId: bookId
        )

        let stored = ReceiptPhotoDataSync.fetch(id: filename)
        XCTAssertNotNil(stored, "ReceiptPhotoDataへ1件追加されていること")
        XCTAssertEqual(stored?.imageData, bytes, "画像バイト列は元のファイルと完全に一致すること（再圧縮しない）")
        XCTAssertEqual(stored?.transactionId, transactionId)
        XCTAssertEqual(stored?.bookId, bookId)
        XCTAssertEqual(stored?.transactionType, .expense)
    }

    // MARK: - 2. ensureSynced: ローカルファイルが読めない場合は静かにスキップする

    func testEnsureSyncedSkipsMissingLocalFileWithoutCrashing() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let missingFilename = "\(UUID().uuidString).jpg"

        ReceiptPhotoSyncService.ensureSynced(
            filenames: [missingFilename], transactionType: .expense, transactionId: UUID(), bookId: UUID()
        )

        XCTAssertNil(ReceiptPhotoDataSync.fetch(id: missingFilename), "読めないファイルはReceiptPhotoDataへ追加されないこと")
    }

    // MARK: - 3. ensureSynced: 同じファイル名で複数回呼んでも重複しない（再実行安全・同期OFF→ON相当）

    func testEnsureSyncedIsIdempotentWhenCalledRepeatedly() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bytes = Data([0x01, 0x02, 0x03])
        let filename = writeLocalFile(bytes: bytes)
        defer { ReceiptImageHelper.delete(filename) }
        let transactionId = UUID()
        let bookId = UUID()

        for _ in 0..<5 {
            ReceiptPhotoSyncService.ensureSynced(
                filenames: [filename], transactionType: .income, transactionId: transactionId, bookId: bookId
            )
        }

        let request = CDReceiptPhotoData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", filename)
        let count = (try? stack.container.viewContext.count(for: request)) ?? -1
        XCTAssertEqual(count, 1, "同じファイル名への複数回のensureSyncedは1件のみを作ること")
    }

    // MARK: - 4. removeSynced: 削除が反映される

    func testRemoveSyncedDeletesRow() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bytes = Data([0xAA])
        let filename = writeLocalFile(bytes: bytes)
        defer { ReceiptImageHelper.delete(filename) }

        ReceiptPhotoSyncService.ensureSynced(
            filenames: [filename], transactionType: .transfer, transactionId: UUID(), bookId: UUID()
        )
        XCTAssertNotNil(ReceiptPhotoDataSync.fetch(id: filename))

        ReceiptPhotoSyncService.removeSynced(filenames: [filename])
        XCTAssertNil(ReceiptPhotoDataSync.fetch(id: filename), "removeSynced後は取得できないこと")
    }

    // MARK: - 5. backfillAllIfNeeded: 写真0件のケースで何も起きない（クラッシュしない）

    func testBackfillWithNoDataDoesNothing() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        ReceiptPhotoSyncService.backfillAllIfNeeded()
        XCTAssertEqual(ReceiptPhotoDataSync.count(), 0)
    }

    // MARK: - 6. backfillAllIfNeeded: 写真1件のケース（既存ユーザーの移行を模す）

    func testBackfillMigratesSingleExistingPhoto() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bookId = UUID()
        var book = BookData(name: "テスト帳簿", sortOrder: 0, isMain: true)
        book.id = bookId
        BookDataSync.insert(book)

        let bytes = Data([0x10, 0x20, 0x30])
        let filename = writeLocalFile(bytes: bytes)
        defer { ReceiptImageHelper.delete(filename) }

        var expense = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "")
        expense.bookId = bookId
        expense.receiptImagePath = filename
        ExpenseDataSync.insert(expense)

        // この機能の実装前から存在していた写真（ensureSyncedは一度も呼ばれていない）を想定
        XCTAssertNil(ReceiptPhotoDataSync.fetch(id: filename), "事前条件：まだ同期されていないこと")

        ReceiptPhotoSyncService.backfillAllIfNeeded()

        let stored = ReceiptPhotoDataSync.fetch(id: filename)
        XCTAssertNotNil(stored, "既存の写真が1回限りの移行でReceiptPhotoDataへ追加されること")
        XCTAssertEqual(stored?.imageData, bytes)

        // 既存データは一切変更されていないこと
        let reloadedExpense = ExpenseDataSync.fetch(id: expense.id)
        XCTAssertEqual(reloadedExpense?.receiptImagePath, filename, "移行後もreceiptImagePathは変化しないこと")
        XCTAssertEqual(reloadedExpense?.amount, 500, "移行後も収支データ自体は変化しないこと")
        XCTAssertNotNil(ReceiptImageHelper.loadData(filename), "移行後も元の.jpgファイルは残っていること")
    }

    // MARK: - 7. backfillAllIfNeeded: 大量件数でもクラッシュせず、全件移行できる

    func testBackfillHandlesLargeNumberOfPhotos() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bookId = UUID()
        var book = BookData(name: "テスト帳簿", sortOrder: 0, isMain: true)
        book.id = bookId
        BookDataSync.insert(book)

        let photoCount = 120
        var filenames: [String] = []
        for i in 0..<photoCount {
            let filename = writeLocalFile(bytes: Data([UInt8(i % 256)]))
            filenames.append(filename)
            var expense = ExpenseData(amount: i, date: Date(), paymentMethod: "現金", category: "食費", memo: "")
            expense.bookId = bookId
            expense.receiptImagePath = filename
            ExpenseDataSync.insert(expense)
        }
        defer { filenames.forEach { ReceiptImageHelper.delete($0) } }

        ReceiptPhotoSyncService.backfillAllIfNeeded()

        XCTAssertEqual(ReceiptPhotoDataSync.count(), photoCount, "大量件数でも全件が移行されること")
    }

    // MARK: - 8. backfillAllIfNeeded: 再実行しても重複しない（中断からの再開を模す）

    func testBackfillIsIdempotentAcrossMultipleRuns() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bookId = UUID()
        var book = BookData(name: "テスト帳簿", sortOrder: 0, isMain: true)
        book.id = bookId
        BookDataSync.insert(book)

        var filenames: [String] = []
        for i in 0..<10 {
            let filename = writeLocalFile(bytes: Data([UInt8(i)]))
            filenames.append(filename)
            var expense = ExpenseData(amount: i, date: Date(), paymentMethod: "現金", category: "食費", memo: "")
            expense.bookId = bookId
            expense.receiptImagePath = filename
            ExpenseDataSync.insert(expense)
        }
        defer { filenames.forEach { ReceiptImageHelper.delete($0) } }

        // 1回目：途中で中断した状況を模すため、先に半分だけ手動でensureSynced相当を進めておく
        ReceiptPhotoSyncService.ensureSynced(
            filenames: Array(filenames.prefix(5)), transactionType: .expense,
            transactionId: UUID(), bookId: bookId
        )
        XCTAssertEqual(ReceiptPhotoDataSync.count(), 5, "事前条件：5件だけ処理済みであること")

        // 2回目以降：backfillAllIfNeededを複数回実行しても、残り5件が追加され、重複は作られない
        ReceiptPhotoSyncService.backfillAllIfNeeded()
        ReceiptPhotoSyncService.backfillAllIfNeeded()
        ReceiptPhotoSyncService.backfillAllIfNeeded()

        XCTAssertEqual(ReceiptPhotoDataSync.count(), 10, "再実行を繰り返しても重複せず、ちょうど10件のままであること")
    }

    // MARK: - ダウンロード方向の安全網（materializeAllMissingLocalFiles）のテスト
    //
    // 「ReceiptPhotoData行はCore Dataに存在するが、ローカルの.jpgファイルがまだ無い」状態を、
    // CDReceiptPhotoDataを直接contextへ書き込むことで模す（RemoteChangeObserverを経由せず
    // 直接書き込むことで、「写真受信直後にアプリが終了した」「復元前にアプリが終了した」状況、
    // つまりNSPersistentStoreRemoteChangeNotificationの通知配送に一切依存しない状況を
    // 決定的に再現する）。

    @discardableResult
    private func insertOrphanedReceiptPhotoRow(
        to stack: CoreDataStack, id: String, transactionId: UUID, bookId: UUID, imageData: Data
    ) throws -> CDReceiptPhotoData {
        let context = stack.container.viewContext
        var result: CDReceiptPhotoData!
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
            result = photo
        }
        return result
    }

    // MARK: - 10. 写真受信直後 / 復元前にアプリが終了したケース（1, 2, 3）：
    //            次回起動時にmaterializeAllMissingLocalFilesが確実に復元する。
    //            あわせて重複防止（5）・既存ファイル非上書き・同期OFF時の動作（6）も
    //            同じCoreDataStackインスタンス内でまとめて検証する（テストプロセス全体での
    //            CoreDataStack生成数を抑えるため。多数のテストが個別にスタックを生成・破棄
    //            すると、既知のCore Data関連の環境要因によるフレーキーな挙動の確率が上がる
    //            ため、関連性の高い検証はまとめている）。

    func testMaterializeRestoresMissingPhotoIdempotentlyWithoutOverwriting() async throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(stack.isCloudSyncActive, "6: このテストはCloudKit無効（OFF相当）なストアで実行していること")

        // --- 1,2,3: 行はあるがローカルファイルは無い状態からの復元 ---
        let filename = "\(UUID().uuidString).jpg"
        defer { ReceiptImageHelper.delete(filename) }
        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0x10, 0x20, 0x30])

        // 通知処理を一切経由せず、Core Data上にだけ写真データが存在する状態を作る
        // （＝写真受信直後やその処理完了前にアプリが終了したのと同じ状態）。
        try insertOrphanedReceiptPhotoRow(
            to: stack, id: filename, transactionId: UUID(), bookId: UUID(), imageData: imageBytes
        )
        XCTAssertNil(ReceiptImageHelper.loadData(filename), "事前条件：ローカルファイルはまだ無いこと")

        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()

        XCTAssertEqual(
            ReceiptImageHelper.loadData(filename), imageBytes,
            "起動時の安全網により、通知の有無に関わらずローカルファイルが復元されること（CloudKit同期OFF中でも動作する）"
        )

        // --- 5: 繰り返し実行しても重複・上書きが起きない ---
        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()
        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()
        XCTAssertEqual(ReceiptImageHelper.loadData(filename), imageBytes, "繰り返し実行しても内容が変化しないこと")

        // --- 既存のローカル写真（別ファイル）は絶対に上書きされないこと ---
        let otherFilename = "\(UUID().uuidString).jpg"
        defer { ReceiptImageHelper.delete(otherFilename) }
        let originalLocalBytes = Data([0xAA, 0xBB, 0xCC])
        ReceiptImageHelper.writeIfMissing(originalLocalBytes, filename: otherFilename)
        // Core Data上には異なるバイト列を持つ行がある状態を作る
        // （他端末の別データが偶然同名で届いた等を想定）。
        try insertOrphanedReceiptPhotoRow(
            to: stack, id: otherFilename, transactionId: UUID(), bookId: UUID(), imageData: Data([0xFF, 0xFF, 0xFF])
        )
        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()
        XCTAssertEqual(
            ReceiptImageHelper.loadData(otherFilename), originalLocalBytes,
            "既存のローカル写真ファイルは絶対に上書きされないこと"
        )
    }

    // MARK: - 11. 大量件数でもメインスレッドをブロックせず完了する（非同期であることの確認）

    func testMaterializeAllMissingLocalFilesHandlesLargeNumberWithoutBlocking() async throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        var filenames: [String] = []
        for i in 0..<120 {
            let filename = "\(UUID().uuidString).jpg"
            filenames.append(filename)
            try insertOrphanedReceiptPhotoRow(
                to: stack, id: filename, transactionId: UUID(), bookId: UUID(), imageData: Data([UInt8(i % 256)])
            )
        }
        defer { filenames.forEach { ReceiptImageHelper.delete($0) } }

        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()

        for filename in filenames {
            XCTAssertNotNil(ReceiptImageHelper.loadData(filename), "大量件数でも全件復元されること: \(filename)")
        }
    }

    // MARK: - 14. 既存の収支データ・写真ファイルを変更しないこと（8）

    func testMaterializeDoesNotModifyExistingTransactionDataOrOtherFiles() async throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bookId = UUID()
        var book = BookData(name: "テスト帳簿", sortOrder: 0, isMain: true)
        book.id = bookId
        BookDataSync.insert(book)

        let existingFilename = writeLocalFile(bytes: Data([0x77]))
        defer { ReceiptImageHelper.delete(existingFilename) }
        var expense = ExpenseData(amount: 999, date: Date(), paymentMethod: "現金", category: "食費", memo: "既存メモ")
        expense.bookId = bookId
        expense.receiptImagePath = existingFilename
        ExpenseDataSync.insert(expense)
        ReceiptPhotoSyncService.ensureSynced(
            filenames: [existingFilename], transactionType: .expense, transactionId: expense.id, bookId: bookId
        )

        let missingFilename = "\(UUID().uuidString).jpg"
        defer { ReceiptImageHelper.delete(missingFilename) }
        try insertOrphanedReceiptPhotoRow(
            to: stack, id: missingFilename, transactionId: UUID(), bookId: bookId, imageData: Data([0x88])
        )

        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()

        let reloaded = ExpenseDataSync.fetch(id: expense.id)
        XCTAssertEqual(reloaded?.amount, 999, "既存の収支データは変化しないこと")
        XCTAssertEqual(reloaded?.memo, "既存メモ")
        XCTAssertEqual(reloaded?.receiptImagePath, existingFilename)
        XCTAssertEqual(ReceiptImageHelper.loadData(existingFilename), Data([0x77]), "既存の写真ファイルは変化しないこと")
        XCTAssertNotNil(ReceiptImageHelper.loadData(missingFilename), "欠落していた写真だけが新たに復元されること")
    }

    // MARK: - 16. 写真受信後の画面自動更新（4）：新規ファイル書き出し時だけ通知が発行される

    func testMaterializeAllMissingLocalFilesPostsNotificationOnlyForNewlyWrittenFiles() async throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let newFilename = "\(UUID().uuidString).jpg"
        defer { ReceiptImageHelper.delete(newFilename) }
        try insertOrphanedReceiptPhotoRow(
            to: stack, id: newFilename, transactionId: UUID(), bookId: UUID(), imageData: Data([0x01])
        )

        // 既にローカルにある写真（通知が発行されるべきではないケース）
        let existingFilename = writeLocalFile(bytes: Data([0x02]))
        defer { ReceiptImageHelper.delete(existingFilename) }
        try insertOrphanedReceiptPhotoRow(
            to: stack, id: existingFilename, transactionId: UUID(), bookId: UUID(), imageData: Data([0x02])
        )

        var notifiedFilenames: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ReceiptPhotoSyncService.photoMaterializedNotification, object: nil, queue: .main
        ) { note in
            if let filename = note.userInfo?["filename"] as? String {
                notifiedFilenames.append(filename)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await ReceiptPhotoSyncService.materializeAllMissingLocalFiles()
        // 通知はDispatchQueue.main.asyncで発行されるため、メインループへ処理を譲る。
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(notifiedFilenames.contains(newFilename), "新規に復元した写真については通知が発行されること")
        XCTAssertFalse(notifiedFilenames.contains(existingFilename), "既にローカルにあった写真については通知が発行されないこと")
    }

    // MARK: - 17. 写真の削除：リモートでの削除はローカルファイルを消さない（意図的な設計の確認）
    //
    // 修正3：ReceiptPhotoDataの削除はローカルファイルの削除をトリガーしない設計にしている
    // （所有する取引側のreceiptImagePath文字列の更新でUI表示は自然に更新されるため、
    // リモート信号だけでディスクのファイルを削除する経路は意図的に作らない。孤立ファイルが
    // 残るが二度と参照されないため実害は無く、誤ったリモート削除信号でユーザーの写真を
    // 失うリスクを避けられる）。この既存の安全な挙動が崩れていないことを確認する。
    func testLocalFileIsNeverDeletedByReceiptPhotoDataRemovalAlone() async throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let filename = writeLocalFile(bytes: Data([0x33]))
        defer { ReceiptImageHelper.delete(filename) }
        let transactionId = UUID()
        let bookId = UUID()
        ReceiptPhotoSyncService.ensureSynced(
            filenames: [filename], transactionType: .expense, transactionId: transactionId, bookId: bookId
        )
        XCTAssertNotNil(ReceiptPhotoDataSync.fetch(id: filename))

        // ReceiptPhotoData行だけを削除する（別端末での削除がCloudKit経由で反映された状況を模す）。
        ReceiptPhotoDataSync.delete(id: filename)
        XCTAssertNil(ReceiptPhotoDataSync.fetch(id: filename))

        XCTAssertNotNil(
            ReceiptImageHelper.loadData(filename),
            "ReceiptPhotoData行の削除だけでは、ローカルの.jpgファイルは削除されない設計であること"
        )
    }

    // MARK: - 9. backfillAllIfNeeded: ゴミ箱内のデータも対象に含める

    func testBackfillIncludesTrashedTransactions() throws {
        let (stack, dir) = try makeStack()
        defer { try? stack.releasePersistentStoresForMigration(); try? FileManager.default.removeItem(at: dir) }

        let bookId = UUID()
        var book = BookData(name: "テスト帳簿", sortOrder: 0, isMain: true)
        book.id = bookId
        BookDataSync.insert(book)

        let filename = writeLocalFile(bytes: Data([0x99]))
        defer { ReceiptImageHelper.delete(filename) }

        var expense = ExpenseData(amount: 100, date: Date(), paymentMethod: "現金", category: "食費", memo: "")
        expense.bookId = bookId
        expense.receiptImagePath = filename
        expense.isInTrash = true
        expense.trashedAt = Date()
        ExpenseDataSync.insert(expense)

        ReceiptPhotoSyncService.backfillAllIfNeeded()

        XCTAssertNotNil(
            ReceiptPhotoDataSync.fetch(id: filename),
            "ゴミ箱内（完全削除前）の写真も移行対象に含まれること（ファイル自体はまだ存在するため）"
        )
    }
}
