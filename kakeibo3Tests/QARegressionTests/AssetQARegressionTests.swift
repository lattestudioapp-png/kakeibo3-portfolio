// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class AssetQARegressionTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 資産に含めるOFFの各項目が総資産に入らない

    func testAssetExcludedCashIsNotIncludedInTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isAsset = false
        PaymentMethodSettingDataSync.update(cash)

        let income = QARegressionTestFactory.makeIncome(amount: 1000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let methodAssets = [cash].filter { $0.isAsset && $0.isActive && $0.type != PaymentMethodType.creditCard.rawValue }
        XCTAssertTrue(methodAssets.isEmpty)

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [income], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        let summaries = calculator.paymentMethodSummaries(for: methodAssets, upTo: Date.distantFuture)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testAssetExcludedBankAccountIsNotIncludedInTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var bankAccount = main.bankAccount
        bankAccount.isAsset = false
        BankAccountDataSync.update(bankAccount)

        let assetBanks = [bankAccount].filter { $0.isAsset }
        XCTAssertTrue(assetBanks.isEmpty)
    }

    func testAssetExcludedElectronicMoneyIsNotIncludedInTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var electronicMoney = main.electronicMoney
        electronicMoney.isAsset = false
        PaymentMethodSettingDataSync.update(electronicMoney)

        let methodAssets = [electronicMoney].filter { $0.isAsset }
        XCTAssertTrue(methodAssets.isEmpty)
    }

    func testAnalysisHiddenAssetDoesNotAppearInDetail() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.showInAnalysis = false
        PaymentMethodSettingDataSync.update(cash)
        XCTAssertFalse(cash.showInAnalysis)
    }

    // MARK: - 初期残高・収入・支出による残高変動

    func testInitialBalanceIsReflectedInBalance() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let initialBalanceIncome = QARegressionTestFactory.makeIncome(
            amount: 10000, receiveMethod: "現金", category: "初期残高", bookId: main.book.id
        )

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [initialBalanceIncome], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        let summaries = calculator.paymentMethodSummaries(for: [main.cash], upTo: Date.distantFuture)
        XCTAssertEqual(summaries.first?.balance, 10000)
    }

    func testExpenseDecreasesBalance() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let initialBalanceIncome = QARegressionTestFactory.makeIncome(
            amount: 10000, receiveMethod: "現金", category: "初期残高", bookId: main.book.id
        )
        let expense = QARegressionTestFactory.makeExpense(
            amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id
        )

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [initialBalanceIncome], allExpenseData: [expense], allTransferData: [], creditCardNames: []
        )
        let summaries = calculator.paymentMethodSummaries(for: [main.cash], upTo: Date.distantFuture)
        XCTAssertEqual(summaries.first?.balance, 9900)
    }

    func testIncomeIncreasesBalance() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let income = QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [income], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        let summaries = calculator.paymentMethodSummaries(for: [main.cash], upTo: Date.distantFuture)
        XCTAssertEqual(summaries.first?.balance, 5000)
    }

    func testTransferDoesNotDoubleCountTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let income = QARegressionTestFactory.makeIncome(amount: 10000, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        var transfer = TransferData(
            fromType: TransferAccountType.paymentMethod.rawValue, fromId: main.cash.id, fromName: "現金",
            toType: TransferAccountType.bank.rawValue, toId: main.bankAccount.id, toName: "三井住友銀行",
            amount: 4000
        )
        transfer.bookId = main.book.id
        TransferDataSync.insert(transfer)

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [main.bankAccount], allIncomeData: [income], allExpenseData: [], allTransferData: [transfer], creditCardNames: []
        )
        XCTAssertEqual(calculator.totalAssets(upTo: Date.distantFuture), 10000)
    }

    // MARK: - 別帳簿の資産が混ざらない

    func testAssetsFromOtherBooksDoNotMix() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let mainIncome = QARegressionTestFactory.makeIncome(amount: 10000, receiveMethod: "現金", category: "給料", bookId: main.book.id)
        let businessIncome = QARegressionTestFactory.makeIncome(amount: 99999, receiveMethod: "現金", category: "給料", bookId: business.book.id)

        let mainCalculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [mainIncome], allExpenseData: [], allTransferData: [], creditCardNames: []
        )
        let mainSummaries = mainCalculator.paymentMethodSummaries(for: [main.cash], upTo: Date.distantFuture)
        XCTAssertEqual(mainSummaries.first?.balance, 10000)

        _ = businessIncome // 事業用帳簿のデータはmainCalculatorに一切渡していない = 混ざりようがないことの確認
    }

    // MARK: - 最重要ケース
    //
    // メイン帳簿: 現金・初期残高10,000円・資産に含めるON・食費支出100円
    // 事業用帳簿: 現金・初期残高10,000円・資産に含めるOFF・食費支出200円
    // 期待: メイン帳簿の総資産には現金が入る / 事業用帳簿の総資産には現金が入らない / 同名の現金設定が混ざらない

    func testCriticalAssetIsolationScenario() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var mainCash = main.cash
        mainCash.isAsset = true
        PaymentMethodSettingDataSync.update(mainCash)
        var businessCash = business.cash
        businessCash.isAsset = false
        PaymentMethodSettingDataSync.update(businessCash)

        let mainInitialIncome = QARegressionTestFactory.makeIncome(amount: 10000, receiveMethod: "現金", category: "初期残高", bookId: main.book.id)
        let mainExpense = QARegressionTestFactory.makeExpense(amount: 100, paymentMethod: "現金", category: "食費", bookId: main.book.id)

        let businessInitialIncome = QARegressionTestFactory.makeIncome(amount: 10000, receiveMethod: "現金", category: "初期残高", bookId: business.book.id)
        let businessExpense = QARegressionTestFactory.makeExpense(amount: 200, paymentMethod: "現金", category: "食費", bookId: business.book.id)

        // --- メイン帳簿の資産計算(帳簿スコープされたデータのみ渡す) ---
        let mainMethodAssets = [mainCash].filter { $0.isAsset && $0.isActive }
        XCTAssertEqual(mainMethodAssets.map(\.id), [mainCash.id])

        let mainCalculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [mainInitialIncome], allExpenseData: [mainExpense], allTransferData: [], creditCardNames: []
        )
        let mainSummaries = mainCalculator.paymentMethodSummaries(for: mainMethodAssets, upTo: Date.distantFuture)
        XCTAssertEqual(mainSummaries.count, 1)
        XCTAssertEqual(mainSummaries.first?.balance, 9900) // 10000 - 100

        // --- 事業用帳簿の資産計算 ---
        let businessMethodAssets = [businessCash].filter { $0.isAsset && $0.isActive }
        XCTAssertTrue(businessMethodAssets.isEmpty) // 資産に含めるOFFなので対象外

        let businessCalculator = BankAccountBalanceCalculator(
            bankAccounts: [], allIncomeData: [businessInitialIncome], allExpenseData: [businessExpense], allTransferData: [], creditCardNames: []
        )
        let businessSummaries = businessCalculator.paymentMethodSummaries(for: businessMethodAssets, upTo: Date.distantFuture)
        XCTAssertTrue(businessSummaries.isEmpty)

        // --- 同名の現金設定が混ざらないことの確認 ---
        XCTAssertNotEqual(mainCash.id, businessCash.id)
        XCTAssertEqual(mainCash.methodName, businessCash.methodName)
        XCTAssertTrue(mainCash.isAsset)
        XCTAssertFalse(businessCash.isAsset)
    }
}
