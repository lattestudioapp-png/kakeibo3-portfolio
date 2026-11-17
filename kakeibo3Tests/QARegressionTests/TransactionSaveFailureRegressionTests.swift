import CoreData
import XCTest
@testable import kakeibo3

// MARK: - 支出・収入・振替の保存処理、および編集処理の回帰テスト
//
// 実機（iPhone/iPad）で「支出を保存してもカレンダー/分析/履歴から消える」不具合が
// 報告された調査の結果判明した、以下2点の実際の不具合の回帰テスト：
// 1. 帳簿が解決できない状態で保存すると、無言で何も保存されない（ユーザーに一切伝わらない）
// 2. 取引履歴の編集時、帳簿が解決できない場合に`?? UUID()`で意味の無いランダムなbookIdへ
//    保存してしまう（どの帳簿からも二度と見えなくなる）
//
// すべてQARegressionTestCase（setUpでCoreDataStack.shared = CoreDataStack(inMemory: true)）
// を使い、実機のデータには一切触れない隔離されたストアで検証する。
final class TransactionSaveFailureRegressionTests: QARegressionTestCase {

    // MARK: - 失敗する保存先を模すフェイクRepository（Core Dataのsave()自体が
    // 失敗するケースを、InputViewModel/TransactionRepositoryの責務分離を保ったまま
    // 決定的に再現するために使う）

    private struct AlwaysFailingRepository: TransactionRepository {
        func insertNewTransaction(draft: TransactionDraft, expenseTypeName: String) throws {
            throw TransactionSaveError.persistenceFailed
        }
        func updateTransaction(
            originalItem: TransactionListItem, draft: TransactionDraft, expenseTypeName: String,
            incomeDataList: [IncomeData], expenseDataList: [ExpenseData]
        ) throws -> Bool {
            throw TransactionSaveError.persistenceFailed
        }
        func deleteTransaction(
            originalItem: TransactionListItem, incomeDataList: [IncomeData], expenseDataList: [ExpenseData]
        ) throws -> Bool { true }
        func trashTransaction(
            originalItem: TransactionListItem, incomeDataList: [IncomeData],
            expenseDataList: [ExpenseData], transferDataList: [TransferData]
        ) throws -> Bool { true }
        func restoreTransaction(
            originalItem: TransactionListItem, incomeDataList: [IncomeData],
            expenseDataList: [ExpenseData], transferDataList: [TransferData]
        ) throws -> Bool { true }
        func permanentlyDeleteTransaction(
            originalItem: TransactionListItem, incomeDataList: [IncomeData],
            expenseDataList: [ExpenseData], transferDataList: [TransferData]
        ) throws -> Bool { true }
        func emptyTrash(
            bookId: UUID, incomeDataList: [IncomeData],
            expenseDataList: [ExpenseData], transferDataList: [TransferData]
        ) throws -> Int { 0 }
    }

    // MARK: - 1〜3. 帳簿が無い場合に保存失敗として処理され、入力が保持され、エラーが伝わる

    func testSaveNewTransactionWithNoBookFailsWithoutResettingInputAndNotifiesUser() {
        let viewModel = InputViewModel()
        viewModel.amountText = "1500"
        viewModel.memo = "テストメモ"
        viewModel.selectedExpenseCategory = "食費"

        let succeeded = viewModel.saveNewTransaction(
            expenseCategories: ["食費"], bankAccountId: nil, bookId: nil
        )

        XCTAssertFalse(succeeded, "1: 帳簿が無い場合は保存失敗として処理されること")
        XCTAssertEqual(viewModel.amountText, "1500", "2: 保存失敗時に入力内容（金額）が保持されること")
        XCTAssertEqual(viewModel.memo, "テストメモ", "2: 保存失敗時に入力内容（メモ）が保持されること")
        XCTAssertNotNil(viewModel.lastSaveErrorMessage, "3: 保存失敗時にユーザー向けエラーメッセージが設定されること")
        XCTAssertEqual(ExpenseDataSync.fetchAll().count, 0, "帳簿が無い状態では支出が1件も保存されていないこと")
    }

    // MARK: - 4. 帳簿の再取得・再試行後に保存できること

