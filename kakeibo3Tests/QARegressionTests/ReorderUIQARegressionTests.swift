// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 並び替えUI改善（④）の回帰テスト：
// - MethodOption/TransferParticipantへのcolorHex伝播
// - TransferParticipantBuilderの重複排除（種別をまたいだ同名統合・孤立した受け取り方法の除外）

import XCTest
@testable import kakeibo3

final class ReorderUIQARegressionTests: QARegressionTestCase {

    // MARK: - MethodOptionへのcolorHex伝播

    func testExpenseOptionsPropagateColorHexFromPaymentMethodsAndBankAccounts() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var cash = main.cash
        cash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.update(cash)

        var bank = main.bankAccount
        bank.colorHex = "#82C08A"
        bank.showAsPaymentMethod = true
        BankAccountDataSync.update(bank)

        let options = MethodOptionBuilder.expenseOptions(
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            bankAccounts: BankAccountDataSync.fetchAll(bookId: main.book.id)
        )

        XCTAssertEqual(options.first { $0.id == cash.id }?.colorHex, "#4A7DBA")
        XCTAssertEqual(options.first { $0.id == bank.id }?.colorHex, "#82C08A")
    }

    func testIncomeOptionsPropagateColorHex() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var cash = main.cash
        cash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.update(cash)

        let options = MethodOptionBuilder.incomeOptions(
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            bankAccounts: BankAccountDataSync.fetchAll(bookId: main.book.id)
        )

        XCTAssertEqual(options.first { $0.id == cash.id }?.colorHex, "#4A7DBA")
    }

    // MARK: - TransferParticipantへのcolorHex伝播

    func testTransferParticipantsPropagateColorHexFromBankAndPaymentMethod() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var cash = main.cash
        cash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.update(cash)

        var bank = main.bankAccount
        bank.colorHex = "#82C08A"
        BankAccountDataSync.update(bank)

        let participants = TransferParticipantBuilder.build(
            bankAccounts: BankAccountDataSync.fetchAll(bookId: main.book.id),
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            receiveMethods: []
        )

        XCTAssertEqual(participants.first { $0.id == cash.id }?.colorHex, "#4A7DBA")
        XCTAssertEqual(participants.first { $0.id == bank.id }?.colorHex, "#82C08A")
    }

    func testReceiveMethodParticipantInheritsColorFromSameNamedPaymentMethod() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 支払い一覧・受け取り一覧のどちらからも外された（showInInputPicker/useForReceiveが
        // 共にfalse）が、レコード自体とcolorHexは残っているPaymentMethodSettingData
        // （TransferParticipantBuilder.payments のフィルタでは除外されるが、
        // colorByPaymentNameの色逆引きには使われる想定のケース）。
        var hiddenCash = main.cash
        hiddenCash.showInInputPicker = false
        hiddenCash.useForReceive = false
        hiddenCash.colorHex = "#4A7DBA"
        PaymentMethodSettingDataSync.update(hiddenCash)

        var receiveCash = ReceiveMethodData(methodName: "現金", sortOrder: 1)
        receiveCash.bookId = main.book.id
        ReceiveMethodDataSync.insert(receiveCash)

        let participants = TransferParticipantBuilder.build(
            bankAccounts: [],
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            receiveMethods: [receiveCash]
        )

        // 支払い方法側の「現金」は一覧から外れて候補に出ないが、受け取り方法側の
        // 「現金」がその色を引き継いで表示されること
        XCTAssertFalse(participants.contains { $0.id == hiddenCash.id })
        XCTAssertEqual(participants.first { $0.name == "現金" }?.colorHex, "#4A7DBA")
    }

    // MARK: - 重複排除：種別をまたいだ同名統合

    func testDuplicateNamesAcrossPaymentAndReceiveAreMergedIntoOne() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 「現金」の支払い方法(useForReceive=true)に加えて、統合前の名残であるReceiveMethodData側の
        // 「現金」も同時に存在するケース（DataInitializerService.reconcileReceiveMethodsForBookが
        // 効く前の状態を模す）。
        var legacyReceiveCash = ReceiveMethodData(methodName: "現金", sortOrder: 99)
        legacyReceiveCash.bookId = main.book.id
        ReceiveMethodDataSync.insert(legacyReceiveCash)

        let participants = TransferParticipantBuilder.build(
            bankAccounts: BankAccountDataSync.fetchAll(bookId: main.book.id),
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            receiveMethods: [legacyReceiveCash]
        )

        XCTAssertEqual(participants.filter { $0.name == "現金" }.count, 1, "種別をまたいでも同名なら振替候補は1つに統合されること")
    }

    // MARK: - 孤立した受け取り方法の除外

    func testReceiveMethodIsExcludedWhenMatchingPaymentMethodIsDeleted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 支払い方法「現金」を削除（isActive=false）
        var cash = main.cash
        cash.isActive = false
        PaymentMethodSettingDataSync.update(cash)

        // 対応する受け取り方法側の「現金」が孤立して残っている
        var orphanedReceiveCash = ReceiveMethodData(methodName: "現金", sortOrder: 1)
        orphanedReceiveCash.bookId = main.book.id
        ReceiveMethodDataSync.insert(orphanedReceiveCash)

        let participants = TransferParticipantBuilder.build(
            bankAccounts: BankAccountDataSync.fetchAll(bookId: main.book.id),
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            receiveMethods: [orphanedReceiveCash]
        )

        XCTAssertFalse(participants.contains { $0.name == "現金" }, "対応する支払い方法が削除済みなら、孤立した受け取り方法は振替候補に出さないこと")
    }

    func testReceiveMethodIsIncludedWhenNoMatchingPaymentMethodEverExisted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 対応する支払い方法が一度も存在しない、独立した受け取り方法
        var independentReceive = ReceiveMethodData(methodName: "ポイント", sortOrder: 5)
        independentReceive.bookId = main.book.id
        ReceiveMethodDataSync.insert(independentReceive)

        let participants = TransferParticipantBuilder.build(
            bankAccounts: BankAccountDataSync.fetchAll(bookId: main.book.id),
            paymentMethods: PaymentMethodSettingDataSync.fetchAll(bookId: main.book.id),
            receiveMethods: [independentReceive]
        )

        XCTAssertTrue(participants.contains { $0.name == "ポイント" }, "対応する支払い方法が存在しない受け取り方法は除外されないこと")
    }

    // MARK: - ReorderHintViewのスモークテスト

    @MainActor
    func testReorderHintViewDoesNotCrash() {
        let view = ReorderHintView()
        _ = view.body
    }
}
