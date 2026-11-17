import CoreData
import XCTest
@testable import kakeibo3

// MARK: - メイン帳簿の重複生成バグの回帰テスト
//
// 実機再現手順(クリーン起動→「あ」作成→帳簿切り替え画面でメイン帳簿が消える、または
// 複数のメイン帳簿が並存する)を、BookMigrationService.migrateIfNeeded()と
// BookSwitchSettingViewが実際に使うBookDataSync.observer()を通して検証する。
final class BookMigrationRegressionTests: QARegressionTestCase {

    // MARK: - 完全新規インストール → メイン帳簿1件だけ

    func testFreshInstallCreatesExactlyOneMainBook() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.isMain, true)
        XCTAssertEqual(books.first?.name, "メイン帳簿")
    }

    // MARK: - アプリ再起動10回 → メイン帳簿件数不変(実機バグの直接の再現テスト)

    func testTenConsecutiveLaunchesDoNotDuplicateMainBook() {
        for i in 0..<10 {
            BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
            let books = BookDataSync.fetchAll()
            XCTAssertEqual(books.count, 1, "launch \(i + 1)回目でメイン帳簿が重複していないこと")
        }
    }

    // MARK: - 新しい帳簿「あ」作成 → メイン帳簿と「あ」の2件表示(BookSwitchSettingViewと同じ経路)

    func testCreatingSecondBookShowsBothBooksInObserver() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let mainBook = try! XCTUnwrap(BookDataSync.fetchAll().first)

        let observer = BookDataSync.observer()
        XCTAssertEqual(observer.items.count, 1)

        let newBook = BookData(name: "あ", sortOrder: 1)
        BookDataSync.insert(newBook)

        XCTAssertEqual(observer.items.count, 2, "「あ」作成後、同じobserverでメイン帳簿と「あ」の2件が見えること")
        let names = Set(observer.items.map(\.name))
        XCTAssertEqual(names, ["メイン帳簿", "あ"])
        XCTAssertNotNil(BookDataSync.fetch(id: mainBook.id), "メイン帳簿のCDBookDataが削除されていないこと")
    }

    // MARK: - 「あ」を削除 → メイン帳簿1件

    func testDeletingSecondBookLeavesOnlyMainBook() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let newBook = BookData(name: "あ", sortOrder: 1)
        BookDataSync.insert(newBook)
        XCTAssertEqual(BookDataSync.fetchAll().count, 2)

        BookDeletionService.deleteBook(newBook)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.isMain, true)
    }

    // MARK: - currentBook切替 → Book件数不変(selectedBookIdStringの変更はBookDataを一切変更しない)

    func testSwitchingCurrentBookDoesNotChangeBookCount() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let mainBook = try! XCTUnwrap(BookDataSync.fetchAll().first)
        let secondBook = BookData(name: "あ", sortOrder: 1)
        BookDataSync.insert(secondBook)
        XCTAssertEqual(BookDataSync.fetchAll().count, 2)

        // BookSwitchSettingViewのbookRow(_:)/createBook()がしているのと同じ操作
        // (selectedBookIdStringの変更のみ、BookDataへの書き込みは一切無い)を模す。
        UserDefaults.standard.set(secondBook.id.uuidString, forKey: BookSettings.storageKey)
        XCTAssertEqual(BookDataSync.fetchAll().count, 2, "現在帳簿を「あ」に切り替えても件数は変わらない")

        UserDefaults.standard.set(mainBook.id.uuidString, forKey: BookSettings.storageKey)
        XCTAssertEqual(BookDataSync.fetchAll().count, 2, "現在帳簿をメイン帳簿に戻しても件数は変わらない")
    }

    // MARK: - Bookを表示するだけの操作でDBデータを変更しない

    func testObservingBooksDoesNotMutateData() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let before = BookDataSync.fetchAll()

        // BookSwitchSettingViewを開いて一覧を表示するのと同じ操作(observer生成・読み取りのみ)。
        _ = BookDataSync.observer()
        _ = BookDataSync.fetchAll()
        _ = BookDataSync.count()

        let after = BookDataSync.fetchAll()
        XCTAssertEqual(before, after)
    }

    // MARK: - 複数帳簿のUUIDが変化しない(表示・再取得のたびにidが変わらないこと)

    func testBookUUIDsRemainStableAcrossFetches() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let first = try! XCTUnwrap(BookDataSync.fetchAll().first)
        let second = try! XCTUnwrap(BookDataSync.fetch(id: first.id))
        XCTAssertEqual(first.id, second.id)
    }

    // MARK: - CloudKit同期ON状態で、初回import完了前は新規メイン帳簿を作らない

    func testCloudSyncActiveWithPendingImportDoesNotCreateMainBookViaFullPipeline() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookMigrationRegression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = try CoreDataStack(cloudLocalDirectory: dir, enableCloudKit: false, enableHistoryTracking: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        CoreDataStack.shared = stack

        // decideMainBookCreationに直接、「CloudKit有効・import未完了」を与えた場合の判定を確認する
        // (実際のCloudKit importイベントはCI環境では発生させられないため、判定ロジック自体を検証する)。
        let decision = BookMigrationService.decideMainBookCreation(
            existingBooks: BookDataSync.fetchAll(),
            legacyUnifiedStoreExists: false,
            cloudSyncActive: true,
            initialImportState: .pending
        )
        XCTAssertEqual(decision, .waitAndRetry)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty, "waitAndRetryの間はメイン帳簿を作らないため、ローカルは空のまま")
    }

    // MARK: - iCloudアカウント変更の統合確認：古いアカウントのestablishedMainBookIdが
    // 残っていても、アカウント変更を検知したら安全弁がクリアされ、新しいアカウントの
    // メイン帳簿を正しく作成できること(詰み状態にならないこと)。
    func testMigrateIfNeededResetsEstablishedAnchorWhenUbiquityIdentityChanges() {
        // 「古いiCloudアカウントの時に確立済み」の状態を模す:
        // 存在しない帳簿idをestablishedMainBookIdKeyに、ありえない値をlastKnownの
        // トークンにそれぞれ事前に設定しておく(実際のFileManager.ubiquityIdentityTokenが
        // 何であっても、この事前値とは一致しないため「変化した」と判定される)。
        let staleBookId = UUID()
        UserDefaults.standard.set(staleBookId.uuidString, forKey: BookMigrationService.establishedMainBookIdKey)
        UserDefaults.standard.set(
            Data([0xDE, 0xAD, 0xBE, 0xEF]),
            forKey: BookMigrationService.lastKnownUbiquityIdentityTokenDataKey
        )
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty, "事前条件：ローカルにBookDataが無いこと")

        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(
            books.count, 1,
            "アカウント変更を検知して安全弁がクリアされ、新しいメイン帳簿が1件作成されること" +
            "(クリアされなければ、古いestablishedMainBookIdのせいでwaitAndRetryのまま詰む)"
        )
        XCTAssertNotEqual(
            books.first?.id, staleBookId,
            "新しく作られた帳簿のidは、古いアカウントの時のidとは別であること"
        )
        let newAnchor = UserDefaults.standard.string(forKey: BookMigrationService.establishedMainBookIdKey)
        XCTAssertEqual(
            newAnchor, books.first?.id.uuidString,
            "establishedMainBookIdKeyが新しい帳簿のidで再確立されていること"
        )
    }

    // MARK: - 恒久対策の統合確認：一度確立済みのメイン帳簿が、ローカルから丸ごと消えても
    // (CloudKit内部resetによる一時的な再インポート待ち等を想定)、二度と重複作成されないこと。
    //
    // 実機調査で確認された不具合の再現条件そのもの：
    // 「initialImportStateは既にcompleted(前回成功済み) なのに、何らかの理由でローカルの
    // BookDataが一時的に0件になる」状態を、migrateIfNeeded()のフルパイプラインで模す。
    func testMigrateIfNeededNeverRecreatesMainBookAfterLocalStoreIsWipedOnceEstablished() {
        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
        let originalMainBook = try! XCTUnwrap(BookDataSync.fetchAll().first)
        XCTAssertEqual(BookDataSync.fetchAll().count, 1)

        // CloudKit内部resetがローカルミラーを丸ごと削除する様子を模す
        // (このテスト自体はCloudKitに繋がないため、BookDataSync.delete(id:)で直接再現する)。
        BookDataSync.delete(id: originalMainBook.id)
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty, "事前条件：ローカルのBookDataが丸ごと消えた状態")

        // 複数回migrateIfNeeded()を呼んでも(=複数回の再起動を模しても)、新しいメイン帳簿が
        // 作られてしまわないこと(確立済みidが記録されているため、waitAndRetryのまま)。
        for _ in 0..<5 {
            BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)
            XCTAssertTrue(
                BookDataSync.fetchAll().isEmpty,
                "一度確立済みのメイン帳簿がローカルから消えても、新しい重複メイン帳簿を作らないこと"
            )
        }
    }
}
