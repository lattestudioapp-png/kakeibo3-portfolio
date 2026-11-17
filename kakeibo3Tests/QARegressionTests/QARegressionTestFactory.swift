// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。

import Foundation
import CoreData
import XCTest
@testable import kakeibo3

// MARK: - QA回帰テスト基底クラス
//
// BookMigrationService / AccountingMonthCalculator / AnalysisCategoryFilterSettings など、
// 本番コードの一部は UserDefaults.standard を直接読み書きする（依存注入されていない）。
// テストが実データ用のUserDefaultsを汚染しないよう、全QARegressionTestsはこの基底クラスを
// 継承し、各テストの前後でUserDefaults.standardの内容を丸ごとスナップショット/復元する。
//
// Core Data移行（Phase 1）：`*DataSync`系は`CoreDataStack.shared`を直接参照するため、
// 各テストの前でsharedをin-memoryの新しいインスタンスに差し替えることで、
// SwiftData時代の`makeInMemoryContainer()`と同じ「テストごとに独立したまっさらな状態」を
// 実現する。個々のテストファイルが意識する必要はない。
class QARegressionTestCase: XCTestCase {
    private var userDefaultsSnapshot: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaultsSnapshot = UserDefaults.standard.dictionaryRepresentation()
        CoreDataStack.shared = CoreDataStack(inMemory: true)
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        let currentKeys = Set(defaults.dictionaryRepresentation().keys)
        let snapshotKeys = Set(userDefaultsSnapshot.keys)
        for key in currentKeys.subtracting(snapshotKeys) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in userDefaultsSnapshot {
            defaults.set(value, forKey: key)
        }
        try super.tearDownWithError()
    }
}

// MARK: - QA回帰テスト共通ファクトリ
//
// 複数帳簿の完全分離を検証するための共通テストデータ生成ヘルパー。
// 「メイン帳簿・事業用帳簿・旅行用帳簿」の3帳簿に、同名データ
// （支出カテゴリー:食費 / 収入カテゴリー:給料 / 支払い方法:現金 / 受け取り方法:現金 /
//   銀行口座:三井住友銀行 / 電子マネー:PayPay / クレジットカード:テストカード）を
// それぞれ作成し、bookIdでしか区別できない状態を毎回作り出す。
//
// 本番コードは一切変更せず、既存のモデル初期化子・Service/Repository層をそのまま呼び出す。

enum QARegressionTestFactory {

    // MARK: - 帳簿

    @discardableResult
    static func makeBook(
        name: String,
        isMain: Bool = false,
        sortOrder: Int = 0
    ) -> BookData {
        let book = BookData(name: name, sortOrder: sortOrder, isMain: isMain)
        BookDataSync.insert(book)
        return book
    }

    // MARK: - async文脈向け（CoreDataStack.performAndSaveのスレッド閉じ込め違反の再現・回帰テスト用）
    //
    // 元のバグ: 本来はメインスレッド/MainActorから呼ばれる前提だった*DataSync.insertが、
    // async testメソッド（await復帰後の再開スレッドがSwift Concurrencyの規約上保証されない）
    // から間接的に呼ばれ、CoreDataStack.performAndSave(sync)がviewContextを未保護のまま直接
    // 触っていたためCore Data内部（NSSet相当の変更通知管理）を破壊していた
    // （testAssetGraphCacheRebuildsSuccessfullyが低確率でクラッシュしていた原因）。
    // CoreDataStack.performAndSave(_:)が内部でperformAndWaitを使うようになったことで
    // 上のsync版（makeBook/seedStandardData）も既に安全だが、こちらはasync文脈から
    // cooperativeスレッドプールを塞がずに書き込みたい場合の非同期API経路そのものを
    // 反復再現テストで踏むためのもの（CoreDataConcurrencyStressTests参照）。

    @discardableResult
    static func makeBookAsync(
        name: String,
        isMain: Bool = false,
        sortOrder: Int = 0
    ) async throws -> BookData {
        let book = BookData(name: name, sortOrder: sortOrder, isMain: isMain)
        try await BookDataSync.insertAsync(book)
        return book
    }

    // MARK: - 同名データ一式

    /// 1帳簿ぶんの「食費/給料/現金/PayPay/テストカード/現金(受け取り)/三井住友銀行」を作成する。
    struct BookFixture {
        let book: BookData
        let expenseCategory: CategoryData
        let incomeCategory: CategoryData
        let cash: PaymentMethodSettingData
        let electronicMoney: PaymentMethodSettingData
        let creditCard: PaymentMethodSettingData
        let receiveMethod: ReceiveMethodData
        let bankAccount: BankAccountData
    }

    @discardableResult
    static func seedStandardData(book: BookData) -> BookFixture {
        var expenseCategory = CategoryData(name: "食費", colorHex: "#6FA58C", type: "支出", sortOrder: 0)
        expenseCategory.bookId = book.id
        CategoryDataSync.insert(expenseCategory)

        var incomeCategory = CategoryData(name: "給料", colorHex: "#5A9ED8", type: "収入", sortOrder: 0)
        incomeCategory.bookId = book.id
        CategoryDataSync.insert(incomeCategory)

        var cash = PaymentMethodSettingData(methodName: "現金", type: PaymentMethodType.cash.rawValue)
        cash.bookId = book.id
        cash.isAsset = true
        cash.useForReceive = true
        PaymentMethodSettingDataSync.insert(cash)

        var electronicMoney = PaymentMethodSettingData(methodName: "PayPay", type: PaymentMethodType.electronicMoney.rawValue)
        electronicMoney.bookId = book.id
        electronicMoney.isAsset = true
        PaymentMethodSettingDataSync.insert(electronicMoney)

        var creditCard = PaymentMethodSettingData(
            methodName: "テストカード",
            type: PaymentMethodType.creditCard.rawValue,
            closingDay: 15,
            withdrawalDay: 10
        )
        creditCard.bookId = book.id
        PaymentMethodSettingDataSync.insert(creditCard)

        var receiveMethod = ReceiveMethodData(methodName: "現金")
        receiveMethod.bookId = book.id
        ReceiveMethodDataSync.insert(receiveMethod)

        var bankAccount = BankAccountData(accountName: "三井住友銀行")
        bankAccount.bookId = book.id
        BankAccountDataSync.insert(bankAccount)

        return BookFixture(
            book: book,
            expenseCategory: expenseCategory,
            incomeCategory: incomeCategory,
            cash: cash,
            electronicMoney: electronicMoney,
            creditCard: creditCard,
            receiveMethod: receiveMethod,
            bankAccount: bankAccount
        )
    }

