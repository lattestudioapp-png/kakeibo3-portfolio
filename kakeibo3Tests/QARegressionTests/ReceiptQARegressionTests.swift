// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
import UIKit
@testable import kakeibo3

@MainActor
final class ReceiptQARegressionTests: QARegressionTestCase {
    // MARK: - テスト用画像・下書き生成

    private func makeTestImage(color: UIColor = .red) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    private func makeDraft(
        image: UIImage,
        paymentMethod: String? = "現金",
        items: [ReceiptDraftItem]
    ) -> ReceiptDraft {
        ReceiptDraft(
            capturedImage: image,
            date: Date(),
            storeName: "テストストア",
            paymentMethod: paymentMethod,
            receiptTotal: nil,
            taxAmount: nil,
            isTaxIncluded: nil,
            items: items
        )
    }

    // MARK: - 複数行保存

    func testSavingMultipleCheckedItemsCreatesMultipleExpensesSharingOneReceiptImagePath() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        viewModel.draft = makeDraft(
            image: makeTestImage(color: .red),
            items: [
                ReceiptDraftItem(productName: "りんご", amount: 200, category: "食費", suggestedCategory: "食費"),
                ReceiptDraftItem(productName: "パン", amount: 300, category: "食費", suggestedCategory: "食費")
            ]
        )

        let count = try viewModel.save(
            expenseTypeName: "支出",
            bookId: main.book.id,
            bankAccounts: []
        )

        XCTAssertEqual(count, 2)
        let expenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(expenses.count, 2)
        XCTAssertEqual(Set(expenses.map(\.memo)), ["りんご", "パン"])
        XCTAssertEqual(Set(expenses.map(\.amount)), [200, 300])

