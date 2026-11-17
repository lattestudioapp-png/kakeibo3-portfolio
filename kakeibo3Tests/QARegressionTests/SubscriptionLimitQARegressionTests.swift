// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 注意: 調査の結果、このアプリには現在「無料版の帳簿数上限」は存在しない
// （Services/DowngradeLockService.swift のコメントで明示的に廃止済みと記載されている）。
// EntitlementStoreが管理するのは広告除去(hasRemoveAds)の単一の非消費型課金のみで、
// 帳簿数や項目数の上限・ロックは一切実装されていない。
// そのため、存在しない上限機能をでっち上げてテストするのではなく、
// 「過去にロックされていたデータが残っていても安全に扱えるか」という
// DowngradeLockServiceの実際の役割（後方互換の安全装置）を検証する。

import XCTest
@testable import kakeibo3

final class SubscriptionLimitQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 帳簿作成に上限がないことの確認

    func testCreatingManyBooksDoesNotHitAnyLimit() throws {
        for index in 0..<20 {
            QARegressionTestFactory.makeBook(name: "帳簿\(index)", sortOrder: index)
        }

        XCTAssertEqual(BookDataSync.fetchAll().count, 20)
    }

    // MARK: - 過去にロックされていたデータが残っていても表示される

    func testLockedItemsAreStillPersistedAndFetchable() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        // 過去バージョンでロックされたまま残っているデータを模す
        var cash = main.cash
        cash.isLocked = true
        PaymentMethodSettingDataSync.update(cash)

        let fetched = PaymentMethodSettingDataSync.fetchAll()
        XCTAssertTrue(fetched.contains { $0.id == main.cash.id })
    }

    func testLockedBankAccountDataIsNotDeleted() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bankAccount = main.bankAccount
        bankAccount.isLocked = true
        BankAccountDataSync.update(bankAccount)

        let fetched = BankAccountDataSync.fetchAll()
        XCTAssertTrue(fetched.contains { $0.id == main.bankAccount.id })
    }

    // MARK: - unlockAll で全解除される

    func testUnlockAllClearsLockedFlagsAcrossAllLockableTypes() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isLocked = true
        PaymentMethodSettingDataSync.update(cash)
        var bankAccount = main.bankAccount
        bankAccount.isLocked = true
        BankAccountDataSync.update(bankAccount)

        var fixedExpense = FixedExpenseData(name: "家賃", amount: 80000)
        fixedExpense.bookId = main.book.id
        fixedExpense.isLocked = true
        FixedExpenseDataSync.insert(fixedExpense)

        var recurringIncome = RecurringIncomeData(name: "給料", amount: 250000)
        recurringIncome.bookId = main.book.id
        recurringIncome.isLocked = true
        RecurringIncomeDataSync.insert(recurringIncome)

        var recurringTransfer = RecurringTransferSettingData(
            fromMethodId: main.cash.id, fromMethodName: "現金",
            toMethodId: main.bankAccount.id, toMethodName: "三井住友銀行",
            amount: 1000, day: 1
        )
        recurringTransfer.bookId = main.book.id
        recurringTransfer.isLocked = true
        RecurringTransferSettingDataSync.insert(recurringTransfer)

        DowngradeLockService.unlockAll()

        XCTAssertFalse(PaymentMethodSettingDataSync.fetch(id: main.cash.id)?.isLocked ?? true)
        XCTAssertFalse(BankAccountDataSync.fetch(id: main.bankAccount.id)?.isLocked ?? true)
        XCTAssertFalse(FixedExpenseDataSync.fetch(id: fixedExpense.id)?.isLocked ?? true)
        XCTAssertFalse(RecurringIncomeDataSync.fetch(id: recurringIncome.id)?.isLocked ?? true)
        XCTAssertFalse(RecurringTransferSettingDataSync.fetch(id: recurringTransfer.id)?.isLocked ?? true)
    }

    func testUnlockAllDoesNotAffectOtherBooksData() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var mainCash = main.cash
        mainCash.isLocked = true
        PaymentMethodSettingDataSync.update(mainCash)
        // business.cashはデフォルトでisLocked=falseのまま（変化なしを確認する対象）

        DowngradeLockService.unlockAll()

        XCTAssertFalse(PaymentMethodSettingDataSync.fetch(id: main.cash.id)?.isLocked ?? true)
        XCTAssertFalse(PaymentMethodSettingDataSync.fetch(id: business.cash.id)?.isLocked ?? true) // 元々falseなので変化なし
    }

    // MARK: - ロック中データが取引集計・資産集計から除外される判定ロジック自体は健在

    func testLockedMethodIsExcludedFromVisibleExpenses() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isLocked = true
        PaymentMethodSettingDataSync.update(cash)

        let expense = QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let visible = DowngradeLockService.visibleExpenses([expense], bankAccounts: [], paymentMethods: [cash])
        XCTAssertTrue(visible.isEmpty)
    }

    func testUnlockedMethodExpenseIsVisible() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let expense = QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let visible = DowngradeLockService.visibleExpenses([expense], bankAccounts: [], paymentMethods: [main.cash])
        XCTAssertEqual(visible.count, 1)
    }

    func testCreditCardUsableOnlyWhenCardAndWithdrawalAccountBothUnlocked() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var creditCard = main.creditCard
        creditCard.withdrawalBankAccountId = main.bankAccount.id
        PaymentMethodSettingDataSync.update(creditCard)

        XCTAssertTrue(DowngradeLockService.isCreditCardUsable(creditCard, bankAccounts: [main.bankAccount]))

        var bankAccount = main.bankAccount
        bankAccount.isLocked = true
        BankAccountDataSync.update(bankAccount)
        XCTAssertFalse(DowngradeLockService.isCreditCardUsable(creditCard, bankAccounts: [bankAccount]))
    }

    // MARK: - 解約後もデータは消えない（ロックされるだけ、という設計思想の確認）

    func testSimulatedDowngradeDoesNotDeleteAnyData() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        QARegressionTestFactory.makeExpense(amount: 500, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        // 「解約」を模して主要なロック対象にisLocked=trueを設定する
        var cash = main.cash
        cash.isLocked = true
        PaymentMethodSettingDataSync.update(cash)
        var bankAccount = main.bankAccount
        bankAccount.isLocked = true
        BankAccountDataSync.update(bankAccount)

        // データそのものは一切削除されない(3帳簿分：現金・電子マネー・カードが各帳簿にある)
        XCTAssertEqual(PaymentMethodSettingDataSync.fetchAll().count, 9)
        XCTAssertEqual(BankAccountDataSync.fetchAll().count, 3)
        XCTAssertEqual(ExpenseDataSync.fetchAll().count, 1)
    }

    func testSelectingLockedBookDuringUnlockDoesNotCrash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isLocked = true
        PaymentMethodSettingDataSync.update(cash)

        UserDefaults.standard.set(main.book.id.uuidString, forKey: BookSettings.storageKey)

        // ロック中データが残る帳簿を選択したままunlockAllを呼んでもクラッシュしない
        DowngradeLockService.unlockAll()

        let allBooks = BookDataSync.fetchAll()
        let resolved = BookResolver.resolveCurrentBook(from: allBooks, selectedIdString: UserDefaults.standard.string(forKey: BookSettings.storageKey) ?? "")
        XCTAssertEqual(resolved?.id, main.book.id)
    }
}
