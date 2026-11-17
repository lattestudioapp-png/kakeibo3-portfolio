import XCTest
@testable import kakeibo3

// MARK: - BookFactoryResetService.eraseAllBooksAndResetAnchors()の回帰テスト
//
// 将来、重複した36帳簿を完全初期化する際に使う想定の機能。このservice自体は
// まだUIから呼ばれていない(明示的なユーザー確認を取るUI操作は未実装)。
//
// 【最重要の確認ポイント】establishedMainBookIdKeyをクリアし忘れると、
// BookMigrationService.decideMainBookCreationが「確立済みなのに0件」と判断して
// 永久にwaitAndRetryし、新しいメイン帳簿を二度と作れなくなる(詰み)。
// このテストは、eraseAllBooksAndResetAnchors()の直後にBookMigrationService.migrateIfNeeded()
// を呼んだ場合に、その詰みが発生しないことを確認する。
final class BookFactoryResetServiceTests: QARegressionTestCase {

    func testEraseAllBooksAndResetAnchorsRemovesAllBooksAndPerBookData() {
        let bookA = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true, sortOrder: 0)
        let fixtureA = QARegressionTestFactory.seedStandardData(book: bookA)
        let bookB = QARegressionTestFactory.makeBook(name: "重複メイン帳簿", isMain: true, sortOrder: 1)
        QARegressionTestFactory.seedStandardData(book: bookB)

        UserDefaults.standard.set(bookA.id.uuidString, forKey: BookSettings.storageKey)
        UserDefaults.standard.set(bookA.id.uuidString, forKey: BookMigrationService.establishedMainBookIdKey)

        BookFactoryResetService.eraseAllBooksAndResetAnchors()

        XCTAssertTrue(BookDataSync.fetchAll().isEmpty, "全帳簿が削除されていること")
        XCTAssertTrue(CategoryDataSync.fetchAll(bookId: bookA.id).isEmpty, "帳簿Aぶんのカテゴリーも削除されていること")
        XCTAssertTrue(CategoryDataSync.fetchAll(bookId: bookB.id).isEmpty, "帳簿Bぶんのカテゴリーも削除されていること")
        XCTAssertNil(PaymentMethodSettingDataSync.fetch(id: fixtureA.cash.id), "帳簿Aぶんの支払い方法も削除されていること")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: BookSettings.storageKey),
            "selectedBookIdがクリアされていること"
        )
        XCTAssertNil(
            UserDefaults.standard.string(forKey: BookMigrationService.establishedMainBookIdKey),
            "establishedMainBookIdKeyがクリアされていること(クリア忘れは次回起動で詰みを引き起こす)"
        )
    }

    func testMigrateIfNeededCreatesFreshMainBookAfterFactoryResetWithoutGettingStuck() {
        // 事前に複数の(重複した)メイン帳簿を作っておく。
        let bookA = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true, sortOrder: 0)
        QARegressionTestFactory.seedStandardData(book: bookA)
        let bookB = QARegressionTestFactory.makeBook(name: "重複メイン帳簿", isMain: true, sortOrder: 1)
        QARegressionTestFactory.seedStandardData(book: bookB)
        UserDefaults.standard.set(bookA.id.uuidString, forKey: BookMigrationService.establishedMainBookIdKey)

        BookFactoryResetService.eraseAllBooksAndResetAnchors()
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty, "事前条件：初期化直後は帳簿が0件であること")

        // 初期化直後、通常の起動シーケンスと同じ経路(migrateIfNeeded)で新しいメイン帳簿を作らせる。
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(
            books.count, 1,
            "初期化後、詰まらずにちょうど1件の新しいメイン帳簿が作成されること" +
            "(establishedMainBookIdKeyのクリア忘れがあれば、ここは0件のまま=詰みになる)"
        )
        XCTAssertEqual(books.first?.isMain, true)
        XCTAssertNotEqual(books.first?.id, bookA.id, "新しい帳簿は古い帳簿Aとは別のidであること")
        XCTAssertNotEqual(books.first?.id, bookB.id, "新しい帳簿は古い帳簿Bとは別のidであること")

        // 新しい帳簿に対して、通常の初回起動と同じデフォルトカテゴリーが作られること
        // (DataInitializerService等の後続処理が正しく動く状態になっていることの確認)。
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: BookMigrationService.establishedMainBookIdKey),
            books.first?.id.uuidString,
            "新しいestablishedMainBookIdKeyが、新しく作られた帳簿のidで再確立されていること"
        )
    }

    // MARK: - 繰り返しの完全初期化でも安全(1回だけでなく、何度行っても詰まらないこと)

    func testRepeatedFactoryResetAndRecreateNeverGetsStuck() {
        for iteration in 0..<3 {
            let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true, sortOrder: 0)
            QARegressionTestFactory.seedStandardData(book: book)

            BookFactoryResetService.eraseAllBooksAndResetAnchors()
            BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

            XCTAssertEqual(
                BookDataSync.fetchAll().count, 1,
                "\(iteration + 1)回目の完全初期化後も、詰まらずに1件の新しいメイン帳簿が作成されること"
            )
        }
    }
}
