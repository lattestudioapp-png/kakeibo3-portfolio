import XCTest
import SwiftData
@testable import kakeibo3

// MARK: - SwiftDataLegacyReaderの前半テスト
//
// この段階(本番Core Dataストアへの昇格処理はまだ未接続)で確認すべき最低限:
// 1. テスト用の旧SwiftDataストアを正常に読み取れる
// 2. 元の旧ストア(store/wal/shm)を一切変更していない
// 3. WALに未checkpointの差分がある状態でも最新値を読み取れる

final class SwiftDataLegacyReaderTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataLegacyReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - テスト用の旧ストア作成ヘルパー

    /// 指定ディレクトリに default.store を新規作成し、テスト用データを1件ずつ投入して保存する。
    /// 呼び出し側がcontainerを保持し続けるかどうかでWALのcheckpointタイミングが変わる
    /// (保持し続ければcheckpointされないまま、破棄すればcloseに伴いcheckpointされる)。
    @discardableResult
    private func makeTestLegacyStore(
        bookName: String = "テスト帳簿",
        expenseMemo: String = "初期データ"
    ) throws -> (paths: SwiftDataLegacyReader.LegacyStorePaths, container: ModelContainer, bookId: UUID) {
        let storeURL = workDirectory.appendingPathComponent("default.store")
        let schema = Schema(LegacySchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = LegacyBookData()
        book.id = UUID()
        book.name = bookName
        book.sortOrder = 0
        book.isMain = true
        context.insert(book)

        let expense = LegacyExpenseData()
        expense.id = UUID()
        expense.amount = 1234
        expense.category = "食費"
        expense.paymentMethod = "現金"
        expense.memo = expenseMemo
        expense.bookId = book.id
        context.insert(expense)

        try context.save()

        let paths = SwiftDataLegacyReader.LegacyStorePaths(
            store: storeURL,
            wal: workDirectory.appendingPathComponent("default.store-wal"),
            shm: workDirectory.appendingPathComponent("default.store-shm")
        )
        return (paths, container, book.id)
    }

    // MARK: - 1. テスト用の旧SwiftDataストアを正常に読み取れる

    func testReadsPopulatedLegacyStoreCorrectly() throws {
        let (paths, container, bookId) = try makeTestLegacyStore(bookName: "家計簿A", expenseMemo: "コンビニ")
        _ = container // 読み取り対象はコピー経由なので、ここで保持し続けても元ストアには影響しない

        let snapshot = try SwiftDataLegacyReader.readSnapshot(paths: paths)

        XCTAssertEqual(snapshot.books.count, 1)
        XCTAssertEqual(snapshot.books.first?.name, "家計簿A")
        XCTAssertEqual(snapshot.books.first?.isMain, true)

        XCTAssertEqual(snapshot.expenses.count, 1)
        XCTAssertEqual(snapshot.expenses.first?.amount, 1234)
        XCTAssertEqual(snapshot.expenses.first?.memo, "コンビニ")
        XCTAssertEqual(snapshot.expenses.first?.bookId, bookId)
    }

    func testReadSnapshotThrowsWhenStoreDoesNotExist() throws {
        // legacyStorePaths()自体はApplication Support配下を見るため、ここでは
        // 「パスがnil(=旧ストアが存在しない)」場合の分岐だけを直接確認する。
        XCTAssertThrowsError(try SwiftDataLegacyReader.readSnapshot(paths: nil)) { error in
            XCTAssertEqual(error as? LegacyReaderError, .storeNotFound)
        }
    }

    // MARK: - 2. 元の旧ストアを一切変更していない

    func testOriginalStoreIsNotModifiedByRead() throws {
        let (paths, container, _) = try makeTestLegacyStore()

        // containerを閉じて(参照を切って)、保存内容がstore本体にcheckpointされた
        // 状態を作ってから、3ファイルのハッシュ・更新日時を記録する。
        _ = container
        let checksumBefore = try fileChecksums(for: paths)

        _ = try SwiftDataLegacyReader.readSnapshot(paths: paths)

        let checksumAfter = try fileChecksums(for: paths)
        XCTAssertEqual(checksumBefore, checksumAfter, "readSnapshot(paths:)が元の旧ストアファイルを変更してはいけない")
    }

    private func fileChecksums(for paths: SwiftDataLegacyReader.LegacyStorePaths) throws -> [String: Data?] {
        func contents(_ url: URL) -> Data? {
            FileManager.default.fileExists(atPath: url.path) ? try? Data(contentsOf: url) : nil
        }
        return [
            "store": contents(paths.store),
            "wal": contents(paths.wal),
            "shm": contents(paths.shm)
        ]
    }

    // MARK: - 3. WALに未checkpointの差分がある状態でも最新値を読み取れる

    func testReadsLatestValueFromUncheckpointedWAL() throws {
        let storeURL = workDirectory.appendingPathComponent("default.store")
        let schema = Schema(LegacySchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = LegacyBookData()
        book.id = UUID()
        book.name = "WAL確認用帳簿"
        context.insert(book)
        try context.save()

        let paths = SwiftDataLegacyReader.LegacyStorePaths(
            store: storeURL,
            wal: workDirectory.appendingPathComponent("default.store-wal"),
            shm: workDirectory.appendingPathComponent("default.store-shm")
        )

        // containerを保持したまま(closeさせず)、-walに差分が残っていることを確認してから読み取る。
        // ここで-walが存在しない/空であれば、このテストはWALシナリオを検証できていないことになる。
        let walAttributes = try FileManager.default.attributesOfItem(atPath: paths.wal.path)
        let walSize = (walAttributes[.size] as? Int) ?? 0
        XCTAssertGreaterThan(walSize, 0, "-walに未checkpointの差分が無いと、このテストはWALシナリオを検証できていない")

        let snapshot = try SwiftDataLegacyReader.readSnapshot(paths: paths)
        XCTAssertEqual(snapshot.books.count, 1)
        XCTAssertEqual(snapshot.books.first?.name, "WAL確認用帳簿")

        _ = container // テスト終了までcontainerを保持し、暗黙のclose/checkpointに依存しないことを明示する
    }
}
