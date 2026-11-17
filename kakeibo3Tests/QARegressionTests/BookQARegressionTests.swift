// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class BookQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - メイン帳簿自動作成

    func testMainBookIsAutoCreatedWhenNoBooksExist() throws {
        XCTAssertTrue(BookDataSync.fetchAll().isEmpty)

        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.name, "メイン帳簿")
        XCTAssertEqual(books.first?.isMain, true)
    }

    func testMigrationDoesNotCreateSecondMainBookIfOneAlreadyExists() throws {
        let existing = QARegressionTestFactory.makeBook(name: "既存メイン帳簿", isMain: true)

        BookMigrationService.migrateIfNeeded(legacyUnifiedStoreExists: false)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.id, existing.id)
    }

    // MARK: - 新規帳簿作成

    func testCanCreateNewBook() throws {
        let book = QARegressionTestFactory.makeBook(name: "事業用帳簿", sortOrder: 1)

        let books = BookDataSync.fetchAll()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.id, book.id)
    }

    // MARK: - 帳簿名バリデーション
    //
    // 空文字チェックはViews/Other/BookSwitchSettingView.swift側の判定をそのまま再現するが、
    // 重複チェック自体はDuplicateNameChecker.isDuplicateBookName（本番コード）を直接呼び出す。
    // BookSwitchSettingView.createBook() / BookEditView.isDuplicateName の両方がこの
    // 同じ関数を使っているため、ここでの検証はそのまま両方の画面の回帰検知になる。

    private func canSaveBookName(_ name: String, allBooks: [BookData], excluding selfId: UUID?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !DuplicateNameChecker.isDuplicateBookName(trimmed, excluding: selfId, in: allBooks)
    }

    func testEmptyBookNameCannotBeSaved() {
        XCTAssertFalse(canSaveBookName("", allBooks: [], excluding: nil))
    }

    func testWhitespaceOnlyBookNameCannotBeSaved() {
        XCTAssertFalse(canSaveBookName("   ", allBooks: [], excluding: nil))
        XCTAssertFalse(canSaveBookName("\u{3000}\u{3000}", allBooks: [], excluding: nil)) // 全角スペース
    }

    func testDuplicateBookNameCannotBeSaved() throws {
        let existing = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        // 確認ケース1: 「メイン帳簿」が存在する状態で「メイン帳簿」を新規作成できない
        XCTAssertFalse(canSaveBookName("メイン帳簿", allBooks: [existing], excluding: nil))
        // 自分自身の名前はOK（変更なしで保存できる）
        XCTAssertTrue(canSaveBookName("メイン帳簿", allBooks: [existing], excluding: existing.id))
    }

    // 確認ケース2: 前後に空白が付いた名前（「 メイン帳簿 」）も同名扱いで作成できない
    func testDuplicateBookNameWithSurroundingSpacesCannotBeSaved() throws {
        let existing = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        XCTAssertFalse(canSaveBookName(" メイン帳簿 ", allBooks: [existing], excluding: nil))
        XCTAssertFalse(canSaveBookName("\u{3000}メイン帳簿\u{3000}", allBooks: [existing], excluding: nil)) // 全角スペース
    }

    // 大文字小文字は区別せず同名扱いにする（例: 「Main」と「main」）
    func testDuplicateBookNameIsCaseInsensitive() throws {
        let existing = QARegressionTestFactory.makeBook(name: "Main")

        XCTAssertFalse(canSaveBookName("main", allBooks: [existing], excluding: nil))
        XCTAssertFalse(canSaveBookName("MAIN", allBooks: [existing], excluding: nil))
        XCTAssertFalse(canSaveBookName("MaIn", allBooks: [existing], excluding: nil))
    }

    // 全角・半角スペースの違いだけでも同名扱いにする（内部の空白差異）
    func testDuplicateBookNameIgnoresFullWidthVsHalfWidthSpaceDifference() throws {
        let existing = QARegressionTestFactory.makeBook(name: "旅行 用帳簿") // 半角スペース

        XCTAssertFalse(canSaveBookName("旅行\u{3000}用帳簿", allBooks: [existing], excluding: nil)) // 全角スペース
    }

    // 確認ケース5: 現在の名前をそのまま再保存できる（大文字小文字・空白の表記ゆれを含めても自分自身は除外される）
    func testSavingUnchangedNameForSelfIsAllowed() throws {
        let existing = QARegressionTestFactory.makeBook(name: "事業用帳簿")

        XCTAssertTrue(canSaveBookName("事業用帳簿", allBooks: [existing], excluding: existing.id))
    }

    // 確認ケース7: 同名作成に失敗しても、既存の帳簿・データは一切変更されない
    func testFailedDuplicateCreationDoesNotCorruptExistingBooksOrData() throws {
        let (main, business, travel) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBooks = BookDataSync.fetchAll()
        XCTAssertFalse(canSaveBookName("事業用帳簿", allBooks: allBooks, excluding: nil))

        // 重複拒否後も、既存の3帳簿とその名前・件数は変化しない
        let afterBooks = BookDataSync.fetchAll()
        XCTAssertEqual(afterBooks.count, 3)
        XCTAssertEqual(main.book.name, "メイン帳簿")
        XCTAssertEqual(business.book.name, "事業用帳簿")
        XCTAssertEqual(travel.book.name, "旅行用帳簿")

        // 既存帳簿配下のカテゴリー等のデータも巻き込まれていない
        XCTAssertFalse(CategoryDataSync.fetchAll().isEmpty)
    }

    // 確認ケース8: 日本語・英語・数字・絵文字を含む名前は保存できる（重複判定に引っかからない）
    func testNameWithJapaneseEnglishNumbersAndEmojiCanBeSaved() throws {
        let existing = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        XCTAssertTrue(canSaveBookName("旅行Trip2026🎉", allBooks: [existing], excluding: nil))
    }

    func testVeryLongBookNameDoesNotCrash() throws {
        let longName = String(repeating: "あ", count: 5000)
        let book = QARegressionTestFactory.makeBook(name: longName)

        let fetched = BookDataSync.fetchAll()
        XCTAssertEqual(fetched.first?.id, book.id)
        XCTAssertEqual(fetched.first?.name.count, 5000)
    }

    func testEmojiBookNameDoesNotCrash() throws {
        let emojiName = "旅行用帳簿🎉✈️🏖️"
        let book = QARegressionTestFactory.makeBook(name: emojiName)

        let fetched = BookDataSync.fetchAll()
        XCTAssertEqual(fetched.first?.name, emojiName)
    }

    func testMixedLanguageBookNameCanBeSaved() throws {
        let mixedName = "Travel旅行2026"
        let book = QARegressionTestFactory.makeBook(name: mixedName)

        let fetched = BookDataSync.fetchAll()
        XCTAssertEqual(fetched.first?.id, book.id)
        XCTAssertEqual(fetched.first?.name, mixedName)
    }

    // MARK: - 帳簿切り替え

    func testSwitchingBookChangesCurrentBookId() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBooks = BookDataSync.fetchAll()

        let resolvedMain = BookResolver.resolveCurrentBook(from: allBooks, selectedIdString: main.book.id.uuidString)
        XCTAssertEqual(resolvedMain?.id, main.book.id)

        let resolvedBusiness = BookResolver.resolveCurrentBook(from: allBooks, selectedIdString: business.book.id.uuidString)
        XCTAssertEqual(resolvedBusiness?.id, business.book.id)
        XCTAssertNotEqual(resolvedMain?.id, resolvedBusiness?.id)
    }

    // MARK: - アプリ再起動相当での帳簿ID復元

    func testSelectedBookIdIsRestoredAcrossRestartEquivalent() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 「事業用帳簿」を選択した状態を模してUserDefaultsへ保存する
        UserDefaults.standard.set(business.book.id.uuidString, forKey: BookSettings.storageKey)

        // アプリ再起動相当：UserDefaultsから selectedBookIdString を読み直して解決する
        let restoredIdString = UserDefaults.standard.string(forKey: BookSettings.storageKey) ?? ""
        let allBooks = BookDataSync.fetchAll()
        let resolved = BookResolver.resolveCurrentBook(from: allBooks, selectedIdString: restoredIdString)

        XCTAssertEqual(resolved?.id, business.book.id)
        XCTAssertNotEqual(resolved?.id, main.book.id)
    }

    func testUnresolvableSelectedBookIdFallsBackToFirstVisibleBook() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBooks = BookDataSync.fetchAll()
        // 削除済み帳簿のIDなど、存在しないIDが保存されているケース
        let resolved = BookResolver.resolveCurrentBook(from: allBooks, selectedIdString: UUID().uuidString)

        XCTAssertEqual(resolved?.id, main.book.id) // sortOrder最小のメイン帳簿にフォールバック
    }

    // MARK: - 帳簿名変更

    func testRenamingBookKeepsSameBookId() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let originalId = business.book.id
        var renamedBook = business.book
        renamedBook.name = "リネーム後の帳簿"
        BookDataSync.update(renamedBook)

        let fetched = BookDataSync.fetchAll()
        let renamed = fetched.first { $0.id == originalId }
        XCTAssertEqual(renamed?.name, "リネーム後の帳簿")
        XCTAssertEqual(renamed?.id, originalId)

        // 他帳簿の名前は変わらない
        let unaffectedMain = fetched.first { $0.id == main.book.id }
        XCTAssertEqual(unaffectedMain?.name, "メイン帳簿")
    }

    func testRenamingToExistingNameIsRejected() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBooks = BookDataSync.fetchAll()
        XCTAssertFalse(canSaveBookName("メイン帳簿", allBooks: allBooks, excluding: business.book.id))

        // 拒否された場合、実際にnameを書き換えなければ元のままであることも確認する
        XCTAssertEqual(business.book.name, "事業用帳簿")
        XCTAssertEqual(main.book.name, "メイン帳簿")
    }

    func testRenamingToEmptyNameIsRejected() throws {
        let (_, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBooks = BookDataSync.fetchAll()
        XCTAssertFalse(canSaveBookName("", allBooks: allBooks, excluding: business.book.id))
        XCTAssertFalse(canSaveBookName("   ", allBooks: allBooks, excluding: business.book.id))
    }
}