    func testSaveNewTransactionSucceedsAfterBookBecomesAvailable() {
        let viewModel = InputViewModel()
        viewModel.amountText = "2000"
        viewModel.memo = "再試行確認"
        viewModel.selectedExpenseCategory = "食費"

        // 1回目：帳簿が無く失敗する
        XCTAssertFalse(viewModel.saveNewTransaction(expenseCategories: ["食費"], bankAccountId: nil, bookId: nil))
        XCTAssertNotNil(viewModel.lastSaveErrorMessage)

        // 帳簿が（CloudKit取り込み完了やBookMigrationServiceの再試行等で）後から用意されたことを模す
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        // 2回目：入力内容はそのまま残っているので、同じ入力で再試行できる
        let succeeded = viewModel.saveNewTransaction(expenseCategories: ["食費"], bankAccountId: nil, bookId: book.id)
        XCTAssertTrue(succeeded, "4: 帳簿が用意された後の再試行で保存できること")
        XCTAssertNil(viewModel.lastSaveErrorMessage, "再試行成功後はエラーが解消されること")

        let saved = ExpenseDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.amount, 2000)
    }

    // MARK: - 5. 再試行後も帳簿が存在しない場合、不正なbookIdで保存しないこと

    func testRepeatedSaveAttemptsWithoutBookNeverCreateExpenseWithInvalidBookId() {
        let viewModel = InputViewModel()
        viewModel.amountText = "999"
        viewModel.selectedExpenseCategory = "食費"

        for _ in 0..<3 {
            let succeeded = viewModel.saveNewTransaction(expenseCategories: ["食費"], bankAccountId: nil, bookId: nil)
            XCTAssertFalse(succeeded)
        }

        XCTAssertEqual(ExpenseDataSync.fetchAll().count, 0, "5: 帳簿が最後まで用意されない場合、不正なbookIdで保存されていないこと")
        XCTAssertEqual(BookDataSync.fetchAll().count, 0, "帳簿自体も作られていないこと（保存処理側が勝手に帳簿を作ってはいけない）")
    }

    // MARK: - 6. 取引履歴の編集時に帳簿が見つからない場合、ランダムなUUIDを生成しないこと

    func testUpdateTransactionWithUnresolvableBookDoesNotUseRandomUUID() {
        // item.bookIdが無い（マイグレーション未実施の異常系）取引を用意する
        var expense = ExpenseData(amount: 500, date: Date(), paymentMethod: "現金", category: "食費", memo: "旧データ")
        expense.bookId = nil
        ExpenseDataSync.insert(expense)
        let item = TransactionListItem.expense(from: expense)

        let editViewModel = TransactionHistoryEditViewModel(item: item)
        let inputViewModel = InputViewModel()
        editViewModel.applyItem(to: inputViewModel)
        inputViewModel.amountText = "600"

        // fallbackBookIdもnil（帳簿が一件も無い）＝以前は`?? UUID()`でランダムなIDへ保存していた状況
        let succeeded = editViewModel.updateTransaction(
            inputViewModel: inputViewModel,
            incomeDataList: [],
            expenseDataList: [expense],
            bankAccountId: nil,
            fallbackBookId: nil
        )

        XCTAssertFalse(succeeded, "6: 帳簿が解決できない場合は保存失敗として処理されること")
        XCTAssertNotNil(editViewModel.lastSaveErrorMessage)

        // 元の支出のbookIdが(ランダムなUUIDを含め)一切変更されていないこと
        let reloaded = ExpenseDataSync.fetch(id: expense.id)
        XCTAssertNil(reloaded?.bookId, "ランダムなUUID等、意味の無いbookIdへ書き換えられていないこと")
        XCTAssertEqual(reloaded?.amount, 500, "保存失敗時は元の金額も変更されないこと")
    }

    // MARK: - 7〜8. 支出・収入・振替が正常に永続化され、別contextから再取得できること

    func testExpenseIncomeTransferPersistAndAreFetchableFromFreshContext() {
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        var expense = ExpenseData(amount: 1234, date: Date(), paymentMethod: "現金", category: "食費", memo: "支出確認")
        expense.bookId = book.id
        XCTAssertTrue(ExpenseDataSync.insertChecked(expense), "7: 支出の永続化が成功として報告されること")

        var income = IncomeData(amount: 5678, date: Date(), receiveMethod: "現金", category: "給料", memo: "収入確認")
        income.bookId = book.id
        XCTAssertTrue(IncomeDataSync.insertChecked(income), "7: 収入の永続化が成功として報告されること")

        var transfer = TransferData(
            date: Date(), fromType: "payment", fromId: nil, fromName: "現金",
            toType: "bank", toId: nil, toName: "口座", amount: 999, feeAmount: 0, memo: "振替確認"
        )
        transfer.bookId = book.id
        XCTAssertTrue(TransferDataSync.insertChecked(transfer), "7: 振替の永続化が成功として報告されること")

        // 8: viewContextとは別の新規contextから再取得できることを確認する
        let freshContext = CoreDataStack.shared.container.newBackgroundContext()
        freshContext.performAndWait {
            let expenseFetch = CDExpenseData.fetchRequest()
            expenseFetch.predicate = NSPredicate(format: "id == %@", expense.id as CVarArg)
            XCTAssertEqual((try? freshContext.fetch(expenseFetch))?.count, 1, "8: 別contextから支出を再取得できること")

            let incomeFetch = CDIncomeData.fetchRequest()
            incomeFetch.predicate = NSPredicate(format: "id == %@", income.id as CVarArg)
            XCTAssertEqual((try? freshContext.fetch(incomeFetch))?.count, 1, "8: 別contextから収入を再取得できること")

            let transferFetch = CDTransferData.fetchRequest()
            transferFetch.predicate = NSPredicate(format: "id == %@", transfer.id as CVarArg)
            XCTAssertEqual((try? freshContext.fetch(transferFetch))?.count, 1, "8: 別contextから振替を再取得できること")
        }
    }

    // MARK: - 9. アプリ再起動相当のストア再読み込み後も保存した取引が残っていること

    func testExpenseSurvivesRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransactionSaveFailureRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)
        var expense = ExpenseData(amount: 4321, date: Date(), paymentMethod: "現金", category: "食費", memo: "再起動確認")
        expense.bookId = book.id
        XCTAssertTrue(ExpenseDataSync.insertChecked(expense))

        // CoreDataStack（＝NSPersistentContainer）を破棄し、同じURLから再生成する
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let reloaded = ExpenseDataSync.fetchAll(bookId: book.id)
        XCTAssertEqual(reloaded.map(\.amount), [4321], "9: アプリ再起動相当後も保存した支出が残っていること")
    }

    // MARK: - 10. CloudKit初回インポート未完了時に、重複したメイン帳簿を作成しないこと
    //
    // BookMigrationRegressionTests.testCloudSyncActiveWithPendingImportDoesNotCreateMainBookViaFullPipeline
    // と同種の確認を、今回initialImportTimeoutを8秒→15秒へ変更したことによる回帰がないことも
    // 含めて、decideMainBookCreationへ直接.pendingを与えて確認する。

    func testPendingCloudKitImportNeverCreatesDuplicateMainBook() {
        let existingBook = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        for _ in 0..<3 {
            let decision = BookMigrationService.decideMainBookCreation(
                existingBooks: BookDataSync.fetchAll(),
                legacyUnifiedStoreExists: false,
                cloudSyncActive: true,
                initialImportState: .pending
            )
            XCTAssertEqual(decision, .useExisting(existingBook.id), "既存帳簿がある場合は再利用されること")
        }

        // 既存帳簿が無い場合は、import未完了のままなら作成せず待機すること
        BookDataSync.delete(id: existingBook.id)
        for _ in 0..<3 {
            let decision = BookMigrationService.decideMainBookCreation(
                existingBooks: BookDataSync.fetchAll(),
                legacyUnifiedStoreExists: false,
                cloudSyncActive: true,
                initialImportState: .pending
            )
            XCTAssertEqual(decision, .waitAndRetry, "10: import未完了のまま新しいメイン帳簿を作らないこと")
        }
        XCTAssertEqual(BookDataSync.fetchAll().count, 0, "waitAndRetryの判定自体は帳簿を作らないこと")
    }

    // MARK: - 永続化失敗（Core Dataのsave()自体が失敗する異常系）の明示的な確認

    func testPersistenceFailurePropagatesAsErrorNotSilentSuccess() {
        let viewModel = InputViewModel(transactionRepository: AlwaysFailingRepository())
        viewModel.amountText = "100"
        viewModel.selectedExpenseCategory = "食費"
        let book = QARegressionTestFactory.makeBook(name: "メイン帳簿", isMain: true)

        let succeeded = viewModel.saveNewTransaction(expenseCategories: ["食費"], bankAccountId: nil, bookId: book.id)

        XCTAssertFalse(succeeded, "Core Dataへの永続化が失敗した場合も保存失敗として処理されること")
        XCTAssertNotNil(viewModel.lastSaveErrorMessage)
        XCTAssertEqual(viewModel.amountText, "100", "永続化失敗時も入力内容が保持されること")
    }
}