    /// seedStandardData(book:)のasync版。書き込み順序・作成データはsync版と完全に同一で、
    /// 経路だけが*Async系（async throws、context.perform経由）になる。
    @discardableResult
    static func seedStandardDataAsync(book: BookData) async throws -> BookFixture {
        var expenseCategory = CategoryData(name: "食費", colorHex: "#6FA58C", type: "支出", sortOrder: 0)
        expenseCategory.bookId = book.id
        try await CategoryDataSync.insertAsync(expenseCategory)

        var incomeCategory = CategoryData(name: "給料", colorHex: "#5A9ED8", type: "収入", sortOrder: 0)
        incomeCategory.bookId = book.id
        try await CategoryDataSync.insertAsync(incomeCategory)

        var cash = PaymentMethodSettingData(methodName: "現金", type: PaymentMethodType.cash.rawValue)
        cash.bookId = book.id
        cash.isAsset = true
        cash.useForReceive = true
        try await PaymentMethodSettingDataSync.insertAsync(cash)

        var electronicMoney = PaymentMethodSettingData(methodName: "PayPay", type: PaymentMethodType.electronicMoney.rawValue)
        electronicMoney.bookId = book.id
        electronicMoney.isAsset = true
        try await PaymentMethodSettingDataSync.insertAsync(electronicMoney)

        var creditCard = PaymentMethodSettingData(
            methodName: "テストカード",
            type: PaymentMethodType.creditCard.rawValue,
            closingDay: 15,
            withdrawalDay: 10
        )
        creditCard.bookId = book.id
        try await PaymentMethodSettingDataSync.insertAsync(creditCard)

        var receiveMethod = ReceiveMethodData(methodName: "現金")
        receiveMethod.bookId = book.id
        try await ReceiveMethodDataSync.insertAsync(receiveMethod)

        var bankAccount = BankAccountData(accountName: "三井住友銀行")
        bankAccount.bookId = book.id
        try await BankAccountDataSync.insertAsync(bankAccount)

        return BookFixture(
            book: book,
            expenseCategory: expenseCategory,
            incomeCategory: incomeCategory,
            cash: cash,
            electronicMoney: electronicMoney,
            creditCard: creditCard,
            receiveMethod: receiveMethod,
            bankAccount: bankAccount
        )
    }

    /// メイン帳簿・事業用帳簿・旅行用帳簿の3帳簿を作成し、それぞれに同名データを仕込む。
    static func makeThreeStandardBooks() -> (main: BookFixture, business: BookFixture, travel: BookFixture) {
        let mainBook = makeBook(name: "メイン帳簿", isMain: true, sortOrder: 0)
        let businessBook = makeBook(name: "事業用帳簿", isMain: false, sortOrder: 1)
        let travelBook = makeBook(name: "旅行用帳簿", isMain: false, sortOrder: 2)

        return (
            main: seedStandardData(book: mainBook),
            business: seedStandardData(book: businessBook),
            travel: seedStandardData(book: travelBook)
        )
    }

    // MARK: - 取引ヘルパー

    @discardableResult
    static func makeExpense(
        amount: Int,
        date: Date = Date(),
        paymentMethod: String,
        category: String,
        memo: String = "",
        bookId: UUID?
    ) -> ExpenseData {
        var expense = ExpenseData(amount: amount, date: date, paymentMethod: paymentMethod, category: category, memo: memo)
        expense.bookId = bookId
        ExpenseDataSync.insert(expense)
        return expense
    }

    @discardableResult
    static func makeIncome(
        amount: Int,
        date: Date = Date(),
        receiveMethod: String,
        category: String,
        memo: String = "",
        bookId: UUID?
    ) -> IncomeData {
        var income = IncomeData(amount: amount, date: date, receiveMethod: receiveMethod, category: category, memo: memo)
        income.bookId = bookId
        IncomeDataSync.insert(income)
        return income
    }

    // MARK: - 取引ヘルパー（async文脈向け）

    @discardableResult
    static func makeExpenseAsync(
        amount: Int,
        date: Date = Date(),
        paymentMethod: String,
        category: String,
        memo: String = "",
        bookId: UUID?
    ) async throws -> ExpenseData {
        var expense = ExpenseData(amount: amount, date: date, paymentMethod: paymentMethod, category: category, memo: memo)
        expense.bookId = bookId
        try await ExpenseDataSync.insertAsync(expense)
        return expense
    }

    @discardableResult
    static func makeIncomeAsync(
        amount: Int,
        date: Date = Date(),
        receiveMethod: String,
        category: String,
        memo: String = "",
        bookId: UUID?
    ) async throws -> IncomeData {
        var income = IncomeData(amount: amount, date: date, receiveMethod: receiveMethod, category: category, memo: memo)
        income.bookId = bookId
        try await IncomeDataSync.insertAsync(income)
        return income
    }
}
