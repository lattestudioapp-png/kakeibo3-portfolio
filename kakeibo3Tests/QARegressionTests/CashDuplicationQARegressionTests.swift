// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 既知バグ: データリセット後、「現金」がPaymentMethodSettingDataとReceiveMethodDataの
// 両方に別レコードとして作られてしまい、支払い・受け取り・振替候補で現金が重複表示される。
// 原因: migrateReceiveMethodsIfNeeded はアプリ全体で一度きりのUserDefaultsフラグで
// ガードされているため、初回移行が完了した後にリセット・新規作成された帳簿には
// 二度と効かない。DataInitializerService.reconcileReceiveMethodsForBook(bookId:) で、
// フラグに関係なくこの帳簿ぶんだけ即座に再整合させることで解消する。

import XCTest
@testable import kakeibo3

final class CashDuplicationQARegressionTests: QARegressionTestCase {

    // MARK: - ヘルパー

    /// 帳簿単位のデータリセット直後に相当する状態を作る（既存データなしから開始）。
    private func makeFreshBook(name: String = "メイン帳簿") -> BookData {
        let book = BookData(name: name, sortOrder: 0, isMain: true)
        BookDataSync.insert(book)
        return book
    }

    // MARK: - 1〜2. データリセット直後は現金が1件だけ有効

    func testDataResetDoesNotCreateDuplicateActiveCash() throws {
        let book = makeFreshBook()

        DataResetService.resetAll(bookId: book.id)

        let activePaymentCash = PaymentMethodSettingDataSync.fetchAll(bookId: book.id)
            .filter { $0.methodName == "現金" && $0.isActive }
        let activeReceiveCash = ReceiveMethodDataSync.fetchAll(bookId: book.id)
            .filter { $0.methodName == "現金" && $0.isActive }

        XCTAssertEqual(activePaymentCash.count, 1, "支払い方法としての現金は1件だけであるべき")
        XCTAssertTrue(activePaymentCash.first?.useForReceive ?? false, "受け取りにも使えるよう統合されているべき")
        XCTAssertEqual(activeReceiveCash.count, 0, "ReceiveMethodData側の現金は無効化され、重複して有効なままにならないべき")
    }

    // MARK: - 3. 削除済み現金は振替候補に残らない

