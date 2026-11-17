import XCTest
import SwiftData
import CoreData
@testable import kakeibo3

// MARK: - Phase B1: 一時Core Dataストアへの書き込み・UUID検証の回帰テスト
//
// この段階ではCoreDataStack.shared / 本番昇格 / 旧ストア退避 / UserDefaultsフラグ /
// Kakeibo3App接続のいずれも行わない。MigrationBootstrap.migrate(legacyPaths:workDirectory:)が
// 返すMigrationOutcomeだけを検証する。

final class MigrationBootstrapB1Tests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationBootstrapB1Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - テスト用旧ストア構築ヘルパー

    @discardableResult
    private func makeLegacyStore(
        name: String = "legacy",
        _ build: (ModelContext) -> Void
    ) throws -> SwiftDataLegacyReader.LegacyStorePaths {
        let dir = workDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("default.store")
        let schema = Schema(LegacySchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        build(context)
        try context.save()
        return SwiftDataLegacyReader.LegacyStorePaths(
            store: storeURL,
            wal: dir.appendingPathComponent("default.store-wal"),
            shm: dir.appendingPathComponent("default.store-shm")
        )
    }

    private func makeBook(_ context: ModelContext, name: String, isMain: Bool = true, sortOrder: Int = 0) -> LegacyBookData {
        let book = LegacyBookData()
        book.id = UUID()
        book.name = name
        book.isMain = isMain
        book.sortOrder = sortOrder
        context.insert(book)
        return book
    }

    private func makeCash(_ context: ModelContext, bookId: UUID, name: String = "現金") -> LegacyPaymentMethodSettingData {
        let cash = LegacyPaymentMethodSettingData()
        cash.id = UUID()
        cash.methodName = name
        cash.type = "cash"
        cash.bookId = bookId
        context.insert(cash)
        return cash
    }

    private func runMigration(_ paths: SwiftDataLegacyReader.LegacyStorePaths) -> MigrationOutcome {
        MigrationBootstrap.migrate(legacyPaths: paths, workDirectory: workDirectory)
    }

    private func requireSuccess(_ outcome: MigrationOutcome, file: StaticString = #filePath, line: UInt = #line) -> (MigrationManifest, [MigrationReferenceIssue], URL) {
        guard case let .tempStoreWriteSucceeded(manifest, warnings, tempStoreURL) = outcome else {
            XCTFail("移行が成功するはずが失敗した: \(outcome)", file: file, line: line)
            return (MigrationManifest(migrationVersion: 0, completedAt: .distantPast, sourceStoreFileSize: 0, sourceStoreModifiedAt: .distantPast, sourceBookIDs: [], entityCounts: [:], regeneratedModelSourceCounts: [:], bookSummaries: [], targetStoreIdentifier: nil), [], workDirectory)
        }
        return (manifest, warnings, tempStoreURL)
    }

    private func fetchAll(_ entityName: String, from url: URL) throws -> [NSManagedObject] {
        let stack = CoreDataStack(storeURL: url)
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try stack.container.viewContext.fetch(request)
    }

    // MARK: - 1. 全Entityの属性移行

    func testAllEntitiesMigrateAttributes() throws {
        var bookId: UUID!
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            bookId = book.id

            let category = LegacyCategoryData()
            category.id = UUID(); category.name = "食費"; category.colorHex = "#FF0000"; category.type = "支出"; category.bookId = bookId
            context.insert(category)

            let expense = LegacyExpenseData()
            expense.id = UUID(); expense.amount = 500; expense.category = "食費"; expense.paymentMethod = "現金"; expense.bookId = bookId
            context.insert(expense)

            let income = LegacyIncomeData()
            income.id = UUID(); income.amount = 300000; income.category = "給料"; income.receiveMethod = "現金"; income.bookId = bookId
            context.insert(income)

            let cash = self.makeCash(context, bookId: bookId)
            let cash2 = self.makeCash(context, bookId: bookId, name: "現金受取")

            let transfer = LegacyTransferData()
            transfer.id = UUID(); transfer.fromType = "payment"; transfer.fromId = cash.id; transfer.fromName = "現金"
            transfer.toType = "payment"; transfer.toId = cash2.id; transfer.toName = "現金受取"; transfer.amount = 1000; transfer.bookId = bookId
            context.insert(transfer)

            let account = LegacyBankAccountData()
            account.id = UUID(); account.accountName = "普通預金"; account.bookId = bookId
            context.insert(account)

            let receiveMethod = LegacyReceiveMethodData()
            receiveMethod.id = UUID(); receiveMethod.methodName = "口座振込"; receiveMethod.bookId = bookId
            context.insert(receiveMethod)

            let budget = LegacyBudgetData()
            budget.id = UUID(); budget.year = 2026; budget.month = 7; budget.categoryName = "食費"; budget.amount = 30000; budget.bookId = bookId
            context.insert(budget)

            let recurringBudget = LegacyRecurringBudgetData()
            recurringBudget.id = UUID(); recurringBudget.categoryName = "食費"; recurringBudget.amount = 30000; recurringBudget.bookId = bookId
            context.insert(recurringBudget)

            let fixedExpense = LegacyFixedExpenseData()
            fixedExpense.id = UUID(); fixedExpense.name = "家賃"; fixedExpense.amount = 80000; fixedExpense.bookId = bookId
            context.insert(fixedExpense)

            let recurringIncome = LegacyRecurringIncomeData()
            recurringIncome.id = UUID(); recurringIncome.name = "給料"; recurringIncome.amount = 300000; recurringIncome.bookId = bookId
            context.insert(recurringIncome)

            let recurringTransfer = LegacyRecurringTransferSettingData()
            recurringTransfer.id = UUID(); recurringTransfer.fromMethodId = cash.id; recurringTransfer.fromMethodName = "現金"
            recurringTransfer.fromType = "payment"; recurringTransfer.toMethodId = cash2.id; recurringTransfer.toMethodName = "現金受取"
            recurringTransfer.toType = "payment"; recurringTransfer.amount = 1000; recurringTransfer.day = 1; recurringTransfer.bookId = bookId
            context.insert(recurringTransfer)
        }

        let outcome = runMigration(paths)
        let (manifest, warnings, _) = requireSuccess(outcome)

        XCTAssertEqual(warnings.count, 0)
        for entityName in MigrationVerifier.migratedEntityNames {
            XCTAssertEqual(manifest.entityCounts[entityName], entityName == "BookData" ? 1 : (entityName == "PaymentMethodSettingData" ? 2 : 1), "\(entityName)の件数が想定と違う")
        }
    }

    // MARK: - 2. UUID維持 / 3. bookId維持

    func testUUIDAndBookIdArePreserved() throws {
        let fixedBookId = UUID()
        let fixedExpenseId = UUID()
        let paths = try makeLegacyStore { context in
            let book = LegacyBookData()
            book.id = fixedBookId; book.name = "帳簿A"; book.isMain = true
            context.insert(book)

            let expense = LegacyExpenseData()
            expense.id = fixedExpenseId; expense.amount = 100; expense.category = "食費"; expense.paymentMethod = "現金"; expense.bookId = fixedBookId
            context.insert(expense)
        }

        let outcome = runMigration(paths)
        let (_, _, tempStoreURL) = requireSuccess(outcome)

        let expenses = try fetchAll("ExpenseData", from: tempStoreURL)
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.value(forKey: "id") as? UUID, fixedExpenseId)
        XCTAssertEqual(expenses.first?.value(forKey: "bookId") as? UUID, fixedBookId)
    }

    // MARK: - 4. 単一帳簿 / 5. 複数帳簿

    func testSingleBookMigrationSucceeds() throws {
        let paths = try makeLegacyStore { context in
            self.makeBook(context, name: "帳簿A")
        }
        let outcome = runMigration(paths)
        let (manifest, _, _) = requireSuccess(outcome)
        XCTAssertEqual(manifest.sourceBookIDs.count, 1)
    }

    func testMultipleBookMigrationSucceeds() throws {
        var bookAId: UUID!
        var bookBId: UUID!
        let paths = try makeLegacyStore { context in
            let bookA = self.makeBook(context, name: "帳簿A", isMain: true, sortOrder: 0)
            let bookB = self.makeBook(context, name: "帳簿B", isMain: false, sortOrder: 1)
            bookAId = bookA.id
            bookBId = bookB.id

            let expenseA = LegacyExpenseData()
            expenseA.id = UUID(); expenseA.amount = 1000; expenseA.category = "食費"; expenseA.paymentMethod = "現金"; expenseA.bookId = bookAId
            context.insert(expenseA)

            let expenseB = LegacyExpenseData()
            expenseB.id = UUID(); expenseB.amount = 2000; expenseB.category = "食費"; expenseB.paymentMethod = "現金"; expenseB.bookId = bookBId
            context.insert(expenseB)
        }

        let outcome = runMigration(paths)
        let (manifest, _, _) = requireSuccess(outcome)
        XCTAssertEqual(manifest.sourceBookIDs.count, 2)
        XCTAssertEqual(manifest.entityCounts["ExpenseData"], 2)

        let summaryA = manifest.bookSummaries.first { $0.bookId == bookAId }
        let summaryB = manifest.bookSummaries.first { $0.bookId == bookBId }
        XCTAssertEqual(summaryA?.expenseTotal, 1000)
        XCTAssertEqual(summaryB?.expenseTotal, 2000)
    }

    // MARK: - 6. 同名カテゴリーの帳簿分離 / 18. 名前一致による補完が行われない

    func testSameNameCategoryAcrossBooksStaysSeparated() throws {
        var bookAId: UUID!
        var bookBId: UUID!
        let paths = try makeLegacyStore { context in
            let bookA = self.makeBook(context, name: "帳簿A")
            let bookB = self.makeBook(context, name: "帳簿B", isMain: false, sortOrder: 1)
            bookAId = bookA.id
            bookBId = bookB.id

            let categoryA = LegacyCategoryData()
            categoryA.id = UUID(); categoryA.name = "食費"; categoryA.colorHex = "#FF0000"; categoryA.type = "支出"; categoryA.bookId = bookAId
            context.insert(categoryA)

            let categoryB = LegacyCategoryData()
            categoryB.id = UUID(); categoryB.name = "食費"; categoryB.colorHex = "#00FF00"; categoryB.type = "支出"; categoryB.bookId = bookBId
            context.insert(categoryB)
        }

        let outcome = runMigration(paths)
        let (manifest, _, tempStoreURL) = requireSuccess(outcome)

        XCTAssertEqual(manifest.entityCounts["CategoryData"], 2, "同名でも名前で統合されず2件のまま残る")
        let categories = try fetchAll("CategoryData", from: tempStoreURL)
        let bookIds = Set(categories.compactMap { $0.value(forKey: "bookId") as? UUID })
        XCTAssertEqual(bookIds, [bookAId, bookBId])
    }

    // MARK: - 7. 同名支払い方法の帳簿分離

    func testSameNamePaymentMethodAcrossBooksStaysSeparated() throws {
        var bookAId: UUID!
        var bookBId: UUID!
        let paths = try makeLegacyStore { context in
            let bookA = self.makeBook(context, name: "帳簿A")
            let bookB = self.makeBook(context, name: "帳簿B", isMain: false, sortOrder: 1)
            bookAId = bookA.id
            bookBId = bookB.id
            self.makeCash(context, bookId: bookAId)
            self.makeCash(context, bookId: bookBId)
        }

        let outcome = runMigration(paths)
        let (manifest, _, _) = requireSuccess(outcome)
        XCTAssertEqual(manifest.entityCounts["PaymentMethodSettingData"], 2, "同名でも名前で統合されず2件のまま残る")
    }

    // MARK: - 8. TransferのfromId/toId検証

    func testTransferWithValidEndpointsSucceeds() throws {
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let cash = self.makeCash(context, bookId: book.id)
            let cash2 = self.makeCash(context, bookId: book.id, name: "現金受取")

            let transfer = LegacyTransferData()
            transfer.id = UUID(); transfer.fromType = "payment"; transfer.fromId = cash.id; transfer.fromName = "現金"
            transfer.toType = "payment"; transfer.toId = cash2.id; transfer.toName = "現金受取"; transfer.amount = 500; transfer.bookId = book.id
            context.insert(transfer)
        }

        let outcome = runMigration(paths)
        _ = requireSuccess(outcome)
    }

    func testTransferWithDanglingFromIdFailsMigration() throws {
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let cash2 = self.makeCash(context, bookId: book.id, name: "現金受取")

            let transfer = LegacyTransferData()
            transfer.id = UUID(); transfer.fromType = "payment"; transfer.fromId = UUID() // 実在しないID
            transfer.fromName = "現金"; transfer.toType = "payment"; transfer.toId = cash2.id
            transfer.toName = "現金受取"; transfer.amount = 500; transfer.bookId = book.id
            context.insert(transfer)
        }

        let outcome = runMigration(paths)
        guard case let .failed(.criticalReferenceIssues(issues)) = outcome else {
            return XCTFail("fromIdがダングリングしている振替は重大エラーで失敗するべき: \(outcome)")
        }
        XCTAssertTrue(issues.contains { $0.entity == "TransferData" && $0.field == "fromId" })
    }

    // MARK: - 9. ゴミ箱状態維持

    func testTrashStateIsPreserved() throws {
        let trashedAt = Date()
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let expense = LegacyExpenseData()
            expense.id = UUID(); expense.amount = 100; expense.category = "食費"; expense.paymentMethod = "現金"
            expense.bookId = book.id; expense.isInTrash = true; expense.trashedAt = trashedAt
            context.insert(expense)
        }

        let outcome = runMigration(paths)
        let (_, _, tempStoreURL) = requireSuccess(outcome)
        let expenses = try fetchAll("ExpenseData", from: tempStoreURL)
        XCTAssertEqual(expenses.first?.value(forKey: "isInTrash") as? Bool, true)
        XCTAssertNotNil(expenses.first?.value(forKey: "trashedAt") as? Date)
    }

    // MARK: - 10. 使用停止・保護・ロック状態維持

    func testSuspendedProtectedLockedStateIsPreserved() throws {
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")

            let category = LegacyCategoryData()
            category.id = UUID(); category.name = "初期残高"; category.colorHex = "#000000"; category.type = "収入"
            category.bookId = book.id; category.isSuspended = true; category.isProtected = true
            context.insert(category)

            let cash = self.makeCash(context, bookId: book.id)
            cash.isLocked = true
        }

        let outcome = runMigration(paths)
        let (_, _, tempStoreURL) = requireSuccess(outcome)

        let categories = try fetchAll("CategoryData", from: tempStoreURL)
        XCTAssertEqual(categories.first?.value(forKey: "isSuspended") as? Bool, true)
        XCTAssertEqual(categories.first?.value(forKey: "isProtected") as? Bool, true)

        let methods = try fetchAll("PaymentMethodSettingData", from: tempStoreURL)
        XCTAssertEqual(methods.first?.value(forKey: "isLocked") as? Bool, true)
    }

    // MARK: - 11. 休日調整情報維持

    func testHolidayAdjustmentIsPreserved() throws {
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let fixedExpense = LegacyFixedExpenseData()
            fixedExpense.id = UUID(); fixedExpense.name = "家賃"; fixedExpense.amount = 80000
            fixedExpense.bookId = book.id
            fixedExpense.holidayAdjustment = WeekendHolidayAdjustment.shiftEarlier.rawValue
            fixedExpense.generatedScheduleMonths = ["2026-6", "2026-7"]
            context.insert(fixedExpense)
        }

        let outcome = runMigration(paths)
        let (_, _, tempStoreURL) = requireSuccess(outcome)
        let fixedExpenses = try fetchAll("FixedExpenseData", from: tempStoreURL)
        XCTAssertEqual(fixedExpenses.first?.value(forKey: "holidayAdjustment") as? String, WeekendHolidayAdjustment.shiftEarlier.rawValue)
        let monthsData = fixedExpenses.first?.value(forKey: "generatedScheduleMonths") as? Data
        let months = monthsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        XCTAssertEqual(months, ["2026-6", "2026-7"])
    }

    // MARK: - 12. 写真参照維持

    func testReceiptImagePathIsPreserved() throws {
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let expense = LegacyExpenseData()
            expense.id = UUID(); expense.amount = 100; expense.category = "食費"; expense.paymentMethod = "現金"
            expense.bookId = book.id; expense.receiptImagePath = "receipt_001.jpg"
            context.insert(expense)
        }

        let outcome = runMigration(paths)
        let (_, _, tempStoreURL) = requireSuccess(outcome)
        let expenses = try fetchAll("ExpenseData", from: tempStoreURL)
        XCTAssertEqual(expenses.first?.value(forKey: "receiptImagePath") as? String, "receipt_001.jpg")
    }

    // MARK: - 13. 件数一致 / 14. 帳簿別支出・収入合計一致

    func testCountsAndPerBookTotalsMatch() throws {
        var bookId: UUID!
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            bookId = book.id
            for amount in [100, 200, 300] {
                let expense = LegacyExpenseData()
                expense.id = UUID(); expense.amount = amount; expense.category = "食費"; expense.paymentMethod = "現金"; expense.bookId = bookId
                context.insert(expense)
            }
            let income = LegacyIncomeData()
            income.id = UUID(); income.amount = 300000; income.category = "給料"; income.receiveMethod = "現金"; income.bookId = bookId
            context.insert(income)
        }

        let outcome = runMigration(paths)
        let (manifest, _, _) = requireSuccess(outcome)
        XCTAssertEqual(manifest.entityCounts["ExpenseData"], 3)
        XCTAssertEqual(manifest.entityCounts["IncomeData"], 1)
        let summary = manifest.bookSummaries.first { $0.bookId == bookId }
        XCTAssertEqual(summary?.expenseTotal, 600)
        XCTAssertEqual(summary?.incomeTotal, 300000)
    }

    // MARK: - 15. 一時ストア再オープン後も維持される

    func testDataSurvivesTempStoreReopen() throws {
        let expenseId = UUID()
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let expense = LegacyExpenseData()
            expense.id = expenseId; expense.amount = 999; expense.category = "食費"; expense.paymentMethod = "現金"; expense.bookId = book.id
            context.insert(expense)
        }

        let outcome = runMigration(paths)
        // MigrationBootstrap自身が内部で close→reopen→reverify を行い、成功した場合だけ
        // .tempStoreWriteSucceeded を返す。ここではさらに独立した3回目のオープンでも
        // データが残っていることを確認する。
        let (_, _, tempStoreURL) = requireSuccess(outcome)

        let expenses = try fetchAll("ExpenseData", from: tempStoreURL)
        XCTAssertEqual(expenses.first?.value(forKey: "id") as? UUID, expenseId)
        XCTAssertEqual(expenses.first?.value(forKey: "amount") as? Int64, 999)
    }

    // MARK: - 16. 重大なダングリング参照で失敗

    func testDanglingBookIdFailsMigration() throws {
        let paths = try makeLegacyStore { context in
            self.makeBook(context, name: "帳簿A")
            let expense = LegacyExpenseData()
            expense.id = UUID(); expense.amount = 100; expense.category = "食費"; expense.paymentMethod = "現金"
            expense.bookId = UUID() // 実在しない帳簿
            context.insert(expense)
        }

        let outcome = runMigration(paths)
        guard case let .failed(.criticalReferenceIssues(issues)) = outcome else {
            return XCTFail("実在しないbookIdは重大エラーで失敗するべき: \(outcome)")
        }
        XCTAssertTrue(issues.contains { $0.entity == "ExpenseData" && $0.field == "bookId" })
    }

    // MARK: - 17. optional参照欠落は警告で継続

    func testDanglingOptionalReferenceContinuesAsWarning() throws {
        let paths = try makeLegacyStore { context in
            let book = self.makeBook(context, name: "帳簿A")
            let expense = LegacyExpenseData()
            expense.id = UUID(); expense.amount = 100; expense.category = "食費"; expense.paymentMethod = "銀行口座"
            expense.bookId = book.id; expense.bankAccountId = UUID() // 実在しない口座(optional)
            context.insert(expense)
        }

        let outcome = runMigration(paths)
        let (_, warnings, _) = requireSuccess(outcome)
        XCTAssertTrue(warnings.contains { $0.entity == "ExpenseData" && $0.field == "bankAccountId" })
    }

    // MARK: - 19. 一時ストア生成失敗時に旧ストア無傷

    func testLegacyStoreUntouchedWhenTempStoreCreationFails() throws {
        let paths = try makeLegacyStore { context in
            self.makeBook(context, name: "帳簿A")
        }

        func checksum() throws -> [Data?] {
            [paths.store, paths.wal, paths.shm].map { url in
                FileManager.default.fileExists(atPath: url.path) ? try? Data(contentsOf: url) : nil
            }
        }
        let before = try checksum()

        // 書き込み不可なディレクトリ(存在しないパス)を一時ストアの作業ディレクトリに指定し、
        // 一時Core Dataストアの生成自体を失敗させる。
        let invalidWorkDirectory = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/deeper")
        let outcome = MigrationBootstrap.migrate(legacyPaths: paths, workDirectory: invalidWorkDirectory)

        guard case .failed = outcome else {
            return XCTFail("一時ストア生成に失敗するはずが成功した: \(outcome)")
        }

        let after = try checksum()
        XCTAssertEqual(before, after, "一時ストア生成失敗時も旧SwiftDataストアは無傷でなければならない")
    }
}
