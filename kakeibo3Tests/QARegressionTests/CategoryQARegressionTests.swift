// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class CategoryQARegressionTests: QARegressionTestCase {
    private let repository = SwiftDataCategoryRepository()

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 支出カテゴリー追加

    func testCanAddExpenseCategory() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.addCategory(name: "交通費", type: "支出", existingCategories: [], bookId: main.book.id)

        let all = CategoryDataSync.fetchAll()
        XCTAssertTrue(all.contains { $0.name == "交通費" && $0.bookId == main.book.id })
    }

    func testExpenseCategoryIsAddedToCurrentBookOnly() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.addCategory(name: "交通費", type: "支出", existingCategories: [], bookId: main.book.id)

        let all = CategoryDataSync.fetchAll()
        XCTAssertFalse(all.contains { $0.name == "交通費" && $0.bookId == business.book.id })
    }

    // MARK: - 既知バグ: 同一帳簿内で同名カテゴリーを作れてしまう

    func testCannotCreateDuplicateCategoryNameInSameBook() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertThrowsError(
            try repository.addCategory(name: "食費", type: "支出", existingCategories: [], bookId: main.book.id)
        ) { error in
            guard case CategoryRepositoryError.duplicateName = error else {
                XCTFail("duplicateNameがthrowされるべき: \(error)"); return
            }
        }

        let all = CategoryDataSync.fetchAll()
        XCTAssertEqual(all.filter { $0.bookId == main.book.id && $0.type == "支出" && $0.name == "食費" }.count, 1)
    }

    func testCanCreateSameCategoryNameInDifferentBooks() throws {
        let (main, business, travel) = QARegressionTestFactory.makeThreeStandardBooks()

        // 3帳簿すべてに既に「食費」が存在する（ファクトリのシード）ことを確認
        let all = CategoryDataSync.fetchAll()
        XCTAssertEqual(all.filter { $0.name == "食費" && $0.type == "支出" }.count, 3)
        XCTAssertEqual(Set([main.book.id, business.book.id, travel.book.id]),
                        Set(all.filter { $0.name == "食費" }.compactMap { $0.bookId }))
    }

    // MARK: - 名前変更

    func testCanRenameCategory() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.renameCategory(category: main.expenseCategory, newName: "食費（改）", existingCategories: [])
        let renamed = CategoryDataSync.fetch(id: main.expenseCategory.id)
        XCTAssertEqual(renamed?.name, "食費（改）")
    }

    func testCannotRenameToExistingName() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.addCategory(name: "交通費", type: "支出", existingCategories: [], bookId: main.book.id)

        XCTAssertThrowsError(
            try repository.renameCategory(category: main.expenseCategory, newName: "交通費", existingCategories: [])
        )
        let unchanged = CategoryDataSync.fetch(id: main.expenseCategory.id)
        XCTAssertEqual(unchanged?.name, "食費") // 変更されていない
    }

    // MARK: - 並び替え

    func testCategoryReorderIsPersisted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.addCategory(name: "交通費", type: "支出", existingCategories: [], bookId: main.book.id)
        try repository.addCategory(name: "娯楽", type: "支出", existingCategories: [], bookId: main.book.id)

        let allCategories = CategoryDataSync.fetchAll(bookId: main.book.id)
        let expenseCategories = repository.sortedCategories(type: "支出", categories: allCategories)
        XCTAssertEqual(expenseCategories.map(\.name), ["食費", "交通費", "娯楽"])

        try repository.moveCategories(categories: expenseCategories, from: IndexSet(integer: 2), to: 0)

        let reordered = repository.sortedCategories(
            type: "支出",
            categories: CategoryDataSync.fetchAll(bookId: main.book.id)
        )
        XCTAssertEqual(reordered.map(\.name), ["娯楽", "食費", "交通費"])
    }

    // MARK: - 収入カテゴリー

    func testCanAddIncomeCategory() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.addCategory(name: "副業", type: "収入", existingCategories: [], bookId: main.book.id)

        let all = CategoryDataSync.fetchAll()
        XCTAssertTrue(all.contains { $0.name == "副業" && $0.bookId == main.book.id && $0.type == "収入" })
        XCTAssertFalse(all.contains { $0.name == "副業" && $0.bookId == business.book.id })
    }

    func testDuplicateIncomeCategoryDoesNotMixAcrossBooks() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // どちらの帳簿にも既に「給料」がある。それぞれ別の色・sortOrderで独立している
        XCTAssertNotEqual(main.incomeCategory.id, business.incomeCategory.id)
        XCTAssertEqual(main.incomeCategory.name, business.incomeCategory.name)
    }

    // MARK: - 使用停止仕様

    func testSuspendingCategoryRemovesItFromNewSelectionList() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        let visible = repository.categoryNames(
            type: "支出",
            categories: CategoryDataSync.fetchAll(bookId: main.book.id)
        )
        XCTAssertFalse(visible.contains("食費"))
    }

    func testSuspendedCategoryAppearsInSuspendedList() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        let all = CategoryDataSync.fetchAll(bookId: main.book.id)
        let suspended = all.filter { $0.type == "支出" && $0.isSuspended }
        XCTAssertEqual(suspended.map(\.name), ["食費"])
    }

    func testUnsuspendingCategoryReturnsItToNormalList() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        var unsuspendedCategory = suspendedCategory
        unsuspendedCategory.isSuspended = false
        CategoryDataSync.update(unsuspendedCategory)

        let visible = repository.categoryNames(
            type: "支出",
            categories: CategoryDataSync.fetchAll(bookId: main.book.id)
        )
        XCTAssertTrue(visible.contains("食費"))
    }

    func testSuspendingCategoryDoesNotAffectPastExpenseHistory() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 800, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        let expenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(expenses.filter { $0.bookId == main.book.id && $0.category == "食費" }.count, 1)
    }

    func testSuspendingCategoryDoesNotAffectSnapshotAggregation() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        QARegressionTestFactory.makeExpense(amount: 800, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        // 使用停止カテゴリーもスナップショット集計から除外しない
        SnapshotManager.rebuildAll()
        let dailySnapshots = DailySnapshotSync.fetchAll(bookId: main.book.id)
        let totalExpense = dailySnapshots.reduce(0) { $0 + $1.expenseTotal }
        XCTAssertEqual(totalExpense, 800)
    }

    // MARK: - 使用停止中カテゴリーの再追加(復活)

    func testReAddingSuspendedCategoryNameReactivatesInsteadOfCreatingDuplicate() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var suspendedCategory = main.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        XCTAssertThrowsError(
            try repository.addCategory(name: "食費", type: "支出", existingCategories: [], bookId: main.book.id)
        ) { error in
            guard case CategoryRepositoryError.suspendedNameExists(let suspended) = error else {
                XCTFail("suspendedNameExistsがthrowされるべき: \(error)"); return
            }
            XCTAssertEqual(suspended.id, main.expenseCategory.id)
        }

        // 新規カテゴリーは作られていない(同名カテゴリーは1件のまま)
        let all = CategoryDataSync.fetchAll()
        XCTAssertEqual(all.filter { $0.bookId == main.book.id && $0.name == "食費" && $0.type == "支出" }.count, 1)

        // 再開すると通常一覧に戻る
        let viewModel = CategoryEditViewModel()
        let current = try XCTUnwrap(CategoryDataSync.fetch(id: main.expenseCategory.id))
        viewModel.reactivateSuspendedCategory(current)
        let reactivated = try XCTUnwrap(CategoryDataSync.fetch(id: main.expenseCategory.id))
        XCTAssertFalse(reactivated.isSuspended)
    }

    func testSuspendedCategoryInOtherBookIsNotReactivationTarget() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var suspendedCategory = business.expenseCategory
        suspendedCategory.isSuspended = true
        CategoryDataSync.update(suspendedCategory)

        // メイン帳簿で「食費」を新規追加しようとしても、事業用帳簿の使用停止カテゴリーは対象にならない
        // （メイン帳簿には既に有効な「食費」があるため、通常の重複エラーになる）
        XCTAssertThrowsError(
            try repository.addCategory(name: "食費", type: "支出", existingCategories: [], bookId: main.book.id)
        ) { error in
            guard case CategoryRepositoryError.duplicateName = error else {
                XCTFail("メイン帳簿では通常の重複エラーになるべき: \(error)"); return
            }
        }
    }

    // MARK: - 初期残高カテゴリーの削除不可

    func testProtectedInitialBalanceCategoryCannotBeDeleted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var initialBalanceCategory = CategoryData(name: "初期残高", colorHex: "#95A5A6", type: "収入", sortOrder: 999)
        initialBalanceCategory.bookId = main.book.id
        initialBalanceCategory.isProtected = true
        CategoryDataSync.insert(initialBalanceCategory)

        XCTAssertThrowsError(
            try repository.deleteCategory(category: initialBalanceCategory)
        ) { error in
            guard case CategoryRepositoryError.protectedCategory = error else {
                XCTFail("protectedCategoryがthrowされるべき: \(error)"); return
            }
        }

        let all = CategoryDataSync.fetchAll()
        XCTAssertTrue(all.contains { $0.id == initialBalanceCategory.id })
    }

    func testNonProtectedCategoryCanBeDeleted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        try repository.addCategory(name: "娯楽", type: "支出", existingCategories: [], bookId: main.book.id)
        let target = try XCTUnwrap(CategoryDataSync.fetchAll().first { $0.name == "娯楽" })

        try repository.deleteCategory(category: target)

        let all = CategoryDataSync.fetchAll()
        XCTAssertFalse(all.contains { $0.name == "娯楽" })
    }
}