    func testDeletedInitialCashDoesNotRemainInTransferCandidates() throws {
        let book = makeFreshBook()
        DataResetService.resetAll(bookId: book.id)

        var cash = try XCTUnwrap(PaymentMethodSettingDataSync.fetchAll(bookId: book.id).first { $0.methodName == "現金" })
        cash.isActive = false
        PaymentMethodSettingDataSync.update(cash)

        let participants = TransferParticipantBuilder.build(
            bankAccounts: BankAccountDataSync.fetchAll(bookId: book.id),
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: book.id),
            receiveMethods: ReceiveMethodDataSync.fetchAll(bookId: book.id)
        )
        XCTAssertFalse(participants.contains { $0.name == "現金" })
    }

    // MARK: - 4〜5. 削除後に新しい現金を追加しても重複しない

    func testAddingNewCashAfterDeletingInitialOneDoesNotDuplicate() throws {
        let book = makeFreshBook()
        DataResetService.resetAll(bookId: book.id)

        var initialCash = try XCTUnwrap(PaymentMethodSettingDataSync.fetchAll(bookId: book.id).first { $0.methodName == "現金" })
        initialCash.isActive = false
        PaymentMethodSettingDataSync.update(initialCash)

        var newCash = PaymentMethodSettingData(methodName: "現金", type: PaymentMethodType.cash.rawValue, sortOrder: 1)
        newCash.showInInputPicker = true
        newCash.useForReceive = true
        newCash.isAsset = true
        newCash.bookId = book.id
        PaymentMethodSettingDataSync.insert(newCash)

        let paymentMethods = PaymentMethodSettingDataSync.fetchAll(bookId: book.id)
        let bankAccounts = BankAccountDataSync.fetchAll(bookId: book.id)
        let receiveMethods = ReceiveMethodDataSync.fetchAll(bookId: book.id)

        let expenseOptions = MethodOptionBuilder.expenseOptions(paymentMethods: paymentMethods, bankAccounts: bankAccounts)
        let incomeOptions = MethodOptionBuilder.incomeOptions(paymentMethods: paymentMethods, bankAccounts: bankAccounts)
        let transferParticipants = TransferParticipantBuilder.build(
            bankAccounts: bankAccounts, paymentMethods: paymentMethods, receiveMethods: receiveMethods
        )

        XCTAssertEqual(expenseOptions.filter { $0.name == "現金" }.count, 1, "支払い候補に現金が重複表示されないこと")
        XCTAssertEqual(incomeOptions.filter { $0.name == "現金" }.count, 1, "受け取り候補に現金が重複表示されないこと")
        XCTAssertEqual(transferParticipants.filter { $0.name == "現金" }.count, 1, "振替候補に現金が重複表示されないこと")
    }

    // MARK: - 6. 実SQLite永続ストアでの再起動相当テスト

    func testReconciliationSurvivesRealPersistentStoreRestart() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionCashDupRestartTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let book = makeFreshBook()
        DataResetService.resetAll(bookId: book.id)

        // アプリ終了→再起動に相当
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        let activePaymentCash = PaymentMethodSettingDataSync.fetchAll(bookId: book.id)
            .filter { $0.methodName == "現金" && $0.isActive }
        let activeReceiveCash = ReceiveMethodDataSync.fetchAll(bookId: book.id)
            .filter { $0.methodName == "現金" && $0.isActive }

        XCTAssertEqual(activePaymentCash.count, 1, "再起動後も現金の重複が発生しないこと")
        XCTAssertEqual(activeReceiveCash.count, 0, "再起動後もReceiveMethodData側の現金は無効化されたままであること")
    }

    // MARK: - 7. 複数帳簿で別帳簿の現金が混ざらない

    func testResetInOneBookDoesNotAffectOtherBookCashMethods() throws {
        let mainBook = makeFreshBook(name: "メイン帳簿")
        let otherBook = makeFreshBook(name: "事業用帳簿")
        DataResetService.resetAll(bookId: mainBook.id)
        DataResetService.resetAll(bookId: otherBook.id)

        let mainCash = PaymentMethodSettingDataSync.fetchAll(bookId: mainBook.id).filter { $0.methodName == "現金" && $0.isActive }
        let otherCash = PaymentMethodSettingDataSync.fetchAll(bookId: otherBook.id).filter { $0.methodName == "現金" && $0.isActive }

        XCTAssertEqual(mainCash.count, 1)
        XCTAssertEqual(otherCash.count, 1)
        XCTAssertNotEqual(mainCash.first?.id, otherCash.first?.id)

        // 片方の帳簿だけリセットしても、もう一方は変化しない
        DataResetService.resetAll(bookId: mainBook.id)
        let otherCashAfter = PaymentMethodSettingDataSync.fetchAll(bookId: otherBook.id).filter { $0.methodName == "現金" && $0.isActive }
        XCTAssertEqual(otherCashAfter.count, 1)
        XCTAssertEqual(otherCashAfter.first?.id, otherCash.first?.id, "他帳簿の現金レコード自体が変化しないこと")
    }

    // MARK: - 8. 同名の現金を不正に重複作成しない

    func testDuplicateNameCheckerRejectsSecondActiveCashAfterReset() throws {
        let book = makeFreshBook()
        DataResetService.resetAll(bookId: book.id)

        let isDuplicate = DuplicateNameChecker.isDuplicatePaymentMethodName(
            "現金", type: PaymentMethodType.cash.rawValue, bookId: book.id
        )
        XCTAssertTrue(isDuplicate, "リセット直後、既に有効な現金があるため同名の現金は重複エラーになるべき")
    }

    // MARK: - 9. 初期現金の資産に含める設定(isAsset)が維持される

    func testResetPreservesInitialCashIsAssetFlag() throws {
        let book = makeFreshBook()
        DataResetService.resetAll(bookId: book.id)

        let cash = try XCTUnwrap(PaymentMethodSettingDataSync.fetchAll(bookId: book.id).first { $0.methodName == "現金" })
        XCTAssertTrue(cash.isAsset, "初期現金は資産に含める設定(isAsset=true)で作られ、再整合処理で失われないこと")
    }

    // MARK: - 新規帳簿作成時も同じ経路で重複しない（InputView.seedDefaultDataForCurrentBookIfNeededと同じ手順）

    func testNewBookCreationDoesNotCreateDuplicateCashEither() throws {
        // 既にアプリ全体の移行フラグが立っている状態を模す
        // （実機では初回起動時に一度だけ立つため、以後に作られる帳簿は全てこの状態）
        UserDefaults.standard.set(true, forKey: "receiveMethodsMigratedV1")

        let book = makeFreshBook(name: "新規帳簿")
        DataInitializerService.createDefaultPaymentMethodsIfNeeded(existing: [], bookId: book.id)
        DataInitializerService.createDefaultReceiveMethodsIfNeeded(existing: [], bookId: book.id)
        DataInitializerService.reconcileReceiveMethodsForBook(bookId: book.id)

        let activePaymentCash = PaymentMethodSettingDataSync.fetchAll(bookId: book.id)
            .filter { $0.methodName == "現金" && $0.isActive }
        let activeReceiveCash = ReceiveMethodDataSync.fetchAll(bookId: book.id)
            .filter { $0.methodName == "現金" && $0.isActive }

        XCTAssertEqual(activePaymentCash.count, 1)
        XCTAssertEqual(activeReceiveCash.count, 0)
    }
}
