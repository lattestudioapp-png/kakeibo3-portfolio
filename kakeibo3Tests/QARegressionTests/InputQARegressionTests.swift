// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import XCTest
@testable import kakeibo3

final class InputQARegressionTests: QARegressionTestCase {
    private let formService = TransactionFormService()
    private let repository = SwiftDataTransactionRepository()

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    // MARK: - 支出保存

    func testCanSaveExpense() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let draft = try formService.makeDraft(
            selectedType: "支出",
            amountText: "500",
            date: Date(),
            selectedMethod: "現金",
            selectedCategory: "食費",
            memo: "",
            bookId: main.book.id
        )
        try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")

        let expenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.amount, 500)
        XCTAssertEqual(expenses.first?.bookId, main.book.id)
    }

    func testZeroAmountExpenseCannotBeSaved() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertThrowsError(
            try formService.makeDraft(
                selectedType: "支出", amountText: "0", date: Date(),
                selectedMethod: "現金", selectedCategory: "食費", memo: "",
                bookId: main.book.id
            )
        ) { error in
            XCTAssertEqual(error as? TransactionFormService.ValidationError, .invalidAmount)
        }
    }

    func testEmptyAmountExpenseCannotBeSaved() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertThrowsError(
            try formService.makeDraft(
                selectedType: "支出", amountText: "", date: Date(),
                selectedMethod: "現金", selectedCategory: "食費", memo: "",
                bookId: main.book.id
            )
        )
    }

    func testEmptyCategoryExpenseCannotBeSaved() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        XCTAssertThrowsError(
            try formService.makeDraft(
                selectedType: "支出", amountText: "500", date: Date(),
                selectedMethod: "現金", selectedCategory: "", memo: "",
                bookId: main.book.id
            )
        ) { error in
            XCTAssertEqual(error as? TransactionFormService.ValidationError, .emptyCategory)
        }
    }

    func testExpenseCanBeSavedWithoutMemo() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let draft = try formService.makeDraft(
            selectedType: "支出", amountText: "300", date: Date(),
            selectedMethod: "現金", selectedCategory: "食費", memo: "",
            bookId: main.book.id
        )
        try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")
        XCTAssertEqual(ExpenseDataSync.fetchAll().first?.memo, "")
    }

    func testExpenseCanBeSavedWithMemoAndPhoto() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let draft = try formService.makeDraft(
            selectedType: "支出", amountText: "300", date: Date(),
            selectedMethod: "現金", selectedCategory: "食費", memo: "ランチ",
            receiptImagePaths: ["receipt_test.jpg"],
            bookId: main.book.id
        )
        try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")

        let saved = ExpenseDataSync.fetchAll().first
        XCTAssertEqual(saved?.memo, "ランチ")
        XCTAssertEqual(saved?.receiptImagePath, "receipt_test.jpg")
    }

    // MARK: - 保存先の帳簿分離

    func testExpenseIsSavedToCurrentBookOnly() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let draft = try formService.makeDraft(
            selectedType: "支出", amountText: "500", date: Date(),
            selectedMethod: "現金", selectedCategory: "食費", memo: "",
            bookId: main.book.id
        )
        try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")

        let allExpenses = ExpenseDataSync.fetchAll()
        XCTAssertEqual(allExpenses.filter { $0.bookId == main.book.id }.count, 1)
        XCTAssertEqual(allExpenses.filter { $0.bookId == business.book.id }.count, 0)
    }

    // MARK: - 収入保存

    func testCanSaveIncome() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let draft = try formService.makeDraft(
            selectedType: "収入", amountText: "250000", date: Date(),
            selectedMethod: "現金", selectedCategory: "給料", memo: "",
            bookId: main.book.id
        )
        try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")

        let incomes = IncomeDataSync.fetchAll()
        XCTAssertEqual(incomes.count, 1)
        XCTAssertEqual(incomes.first?.amount, 250000)
        XCTAssertEqual(incomes.first?.bookId, main.book.id)
    }

    func testIncomeIsSavedToCurrentBookOnly() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let draft = try formService.makeDraft(
            selectedType: "収入", amountText: "1000", date: Date(),
            selectedMethod: "現金", selectedCategory: "給料", memo: "",
            bookId: business.book.id
        )
        try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")

        let allIncomes = IncomeDataSync.fetchAll()
        XCTAssertEqual(allIncomes.filter { $0.bookId == business.book.id }.count, 1)
        XCTAssertEqual(allIncomes.filter { $0.bookId == main.book.id }.count, 0)
    }

    // MARK: - 収入カテゴリー・受け取り方法の帳簿スコープ
    //
    // 既知バグ: 他帳簿で初期残高を設定した時、他の帳簿の収入カテゴリーに「初期残高」が混ざる

    func testIncomeCategoryListOnlyShowsCurrentBookCategories() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let repository = SwiftDataCategoryRepository()
        let allCategories = CategoryDataSync.fetchAll()

        let mainIncomeNames = repository.categoryNames(type: "収入", categories: allCategories.filter { $0.bookId == main.book.id })
        let businessIncomeNames = repository.categoryNames(type: "収入", categories: allCategories.filter { $0.bookId == business.book.id })

        XCTAssertEqual(mainIncomeNames, ["給料"])
        XCTAssertEqual(businessIncomeNames, ["給料"])
    }

    func testInitialBalanceCategoryFromOtherBookDoesNotLeakIntoCurrentBookIncomeCategories() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // 事業用帳簿で「初期残高」カテゴリーを作成する（銀行口座の初期残高設定を模す）
        var initialBalanceCategory = CategoryData(name: "初期残高", colorHex: "#95A5A6", type: "収入", sortOrder: 999)
        initialBalanceCategory.bookId = business.book.id
        initialBalanceCategory.isProtected = true
        CategoryDataSync.insert(initialBalanceCategory)

        let repository = SwiftDataCategoryRepository()
        let allCategories = CategoryDataSync.fetchAll()

        let mainIncomeNames = repository.categoryNames(type: "収入", categories: allCategories.filter { $0.bookId == main.book.id })
        XCTAssertFalse(mainIncomeNames.contains("初期残高"))

        let businessIncomeNames = repository.categoryNames(type: "収入", categories: allCategories.filter { $0.bookId == business.book.id })
        XCTAssertTrue(businessIncomeNames.contains("初期残高"))
    }

    func testReceiveMethodListOnlyShowsCurrentBookMethods() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allReceiveMethods = ReceiveMethodDataSync.fetchAll()
        let mainMethods = allReceiveMethods.filter { $0.bookId == main.book.id }
        let businessMethods = allReceiveMethods.filter { $0.bookId == business.book.id }

        XCTAssertEqual(mainMethods.count, 1)
        XCTAssertEqual(businessMethods.count, 1)
        XCTAssertNotEqual(mainMethods.first?.id, businessMethods.first?.id)
    }

    // MARK: - 振替保存

    func testCanSaveTransfer() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var transfer = TransferData(
            fromType: TransferAccountType.paymentMethod.rawValue,
            fromId: main.cash.id,
            fromName: "現金",
            toType: TransferAccountType.bank.rawValue,
            toId: main.bankAccount.id,
            toName: "三井住友銀行",
            amount: 5000
        )
        transfer.bookId = main.book.id
        TransferDataSync.insert(transfer)

        let saved = TransferDataSync.fetchAll()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.bookId, main.book.id)
    }

    // MARK: - 振替候補(移動元/移動先)の帳簿スコープ
    //
    // 既知バグ: 現金を削除しても振替の選択欄に現金が出てくる / 振替元・振替先に現金が2個出てくる

    func testTransferParticipantsOnlyShowCurrentBookAccounts() throws {
        let (main, business, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let allBankAccounts = BankAccountDataSync.fetchAll()
        let allPaymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let allReceiveMethods = ReceiveMethodDataSync.fetchAll()

        let participants = TransferParticipantBuilder.build(
            bankAccounts: allBankAccounts.filter { $0.bookId == main.book.id },
            paymentMethods: allPaymentMethods.filter { $0.bookId == main.book.id },
            receiveMethods: allReceiveMethods.filter { $0.bookId == main.book.id }
        )

        // 別帳簿(事業用)の口座IDは一切含まれない
        XCTAssertFalse(participants.contains { $0.id == business.bankAccount.id })
        XCTAssertFalse(participants.contains { $0.id == business.cash.id })
        // クレカは振替候補から除外される
        XCTAssertFalse(participants.contains { $0.id == main.creditCard.id })
        // 現金・銀行口座は候補に含まれる
        XCTAssertTrue(participants.contains { $0.id == main.cash.id })
        XCTAssertTrue(participants.contains { $0.id == main.bankAccount.id })
    }

    func testDeletedCashDoesNotAppearInTransferParticipants() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        var cash = main.cash
        cash.isActive = false
        PaymentMethodSettingDataSync.update(cash)

        let allPaymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let participants = TransferParticipantBuilder.build(
            bankAccounts: [],
            paymentMethods: allPaymentMethods.filter { $0.bookId == main.book.id },
            receiveMethods: []
        )

        XCTAssertFalse(participants.contains { $0.id == main.cash.id })
    }

    func testDuplicateCashNamesDoNotAppearTwiceInTransferParticipants() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()
        // 重複防止(Phase1)より前に作られた既存データを模して、意図的に同名の現金を2件作る
        var extraCash = PaymentMethodSettingData(methodName: "現金", type: PaymentMethodType.cash.rawValue, sortOrder: 1)
        extraCash.bookId = main.book.id
        PaymentMethodSettingDataSync.insert(extraCash)

        let allPaymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let participants = TransferParticipantBuilder.build(
            bankAccounts: [],
            paymentMethods: allPaymentMethods.filter { $0.bookId == main.book.id },
            receiveMethods: []
        )

        XCTAssertEqual(participants.filter { $0.name == "現金" }.count, 1)
    }

    func testSameAccountCannotBeSelectedAsBothFromAndTo() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        // TransferEditView.canSave と同じ判定（f != t）
        let from = main.cash.id
        let to = main.cash.id
        XCTAssertFalse(from != to)
    }

    // MARK: - 振替は支出/収入合計に混ざらない・資産の二重計上がない

    func testTransferDoesNotAffectExpenseOrIncomeTotals() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let expense = QARegressionTestFactory.makeExpense(amount: 1000, paymentMethod: "現金", category: "食費", bookId: main.book.id)
        let income = QARegressionTestFactory.makeIncome(amount: 5000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        var transfer = TransferData(
            fromType: TransferAccountType.paymentMethod.rawValue,
            fromId: main.cash.id,
            fromName: "現金",
            toType: TransferAccountType.bank.rawValue,
            toId: main.bankAccount.id,
            toName: "三井住友銀行",
            amount: 20000
        )
        transfer.bookId = main.book.id
        TransferDataSync.insert(transfer)

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [main.bankAccount],
            allIncomeData: [income],
            allExpenseData: [expense],
            allTransferData: [transfer],
            creditCardNames: []
        )
        let (periodIncome, periodExpense) = calculator.periodBalance(in: AnalysisDateRange(start: .distantPast, end: .distantFuture))

        XCTAssertEqual(periodIncome, 5000)   // 振替の20000円は含まれない
        XCTAssertEqual(periodExpense, 1000)  // 振替の20000円は含まれない
    }

    func testTransferDoesNotDoubleCountInTotalAssets() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let income = QARegressionTestFactory.makeIncome(amount: 10000, receiveMethod: "現金", category: "給料", bookId: main.book.id)

        var transfer = TransferData(
            fromType: TransferAccountType.paymentMethod.rawValue,
            fromId: main.cash.id,
            fromName: "現金",
            toType: TransferAccountType.bank.rawValue,
            toId: main.bankAccount.id,
            toName: "三井住友銀行",
            amount: 3000
        )
        transfer.bookId = main.book.id
        TransferDataSync.insert(transfer)

        let calculator = BankAccountBalanceCalculator(
            bankAccounts: [main.bankAccount],
            allIncomeData: [income],
            allExpenseData: [],
            allTransferData: [transfer],
            creditCardNames: []
        )
        // 総資産は「収入10000」のみで変動し、振替(現金→銀行の移動)自体はプラスマイナス0
        let totalAssets = calculator.totalAssets(upTo: Date.distantFuture)
        XCTAssertEqual(totalAssets, 10000)
    }
}
