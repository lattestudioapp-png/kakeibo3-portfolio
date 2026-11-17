// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class TrashQARegressionTests: QARegressionTestCase {

    private let repository: TransactionRepository = SwiftDataTransactionRepository()
    private var createdPhotoFilenames: [String] = []

    override func tearDownWithError() throws {
        ReceiptImageHelper.deleteAll(createdPhotoFilenames)
        createdPhotoFilenames = []
        try super.tearDownWithError()
    }

    // MARK: - ヘルパー

    private func makeBook(name: String = "メイン帳簿", isMain: Bool = true) -> BookData {
        let book = BookData(name: name, sortOrder: 0, isMain: isMain)
        BookDataSync.insert(book)
        return book
    }

    // ReceiptImageHelper.load(_:)は実際にJPEG/PNGとしてデコードを試みるため、テスト用の
    // ダミーバイト列では「ファイルが存在するのにデコード失敗でnil」になり判定を誤る。
    // ここではファイルの存在そのものをFileManagerで直接確認する。
    private func photoFileExists(_ filename: String) -> Bool {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("receipts")
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 1. 通常削除でゴミ箱へ移動する

    func testTrashTransactionMovesToTrashInsteadOfHardDelete() throws {
        let book = makeBook()
        var expense = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "テスト")
        expense.bookId = book.id
        ExpenseDataSync.insert(expense)

        let item = TransactionListItem.expense(from: expense)
        let ok = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )
        XCTAssertTrue(ok)

        let trashed = ExpenseDataSync.fetchTrashed(bookId: book.id)
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(trashed.first?.isInTrash, true)
        XCTAssertNotNil(trashed.first?.trashedAt)
    }

    // MARK: - 2. ゴミ箱データが通常一覧に出ない

    func testTrashedItemIsExcludedFromNormalFetch() throws {
        let book = makeBook()
        var expense = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "テスト")
        expense.bookId = book.id
        ExpenseDataSync.insert(expense)
        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )

        XCTAssertTrue(ExpenseDataSync.fetchAll(bookId: book.id).isEmpty, "ゴミ箱内データは帳簿単位の一覧に出てはいけない")
        XCTAssertTrue(ExpenseDataSync.fetchAll().isEmpty, "ゴミ箱内データは全件一覧にも出てはいけない")
    }

    // MARK: - 3. ゴミ箱データが集計に含まれない

    func testTrashedItemIsExcludedFromSnapshotAggregation() throws {
        let book = makeBook()
        var expense1 = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "残る")
        expense1.bookId = book.id
        ExpenseDataSync.insert(expense1)
        var expense2 = ExpenseData(amount: 300, date: Date(), paymentMethod: "現金", category: "食費", memo: "ゴミ箱行き")
        expense2.bookId = book.id
        ExpenseDataSync.insert(expense2)

        let item2 = TransactionListItem.expense(from: expense2)
        _ = try repository.trashTransaction(
            originalItem: item2, incomeDataList: [], expenseDataList: [expense1, expense2], transferDataList: []
        )

        SnapshotManager.rebuildAll()
        let dailyTotal = DailySnapshotSync.fetchAll(bookId: book.id).reduce(0) { $0 + $1.expenseTotal }
        XCTAssertEqual(dailyTotal, 500, "ゴミ箱内の300円は日次集計に含まれてはいけない")
    }

    // MARK: - 4・5. 復元できる・復元後に元の属性が維持される

    func testRestoreTransactionBringsBackOriginalAttributes() throws {
        let book = makeBook()
        let originalDate = Date()
        var expense = ExpenseData(amount: 777, date: originalDate, paymentMethod: "現金", category: "食費", memo: "元のメモ")
        expense.bookId = book.id
        expense.receiptImagePath = "keep_this_photo.jpg"
        ExpenseDataSync.insert(expense)

        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )

        let trashedList = ExpenseDataSync.fetchTrashed(bookId: book.id)
        let restoredOk = try repository.restoreTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: trashedList, transferDataList: []
        )
        XCTAssertTrue(restoredOk)

        let restored = ExpenseDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(restored?.amount, 777)
        XCTAssertEqual(restored?.memo, "元のメモ")
        XCTAssertEqual(restored?.category, "食費")
        XCTAssertEqual(restored?.paymentMethod, "現金")
        XCTAssertEqual(restored?.bookId, book.id)
        XCTAssertEqual(restored?.receiptImagePath, "keep_this_photo.jpg")
        XCTAssertEqual(restored?.isInTrash, false)
        XCTAssertNil(restored?.trashedAt)
    }

    // MARK: - 6. 完全削除後に再表示されない

    func testPermanentlyDeletedItemNeverReappears() throws {
        let book = makeBook()
        var expense = ExpenseData(amount: 100, date: Date(), paymentMethod: "現金", category: "食費", memo: "消す")
        expense.bookId = book.id
        ExpenseDataSync.insert(expense)
        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )

        let trashedList = ExpenseDataSync.fetchTrashed(bookId: book.id)
        let deleted = try repository.permanentlyDeleteTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: trashedList, transferDataList: []
        )
        XCTAssertTrue(deleted)
        XCTAssertTrue(ExpenseDataSync.fetchTrashed(bookId: book.id).isEmpty)
        XCTAssertTrue(ExpenseDataSync.fetchAll(bookId: book.id).isEmpty)
        XCTAssertNil(ExpenseDataSync.fetch(id: expense.id))
    }

    // MARK: - 7. ゴミ箱を空にしても他帳簿は変化しない

    func testEmptyTrashDoesNotAffectOtherBooks() throws {
        let bookA = makeBook(name: "帳簿A", isMain: true)
        let bookB = makeBook(name: "帳簿B", isMain: false)

        var expenseA = ExpenseData(amount: 100, date: Date(), paymentMethod: "現金", category: "食費", memo: "A")
        expenseA.bookId = bookA.id
        ExpenseDataSync.insert(expenseA)
        var expenseB = ExpenseData(amount: 200, date: Date(), paymentMethod: "現金", category: "食費", memo: "B")
        expenseB.bookId = bookB.id
        ExpenseDataSync.insert(expenseB)

        _ = try repository.trashTransaction(
            originalItem: TransactionListItem.expense(from: expenseA),
            incomeDataList: [], expenseDataList: [expenseA], transferDataList: []
        )
        _ = try repository.trashTransaction(
            originalItem: TransactionListItem.expense(from: expenseB),
            incomeDataList: [], expenseDataList: [expenseB], transferDataList: []
        )

        let trashedA = ExpenseDataSync.fetchTrashed(bookId: bookA.id)
        _ = try repository.emptyTrash(bookId: bookA.id, incomeDataList: [], expenseDataList: trashedA, transferDataList: [])

        XCTAssertTrue(ExpenseDataSync.fetchTrashed(bookId: bookA.id).isEmpty)
        XCTAssertEqual(ExpenseDataSync.fetchTrashed(bookId: bookB.id).count, 1, "他帳簿(帳簿B)のゴミ箱データは変化してはいけない")
    }

    // MARK: - 8. アプリ再起動後もゴミ箱状態が維持される（実SQLiteストア）

    func testTrashStateSurvivesRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionTrashRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let book = makeBook()
        var expense = ExpenseData(amount: 900, date: Date(), paymentMethod: "現金", category: "食費", memo: "再起動確認")
        expense.bookId = book.id
        ExpenseDataSync.insert(expense)
        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )

        // CoreDataStack（＝NSPersistentContainer）を破棄し、同じストアURLから再生成する
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let trashedAfterRestart = ExpenseDataSync.fetchTrashed(bookId: book.id)
        XCTAssertEqual(trashedAfterRestart.count, 1)
        XCTAssertEqual(trashedAfterRestart.first?.isInTrash, true)
        XCTAssertNotNil(trashedAfterRestart.first?.trashedAt)
        XCTAssertTrue(ExpenseDataSync.fetchAll(bookId: book.id).isEmpty, "再起動後も通常一覧には出ない")
    }

    // MARK: - 9. バックアップ／復元でゴミ箱状態が維持される

    func testBackupRestorePreservesTrashState() async throws {
        let book = makeBook()
        var expense = ExpenseData(amount: 456, date: Date(), paymentMethod: "現金", category: "食費", memo: "バックアップ確認")
        expense.bookId = book.id
        ExpenseDataSync.insert(expense)
        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )

        var backup = BackupData(
            version: BackupData.currentVersion, createdAt: Date(),
            books: [BookBackupItem(id: book.id, name: book.name, createdAt: book.createdAt, sortOrder: 0, isArchived: false, isMain: true)],
            expenses: [], incomes: [], transfers: [], categories: [], paymentMethods: [], receiveMethods: [],
            bankAccounts: [], budgets: [], recurringBudgets: [], fixedExpenses: [], recurringIncomes: [], recurringTransfers: [],
            settings: BackupSettings(
                themeColorHex: nil, analysisSegmentOrder: nil, showPreviousMonthCarryover: true,
                creditCardAssetReflectionTiming: nil, accountingMonthStartDay: nil,
                accountingMonthWeekendHolidayAdjustment: nil, accountingMonthLabelBasis: nil, calendarWeekStartWeekday: nil
            )
        )
        backup.sourceBookId = book.id
        backup.expenses = [
            ExpenseBackupItem(
                id: expense.id, amount: 456, date: expense.date, paymentMethod: "現金", category: "食費",
                memo: "バックアップ確認", createdAt: expense.createdAt, bankAccountId: nil, fixedExpenseId: nil,
                receiptImagePath: nil, isTestData: false, bookId: book.id, isInTrash: true, trashedAt: Date()
            ),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionTrashBackup_\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await BackupManager().restore(from: url, targetBookId: book.id)

        let restoredTrashed = ExpenseDataSync.fetchTrashed(bookId: book.id)
        XCTAssertEqual(restoredTrashed.count, 1, "復元後もゴミ箱内データはゴミ箱のまま維持される必要がある")
        XCTAssertEqual(restoredTrashed.first?.amount, 456)
        XCTAssertTrue(ExpenseDataSync.fetchAll(bookId: book.id).isEmpty, "ゴミ箱内データが通常一覧に復元されてはいけない")
    }

    // MARK: - 10. 旧バックアップ（isInTrash/trashedAtキー自体が無い）を読み込んでもクラッシュしない

    func testLegacyBackupWithoutTrashFieldsDoesNotCrash() async throws {
        let book = makeBook()
        let expenseId = UUID().uuidString
        let json = """
        {
            "version": 1,
            "createdAt": "2026-01-01T00:00:00Z",
            "books": [{"id": "\(book.id.uuidString)", "name": "メイン帳簿", "createdAt": "2026-01-01T00:00:00Z", "sortOrder": 0, "isArchived": false, "isMain": true}],
            "expenses": [{"id": "\(expenseId)", "amount": 100, "date": "2026-01-01T00:00:00Z", "paymentMethod": "現金", "category": "食費", "memo": "旧形式", "createdAt": "2026-01-01T00:00:00Z", "isTestData": false, "bookId": "\(book.id.uuidString)"}],
            "incomes": [], "transfers": [], "categories": [], "paymentMethods": [], "receiveMethods": [],
            "bankAccounts": [], "budgets": [], "recurringBudgets": [], "fixedExpenses": [], "recurringIncomes": [], "recurringTransfers": [],
            "settings": {"showPreviousMonthCarryover": true}
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QARegressionLegacyTrash_\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try await BackupManager().restore(from: url, targetBookId: book.id)
        } catch {
            XCTFail("復元が失敗しないはずだが例外が発生した: \(error)")
        }
        let restored = ExpenseDataSync.fetchAll(bookId: book.id).first
        XCTAssertEqual(restored?.amount, 100)
        XCTAssertEqual(restored?.isInTrash, false, "旧バックアップにキーが無い場合はfalse扱いになる必要がある")
        XCTAssertNil(restored?.trashedAt)
    }

    // MARK: - 11. 写真付きデータをゴミ箱へ移動しても写真が残る

    func testTrashingDoesNotDeletePhotoFile() throws {
        let book = makeBook()
        guard let filename = ReceiptImageHelper.save(Data("dummy-photo-data".utf8)) else {
            XCTFail("テスト用写真ファイルの作成に失敗した")
            return
        }
        createdPhotoFilenames.append(filename)

        var expense = ExpenseData(amount: 100, date: Date(), paymentMethod: "現金", category: "食費", memo: "写真付き")
        expense.bookId = book.id
        expense.receiptImagePath = filename
        ExpenseDataSync.insert(expense)

        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )

        XCTAssertTrue(photoFileExists(filename), "ゴミ箱へ移動しただけでは写真ファイルを削除してはいけない")
    }

    // MARK: - 12. 完全削除時の写真削除が正しい

    func testPermanentDeleteRemovesPhotoFile() throws {
        let book = makeBook()
        guard let filename = ReceiptImageHelper.save(Data("dummy-photo-data-2".utf8)) else {
            XCTFail("テスト用写真ファイルの作成に失敗した")
            return
        }

        var expense = ExpenseData(amount: 100, date: Date(), paymentMethod: "現金", category: "食費", memo: "写真付き")
        expense.bookId = book.id
        expense.receiptImagePath = filename
        ExpenseDataSync.insert(expense)

        let item = TransactionListItem.expense(from: expense)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expense], transferDataList: []
        )
        let trashedList = ExpenseDataSync.fetchTrashed(bookId: book.id)
        _ = try repository.permanentlyDeleteTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: trashedList, transferDataList: []
        )

        XCTAssertFalse(photoFileExists(filename), "完全削除後は写真ファイルも削除されている必要がある")
    }

    // MARK: - 13. 対象帳簿以外のスナップショットやキャッシュが変化しない

    func testTrashingInOneBookDoesNotAffectOtherBookSnapshots() throws {
        let bookA = makeBook(name: "帳簿A", isMain: true)
        let bookB = makeBook(name: "帳簿B", isMain: false)

        var expenseA = ExpenseData(amount: 100, date: Date(), paymentMethod: "現金", category: "食費", memo: "A")
        expenseA.bookId = bookA.id
        ExpenseDataSync.insert(expenseA)
        var expenseB = ExpenseData(amount: 200, date: Date(), paymentMethod: "現金", category: "食費", memo: "B")
        expenseB.bookId = bookB.id
        ExpenseDataSync.insert(expenseB)
        SnapshotManager.rebuildAll()

        let beforeB = DailySnapshotSync.fetchAll(bookId: bookB.id).reduce(0) { $0 + $1.expenseTotal }
        XCTAssertEqual(beforeB, 200)

        let item = TransactionListItem.expense(from: expenseA)
        _ = try repository.trashTransaction(
            originalItem: item, incomeDataList: [], expenseDataList: [expenseA], transferDataList: []
        )
        SnapshotManager.rebuildAll()

        let afterB = DailySnapshotSync.fetchAll(bookId: bookB.id).reduce(0) { $0 + $1.expenseTotal }
        XCTAssertEqual(beforeB, afterB, "帳簿Aでのゴミ箱移動が帳簿Bのスナップショットに影響してはいけない")
    }
}
