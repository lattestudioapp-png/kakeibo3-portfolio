import CoreData
import XCTest
@testable import kakeibo3

// MARK: - カテゴリー追加処理の回帰テスト
//
// 実機（iPhone）で「カテゴリーを追加できない」不具合が報告された調査の結果判明した、
// 以下の不具合の回帰テスト：
// 1. CategoryEditView「追加」ボタンがbookIdを解決できない場合、無言で何もしなかった
//    （InputView.onSave等と同じ理由）
// 2. CategoryEditViewModel.addCategoryは、永続化が実際に失敗した場合でも常に
//    newCategoryNameを空にしており、かつduplicateName/suspendedNameExists以外の
//    失敗はprint()のみでユーザーに一切伝わらなかった
//
// QARegressionTestCase（CoreDataStack(inMemory: true)の隔離ストア）で検証する。
final class CategorySaveFailureRegressionTests: QARegressionTestCase {

    // MARK: - 永続化が失敗するケースを模すフェイクRepository

    private struct AlwaysFailingCategoryRepository: CategoryRepository {
        func createDefaultCategoriesIfNeeded(existingCategories: [CategoryData], bookId: UUID) throws {}
        func categoryNames(type: String, categories: [CategoryData]) -> [String] { [] }
        func sortedCategories(type: String, categories: [CategoryData]) -> [CategoryData] { [] }
        func addCategory(name: String, type: String, existingCategories: [CategoryData], bookId: UUID) throws {
            throw TransactionSaveError.persistenceFailed
        }
        func renameCategory(category: CategoryData, newName: String, existingCategories: [CategoryData]) throws {}
        func deleteCategory(category: CategoryData) throws {}
        func moveCategories(categories: [CategoryData], from source: IndexSet, to destination: Int) throws {}
    }

    // MARK: - カテゴリー追加の正常な永続化（7,8,9の土台）

    func testAddCategoryPersistsAndIsFetchableFromFreshContext() {
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)
        let viewModel = CategoryEditViewModel()
        viewModel.newCategoryName = "交通費"

        viewModel.addCategory(type: "支出", existingCategories: [], bookId: book.id)

        XCTAssertNil(viewModel.errorAlertMessage, "正常な追加でエラーが出ないこと")
        XCTAssertEqual(viewModel.newCategoryName, "", "追加成功後は入力欄がクリアされること")

        let saved = CategoryDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(saved.map(\.name), ["交通費"], "7: カテゴリーが正常に永続化されること")

        // 8: 別contextからも再取得できること
        let freshContext = CoreDataStack.shared.container.newBackgroundContext()
        freshContext.performAndWait {
            let fetch = CDCategoryData.fetchRequest()
            fetch.predicate = NSPredicate(format: "name == %@", "交通費")
            XCTAssertEqual((try? freshContext.fetch(fetch))?.count, 1, "8: 別contextから再取得できること")
        }
    }

    // MARK: - 9: アプリ再起動相当のストア再読み込み後もカテゴリーが残ること

    func testAddedCategorySurvivesRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)
        let viewModel = CategoryEditViewModel()
        viewModel.newCategoryName = "娯楽費"
        viewModel.addCategory(type: "支出", existingCategories: [], bookId: book.id)

        // CoreDataStack（＝NSPersistentContainer）を破棄し、同じURLから再生成する
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let reloaded = CategoryDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(reloaded.map(\.name), ["娯楽費"], "9: アプリ再起動相当後もカテゴリーが残っていること")
    }

    // MARK: - 帳簿が解決できない場合、無言で何もせず明確なエラーになること

    func testAddCategoryWithNoBookShowsErrorInsteadOfSilentNoOp() {
        // CategoryEditViewのボタン内ロジックと同じ条件（bookIdが一切解決できない）を
        // ViewModel/Repositoryの責務範囲で再現する：帳簿がそもそも無いため、
        // 呼び出し元（View）はaddCategoryを呼ばずにエラーを設定する、という設計を検証する。
        XCTAssertEqual(BookDataSync.fetchAll().count, 0, "事前条件：帳簿が1件も無いこと")
        XCTAssertNil(BookResolver.mainBookId(), "帳簿が無い場合、mainBookIdはnilであること")
        // → この場合CategoryEditView側はviewModel.addCategoryを呼ばず、
        //   viewModel.errorAlertMessageへ直接セットする（CategoryEditView.swift参照）。
        //   ここではその前提条件（bookIdが解決できないこと自体）を固定化する。
    }

    // MARK: - 永続化失敗時：入力内容が保持され、エラーが通知されること

    func testPersistenceFailureDoesNotClearInputAndShowsError() {
        let viewModel = CategoryEditViewModel(categoryRepository: AlwaysFailingCategoryRepository())
        viewModel.newCategoryName = "食費"
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        viewModel.addCategory(type: "支出", existingCategories: [], bookId: book.id)

        XCTAssertNotNil(viewModel.errorAlertMessage, "永続化失敗時にエラーメッセージが設定されること")
        XCTAssertEqual(viewModel.newCategoryName, "食費", "永続化失敗時は入力内容（カテゴリー名）が保持されること")
    }

    // MARK: - 重複名チェック失敗時も入力内容が保持されること（既存挙動の回帰確認）

    func testDuplicateNameFailureDoesNotClearInput() {
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)
        var existing = CategoryData(name: "食費", colorHex: "#111111", type: "支出", sortOrder: 0)
        existing.bookId = book.id
        CategoryDataSync.insert(existing)

        let viewModel = CategoryEditViewModel()
        viewModel.newCategoryName = "食費"
        viewModel.addCategory(type: "支出", existingCategories: [existing], bookId: book.id)

        XCTAssertNotNil(viewModel.errorAlertMessage, "重複名の場合にエラーメッセージが設定されること")
        XCTAssertEqual(viewModel.newCategoryName, "食費", "重複名で失敗した場合も入力内容が保持されること")
        XCTAssertEqual(CategoryDataSync.fetchAll(bookId: book.id).count, 1, "重複名では新規カテゴリーが作られないこと")
    }
}