        let paths = Set(expenses.compactMap(\.receiptImagePath))
        XCTAssertEqual(paths.count, 1, "同一レシート画像は1回だけ保存され、全行が同じreceiptImagePathを共有する")
    }

    // MARK: - チェック除外行は保存されない

    func testUncheckedItemsAreNotSaved() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        var excludedItem = ReceiptDraftItem(productName: "対象外", amount: 999, category: "食費", suggestedCategory: "食費")
        excludedItem.isIncluded = false
        viewModel.draft = makeDraft(
            image: makeTestImage(color: .blue),
            items: [
                ReceiptDraftItem(productName: "対象", amount: 100, category: "食費", suggestedCategory: "食費"),
                excludedItem
            ]
        )

        let count = try viewModel.save(expenseTypeName: "支出", bookId: main.book.id, bankAccounts: [])

        XCTAssertEqual(count, 1)
        let expenses = ExpenseDataSync.fetchAll(bookId: main.book.id)
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.memo, "対象")
    }

    // MARK: - バリデーションエラー

    func testSaveThrowsWhenNoItemsAreSelected() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        var excludedItem = ReceiptDraftItem(productName: "対象外", amount: 100, category: "食費", suggestedCategory: "食費")
        excludedItem.isIncluded = false
        viewModel.draft = makeDraft(image: makeTestImage(), items: [excludedItem])

        XCTAssertThrowsError(
            try viewModel.save(expenseTypeName: "支出", bookId: main.book.id, bankAccounts: [])
        ) { error in
            XCTAssertEqual(error as? ReceiptSaveError, .noItemsSelected)
        }
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: main.book.id).count, 0)
    }

    func testSaveThrowsWhenAnyCheckedItemHasUnsetCategory() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        viewModel.draft = makeDraft(
            image: makeTestImage(),
            items: [
                ReceiptDraftItem(
                    productName: "不明な商品",
                    amount: 100,
                    category: ReceiptCategorySuggestionService.unsetCategory,
                    suggestedCategory: ReceiptCategorySuggestionService.unsetCategory
                )
            ]
        )

        XCTAssertThrowsError(
            try viewModel.save(expenseTypeName: "支出", bookId: main.book.id, bankAccounts: [])
        ) { error in
            XCTAssertEqual(error as? ReceiptSaveError, .unsetCategoryExists)
        }
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: main.book.id).count, 0)
    }

    func testSaveThrowsWhenPaymentMethodIsMissing() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        viewModel.draft = makeDraft(
            image: makeTestImage(),
            paymentMethod: nil,
            items: [ReceiptDraftItem(productName: "商品", amount: 100, category: "食費", suggestedCategory: "食費")]
        )

        XCTAssertThrowsError(
            try viewModel.save(expenseTypeName: "支出", bookId: main.book.id, bankAccounts: [])
        ) { error in
            XCTAssertEqual(error as? ReceiptSaveError, .paymentMethodMissing)
        }
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: main.book.id).count, 0)
    }

    // MARK: - 他帳簿への非影響

    func testReceiptSaveOnlyAffectsTargetBook() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        viewModel.draft = makeDraft(
            image: makeTestImage(color: .green),
            items: [ReceiptDraftItem(productName: "商品", amount: 500, category: "食費", suggestedCategory: "食費")]
        )

        _ = try viewModel.save(expenseTypeName: "支出", bookId: main.book.id, bankAccounts: [])

        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: main.book.id).count, 1)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: business.book.id).count, 0)
    }

    // MARK: - 銀行口座（支払い方法名一致）の解決

    func testSaveResolvesBankAccountIdWhenPaymentMethodMatchesActiveBankAccount() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let viewModel = ReceiptScanViewModel()
        viewModel.draft = makeDraft(
            image: makeTestImage(color: .yellow),
            paymentMethod: "三井住友銀行",
            items: [ReceiptDraftItem(productName: "商品", amount: 700, category: "食費", suggestedCategory: "食費")]
        )

        _ = try viewModel.save(
            expenseTypeName: "支出",
            bookId: main.book.id,
            bankAccounts: [main.bankAccount]
        )

        let saved = ExpenseDataSync.fetchAll(bookId: main.book.id).first
        XCTAssertEqual(saved?.bankAccountId, main.bankAccount.id)
    }

    // MARK: - カテゴリー学習ストア（UserDefaults往復）

    func testReceiptCategoryLearningStoreRoundTrip() {
        let productName = "テスト商品_\(UUID().uuidString)"
        XCTAssertNil(ReceiptCategoryLearningStore.suggestedCategory(forProductName: productName))

        ReceiptCategoryLearningStore.recordCorrection(productName: productName, category: "日用品")
        XCTAssertEqual(ReceiptCategoryLearningStore.suggestedCategory(forProductName: productName), "日用品")
    }

    func testReceiptCategoryLearningStoreIgnoresUnsetCategory() {
        let productName = "テスト商品_\(UUID().uuidString)"
        ReceiptCategoryLearningStore.recordCorrection(
            productName: productName,
            category: ReceiptCategorySuggestionService.unsetCategory
        )
        XCTAssertNil(ReceiptCategoryLearningStore.suggestedCategory(forProductName: productName))
    }

    // MARK: - 重複防止ストア（UserDefaults往復）

    func testReceiptDuplicateGuardStoreRoundTrip() {
        let image = makeTestImage(color: .purple)
        XCTAssertFalse(ReceiptDuplicateGuardStore.isDuplicate(image))

        ReceiptDuplicateGuardStore.markSaved(image)
        XCTAssertTrue(ReceiptDuplicateGuardStore.isDuplicate(image))
    }

    // MARK: - 機能フラグ

    func testReceiptFeatureFlagIsDisabledByDefault() {
        XCTAssertFalse(FeatureFlags.isReceiptFeatureEnabled, "公開版では非表示のため、既定値はfalseのまま")
    }

    // MARK: - フラグOFF時のTransactionTypeSwitchViewの見た目（インスタンス化のみのスモークテスト）
    //
    // showsReceipt/onReceiptSelectのデフォルト値がfalse/nilのため、既存呼び出し側（TransferInputPageView等）は
    // 何も変更せずに以前と同じ2/3択のセグメントバーになる。selectedIndex/itemsはprivateのため、
    // ここでは「デフォルト値でのインスタンス化とbody評価がクラッシュしないこと」を確認する。
    func testTransactionTypeSwitchViewWithDefaultsDoesNotCrash() {
        let view = TransactionTypeSwitchView(
            selectedType: .constant("支出"),
            expenseSetting: ExpenseInputSetting(),
            incomeSetting: IncomeInputSetting(),
            onChange: { _ in }
        )
        _ = view.body
    }

    // MARK: - 実SQLite永続ストアでの再起動相当テスト

    func testReceiptSavedExpenseAndPhotoSurviveRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionReceiptRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        // 1. 一時ディレクトリに永続ストアを作成
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let mainBook = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
        BookDataSync.insert(mainBook)
        let otherBook = BookData(name: "事業用帳簿", sortOrder: 1, isMain: false)
        BookDataSync.insert(otherBook)
        var otherExpense = ExpenseData(amount: 777, date: Date(), paymentMethod: "現金", category: "食費", memo: "他帳簿")
        otherExpense.bookId = otherBook.id
        ExpenseDataSync.insert(otherExpense)

        // 2. レシートOCR経由で保存（写真ファイルも実際にDocuments/receiptsへ書き込まれる）
        let viewModel = ReceiptScanViewModel()
        viewModel.draft = makeDraft(
            image: makeTestImage(color: .orange),
            items: [ReceiptDraftItem(productName: "再起動確認商品", amount: 1234, category: "食費", suggestedCategory: "食費")]
        )
        _ = try viewModel.save(expenseTypeName: "支出", bookId: mainBook.id, bankAccounts: [])

        let savedPath = try XCTUnwrap(ExpenseDataSync.fetchAll(bookId: mainBook.id).first?.receiptImagePath)
        defer { ReceiptImageHelper.delete(savedPath) }

        // 3-4. CoreDataStackを破棄し、同じストアURLから再生成する（アプリ終了→再起動に相当）
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        // 5. 保存した支出・写真参照が維持されていることを確認
        let mainExpensesAfterRestart = ExpenseDataSync.fetchAll(bookId: mainBook.id)
        XCTAssertEqual(mainExpensesAfterRestart.map(\.amount), [1234])
        XCTAssertEqual(mainExpensesAfterRestart.first?.receiptImagePath, savedPath)
        XCTAssertNotNil(ReceiptImageHelper.load(savedPath), "レシート写真ファイル自体も再起動後に読み込めること")

        // 6. 他帳簿は変化していないこと
        let otherExpensesAfterRestart = ExpenseDataSync.fetchAll(bookId: otherBook.id)
        XCTAssertEqual(otherExpensesAfterRestart.map(\.amount), [777])
    }
}
