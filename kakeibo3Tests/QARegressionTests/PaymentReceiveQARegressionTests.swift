// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

// このアプリには独立した「残高を管理」フラグは存在しない。isAsset が
// 「資産に含める」と「残高を管理する」の両方を兼ねている（項目6の実装調査で確認済み）。
final class PaymentReceiveQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 現金

    func testCanAddCash() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        XCTAssertEqual(main.cash.type, PaymentMethodType.cash.rawValue)
        XCTAssertEqual(main.cash.bookId, main.book.id)
    }

    func testShowInInputPickerControlsPaymentCandidateVisibility() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.showInInputPicker = true
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertTrue(cash.showInInputPicker)

        cash.showInInputPicker = false
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertFalse(cash.showInInputPicker)
    }

    func testUseForReceiveControlsReceiveCandidateVisibility() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.useForReceive = true
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertTrue(cash.useForReceive)

        cash.useForReceive = false
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertFalse(cash.useForReceive)
    }

    func testIsAssetControlsWhetherBalanceIsCalculated() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let income = QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        var cash = main.cash
        cash.isAsset = true
        PaymentMethodSettingDataSync.update(cash)
        let calculatorWithAsset = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [income], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        let includedSummaries = calculatorWithAsset.paymentMethodSummaries(
            for: [cash].filter { $0.isAsset }, upTo: Date.distantFuture
        )
        XCTAssertEqual(includedSummaries.first?.balance, 5000)

        cash.isAsset = false
        PaymentMethodSettingDataSync.update(cash)
        let excludedMethods = [cash].filter { $0.isAsset }
        XCTAssertTrue(excludedMethods.isEmpty)
    }

    func testIsAssetControlsInclusionInTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isAsset = false
        PaymentMethodSettingDataSync.update(cash)

        let allMethods = [cash, main.electronicMoney]
        // AnalysisViewModel.rebuildAsset と同じフィルタ条件
        let methodAssets = allMethods.filter { $0.isAsset && $0.isActive && !$0.isLocked && $0.type != PaymentMethodType.creditCard.rawValue }
        XCTAssertFalse(methodAssets.contains { $0.id == cash.id })
    }

    func testShowInAnalysisControlsVisibilityInAssetDetail() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.showInAnalysis = false
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertFalse(cash.showInAnalysis)

        cash.showInAnalysis = true
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertTrue(cash.showInAnalysis)
    }

    // MARK: - 既知バグ: 同名の現金が別帳簿にあっても混ざらない

    func testSameNameCashDoesNotMixAcrossBooks() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var mainCash = main.cash
        mainCash.isAsset = true
        PaymentMethodSettingDataSync.update(mainCash)
        var businessCash = business.cash
        businessCash.isAsset = false
        PaymentMethodSettingDataSync.update(businessCash)

        XCTAssertNotEqual(mainCash.id, businessCash.id)
        XCTAssertEqual(mainCash.methodName, businessCash.methodName)
        XCTAssertTrue(mainCash.isAsset)
        XCTAssertFalse(businessCash.isAsset)
    }

    func testCannotCreateDuplicateCashNameInSameBook() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertTrue(
            DuplicateNameChecker.isDuplicatePaymentMethodName(
                "現金", type: PaymentMethodType.cash.rawValue, bookId: main.book.id, excluding: nil
            )
        )
    }

    // MARK: - 電子マネー

    func testCanAddElectronicMoney() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        XCTAssertEqual(main.electronicMoney.methodName, "PayPay")
        XCTAssertEqual(main.electronicMoney.type, PaymentMethodType.electronicMoney.rawValue)
    }

    func testElectronicMoneyIsAssetToggleWorks() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var electronicMoney = main.electronicMoney
        electronicMoney.isAsset = true
        PaymentMethodSettingDataSync.update(electronicMoney)
        XCTAssertTrue(electronicMoney.isAsset)

        electronicMoney.isAsset = false
        PaymentMethodSettingDataSync.update(electronicMoney)
        XCTAssertFalse(electronicMoney.isAsset)
    }

    func testElectronicMoneyPaymentAndReceiveVisibilityToggles() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var electronicMoney = main.electronicMoney
        electronicMoney.showInInputPicker = false
        electronicMoney.useForReceive = true
        PaymentMethodSettingDataSync.update(electronicMoney)

        XCTAssertFalse(electronicMoney.showInInputPicker)
        XCTAssertTrue(electronicMoney.useForReceive)
    }

    func testSameNameElectronicMoneyDoesNotMixAcrossBooks() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var mainElectronicMoney = main.electronicMoney
        mainElectronicMoney.isAsset = true
        PaymentMethodSettingDataSync.update(mainElectronicMoney)
        var businessElectronicMoney = business.electronicMoney
        businessElectronicMoney.isAsset = false
        PaymentMethodSettingDataSync.update(businessElectronicMoney)

        XCTAssertEqual(mainElectronicMoney.methodName, businessElectronicMoney.methodName)
        XCTAssertNotEqual(mainElectronicMoney.isAsset, businessElectronicMoney.isAsset)
    }

    // MARK: - 銀行口座

    func testCanAddBankAccount() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        XCTAssertEqual(main.bankAccount.accountName, "三井住友銀行")
        XCTAssertEqual(main.bankAccount.bookId, main.book.id)
    }

    func testBankAccountInitialBalanceCanBeSet() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bankAccount = main.bankAccount
        bankAccount.initialBalance = 100000
        BankAccountDataSync.update(bankAccount)
        XCTAssertEqual(bankAccount.initialBalance, 100000)
    }

    func testBankAccountShowAsPaymentAndReceiveToggles() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bankAccount = main.bankAccount
        bankAccount.showAsPaymentMethod = true
        bankAccount.showAsReceiveMethod = false
        BankAccountDataSync.update(bankAccount)

        XCTAssertTrue(bankAccount.showAsPaymentMethod)
        XCTAssertFalse(bankAccount.showAsReceiveMethod)
    }

    func testBankAccountIsAssetFalseExcludesFromTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bankAccount = main.bankAccount
        bankAccount.isAsset = false
        BankAccountDataSync.update(bankAccount)

        let assetBanks = [bankAccount].filter { $0.isAsset }
        XCTAssertTrue(assetBanks.isEmpty)
    }

    func testBankAccountShowInAnalysisFalseHidesFromAssetDetail() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bankAccount = main.bankAccount
        bankAccount.showInAnalysis = false
        BankAccountDataSync.update(bankAccount)
        XCTAssertFalse(bankAccount.showInAnalysis)
    }

    func testBankAccountFromOtherBookIsNotVisible() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBankAccounts = BankAccountDataSync.fetchAll()
        let mainVisible = allBankAccounts.filter { $0.bookId == main.book.id }
        XCTAssertFalse(mainVisible.contains { $0.id == business.bankAccount.id })
    }

    func testSameNameBankAccountDoesNotMixAcrossBooks() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var mainBankAccount = main.bankAccount
        mainBankAccount.initialBalance = 50000
        BankAccountDataSync.update(mainBankAccount)
        var businessBankAccount = business.bankAccount
        businessBankAccount.initialBalance = 999999
        BankAccountDataSync.update(businessBankAccount)

        XCTAssertEqual(mainBankAccount.accountName, businessBankAccount.accountName)
        XCTAssertNotEqual(mainBankAccount.initialBalance, businessBankAccount.initialBalance)
    }

    func testCannotCreateDuplicateBankAccountNameInSameBook() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertTrue(
            DuplicateNameChecker.isDuplicateBankAccountName(
                "三井住友銀行", bookId: main.book.id, excluding: nil
            )
        )
        // 別帳簿ならOK
        XCTAssertFalse(
            DuplicateNameChecker.isDuplicateBankAccountName(
                "三井住友銀行", bookId: UUID(), excluding: nil
            )
        )
    }
}
