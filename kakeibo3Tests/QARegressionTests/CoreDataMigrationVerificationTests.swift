// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// Core Data移行（手順4）のdual-write検証用。SwiftData側は各モデルごとに
// in-memoryコンテナで保存し、その直後にCore Data側（CoreDataStack.shared、実ディスク）を
// フェッチしてUUID・件数・主要項目が一致することを確認する。

import XCTest
import CoreData
@testable import kakeibo3

final class CoreDataMigrationVerificationTests: QARegressionTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        // super.setUpWithError()がCoreDataStack.sharedをin-memoryの新規インスタンスに
        // 差し替えるため、Core Data側も毎回まっさらな状態になる（手動削除は不要）。
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }

    func testExpenseDualWriteMatchesCoreData() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let formService = TransactionFormService()
        let repository = SwiftDataTransactionRepository()

        for amount in ["1000", "2500", "999"] {
            let draft = try formService.makeDraft(
                selectedType: "支出", amountText: amount, date: Date(),
                selectedMethod: "現金", selectedCategory: "食費", memo: "検証用",
                bookId: main.book.id
            )
            try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")
        }

        let swiftDataExpenses = ExpenseDataSync.fetchAll()
            .sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(swiftDataExpenses.count, 3, "件数")

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "ExpenseData")
        request.predicate = NSPredicate(format: "id IN %@", swiftDataExpenses.map { $0.id })
        let cdExpenses = try cdContext.fetch(request)
            .sorted { ($0.value(forKey: "id") as! UUID).uuidString < ($1.value(forKey: "id") as! UUID).uuidString }

        XCTAssertEqual(cdExpenses.count, swiftDataExpenses.count, "件数一致")

        for (sd, cd) in zip(swiftDataExpenses, cdExpenses) {
            XCTAssertEqual(cd.value(forKey: "id") as? UUID, sd.id, "UUID一致")
            XCTAssertEqual(cd.value(forKey: "amount") as? Int64, Int64(sd.amount), "金額一致")
            XCTAssertEqual(cd.value(forKey: "category") as? String, sd.category, "カテゴリー一致")
            XCTAssertEqual(cd.value(forKey: "paymentMethod") as? String, sd.paymentMethod, "支払い方法一致")
            XCTAssertEqual(cd.value(forKey: "bookId") as? UUID, sd.bookId, "bookId一致")
            XCTAssertEqual(
                (cd.value(forKey: "date") as? Date)?.timeIntervalSince1970 ?? -1,
                sd.date.timeIntervalSince1970,
                accuracy: 0.001,
                "日付一致"
            )
        }

        // 更新確認（SwiftDataTransactionRepository.updateSameTypeTransactionと同じ手順）
        var target = swiftDataExpenses[0]
        target.amount = 7777
        target.memo = "更新済み"
        ExpenseDataSync.update(target)

        let updatedCD = try XCTUnwrap(cdContext.fetch(request).first { ($0.value(forKey: "id") as? UUID) == target.id })
        XCTAssertEqual(updatedCD.value(forKey: "amount") as? Int64, 7777, "更新後の金額一致")
        XCTAssertEqual(updatedCD.value(forKey: "memo") as? String, "更新済み", "更新後のメモ一致")

        // 削除確認（SwiftDataTransactionRepository.deleteOnlyと同じ手順）
        let deletedId = target.id
        ExpenseDataSync.delete(id: deletedId)
        XCTAssertEqual(try cdContext.count(for: request), 2, "削除後の件数一致")
    }

    func testIncomeDualWriteMatchesCoreData() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        let formService = TransactionFormService()
        let repository = SwiftDataTransactionRepository()

        for amount in ["200000", "5000", "1200"] {
            let draft = try formService.makeDraft(
                selectedType: "収入", amountText: amount, date: Date(),
                selectedMethod: "現金", selectedCategory: "給料", memo: "検証用",
                bookId: main.book.id
            )
            try repository.insertNewTransaction(draft: draft, expenseTypeName: "支出")
        }

        let swiftDataIncomes = IncomeDataSync.fetchAll()
            .sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(swiftDataIncomes.count, 3, "件数")

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "IncomeData")
        request.predicate = NSPredicate(format: "id IN %@", swiftDataIncomes.map { $0.id })
        let cdIncomes = try cdContext.fetch(request)
            .sorted { ($0.value(forKey: "id") as! UUID).uuidString < ($1.value(forKey: "id") as! UUID).uuidString }

        XCTAssertEqual(cdIncomes.count, swiftDataIncomes.count, "件数一致")

        for (sd, cd) in zip(swiftDataIncomes, cdIncomes) {
            XCTAssertEqual(cd.value(forKey: "id") as? UUID, sd.id, "UUID一致")
            XCTAssertEqual(cd.value(forKey: "amount") as? Int64, Int64(sd.amount), "金額一致")
            XCTAssertEqual(cd.value(forKey: "category") as? String, sd.category, "カテゴリー一致")
            XCTAssertEqual(cd.value(forKey: "receiveMethod") as? String, sd.receiveMethod, "受け取り方法一致")
            XCTAssertEqual(cd.value(forKey: "bookId") as? UUID, sd.bookId, "bookId一致")
            XCTAssertEqual(
                (cd.value(forKey: "date") as? Date)?.timeIntervalSince1970 ?? -1,
                sd.date.timeIntervalSince1970,
                accuracy: 0.001,
                "日付一致"
            )
        }

        // 更新確認（SwiftDataTransactionRepository.updateSameTypeTransactionと同じ手順）
        var target = swiftDataIncomes[0]
        target.amount = 88888
        target.memo = "更新済み"
        IncomeDataSync.update(target)

        let updatedCD = try XCTUnwrap(cdContext.fetch(request).first { ($0.value(forKey: "id") as? UUID) == target.id })
        XCTAssertEqual(updatedCD.value(forKey: "amount") as? Int64, 88888, "更新後の金額一致")
        XCTAssertEqual(updatedCD.value(forKey: "memo") as? String, "更新済み", "更新後のメモ一致")

        // 削除確認（SwiftDataTransactionRepository.deleteOnlyと同じ手順）
        let deletedId = target.id
        IncomeDataSync.delete(id: deletedId)
        XCTAssertEqual(try cdContext.count(for: request), 2, "削除後の件数一致")
    }

    func testInitialBalanceIncomeDualWriteViaBankAccount() throws {
        // BankAccountEditView.saveと同じ手順（初期残高>0でIncomeDataを自動生成）を、
        // 実際のモデル初期化子を使って直接再現し、dual-writeを検証する。
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var bank = BankAccountData(accountName: "検証用銀行", initialBalance: 50000)
        bank.bookId = main.book.id
        BankAccountDataSync.insert(bank)

        var income = IncomeData(
            amount: 50000, date: Date(), receiveMethod: bank.accountName,
            category: "初期残高", memo: "\(bank.accountName)の初期残高", bankAccountId: bank.id
        )
        income.bookId = main.book.id
        bank.initialBalanceIncomeId = income.id
        BankAccountDataSync.update(bank)
        IncomeDataSync.insert(income)

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "IncomeData")
        request.predicate = NSPredicate(format: "id == %@", income.id as CVarArg)
        let cdIncome = try XCTUnwrap(cdContext.fetch(request).first)
        XCTAssertEqual(cdIncome.value(forKey: "amount") as? Int64, 50000, "初期残高金額一致")
        XCTAssertEqual(cdIncome.value(forKey: "bankAccountId") as? UUID, bank.id, "紐づく口座UUID一致")

        // 口座削除時の連動削除も確認
        IncomeDataSync.delete(id: income.id)
        XCTAssertEqual(try cdContext.count(for: request), 0, "口座削除に連動した初期残高収入の削除確認")
    }

    func testTransferDualWriteMatchesCoreData() throws {
        // InputView.saveTransferと同じ手順（TransferData初期化→insert→save→Sync）を再現する。
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var transfer = TransferData(
            date: Date(),
            fromType: TransferAccountType.paymentMethod.rawValue,
            fromId: main.cash.id, fromName: main.cash.methodName,
            toType: TransferAccountType.bank.rawValue,
            toId: main.bankAccount.id, toName: main.bankAccount.accountName,
            amount: 30000, feeAmount: 200, memo: "検証用振替"
        )
        transfer.bookId = main.book.id
        TransferDataSync.insert(transfer)

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "TransferData")
        request.predicate = NSPredicate(format: "id == %@", transfer.id as CVarArg)
        let cdTransfer = try XCTUnwrap(cdContext.fetch(request).first)

        XCTAssertEqual(cdTransfer.value(forKey: "id") as? UUID, transfer.id, "UUID一致")
        XCTAssertEqual(cdTransfer.value(forKey: "amount") as? Int64, 30000, "金額一致")
        XCTAssertEqual(cdTransfer.value(forKey: "feeAmount") as? Int64, 200, "手数料一致")
        XCTAssertEqual(cdTransfer.value(forKey: "fromId") as? UUID, main.cash.id, "振替元UUID一致")
        XCTAssertEqual(cdTransfer.value(forKey: "toId") as? UUID, main.bankAccount.id, "振替先UUID一致")
        XCTAssertEqual(cdTransfer.value(forKey: "bookId") as? UUID, main.book.id, "bookId一致")
        XCTAssertEqual(
            (cdTransfer.value(forKey: "date") as? Date)?.timeIntervalSince1970 ?? -1,
            transfer.date.timeIntervalSince1970,
            accuracy: 0.001,
            "日付一致"
        )

        // 更新確認（TransferEditView.saveと同じ手順）
        transfer.amount = 45000
        transfer.memo = "更新済み"
        transfer.updatedAt = Date()
        TransferDataSync.update(transfer)

        let updatedCD = try XCTUnwrap(cdContext.fetch(request).first)
        XCTAssertEqual(updatedCD.value(forKey: "amount") as? Int64, 45000, "更新後の金額一致")
        XCTAssertEqual(updatedCD.value(forKey: "memo") as? String, "更新済み", "更新後のメモ一致")

        // 削除確認（TransferEditView.deleteButtonと同じ手順）
        let deletedId = transfer.id
        TransferDataSync.delete(id: deletedId)
        XCTAssertEqual(try cdContext.count(for: request), 0, "削除後の件数一致")
    }

    func testBudgetDualWriteMatchesCoreData() throws {
        // BudgetSettingView.saveと同じ手順（BudgetData初期化→insert）を再現する。
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var budget = BudgetData(year: 2026, month: 7, categoryName: "食費", amount: 30000)
        budget.bookId = main.book.id
        BudgetDataSync.insert(budget)

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "BudgetData")
        request.predicate = NSPredicate(format: "id == %@", budget.id as CVarArg)
        let cdBudget = try XCTUnwrap(cdContext.fetch(request).first)

        XCTAssertEqual(cdBudget.value(forKey: "id") as? UUID, budget.id, "UUID一致")
        XCTAssertEqual(cdBudget.value(forKey: "year") as? Int64, 2026, "年一致")
        XCTAssertEqual(cdBudget.value(forKey: "month") as? Int64, 7, "月一致")
        XCTAssertEqual(cdBudget.value(forKey: "categoryName") as? String, "食費", "カテゴリー名一致")
        XCTAssertEqual(cdBudget.value(forKey: "amount") as? Int64, 30000, "金額一致")
        XCTAssertEqual(cdBudget.value(forKey: "bookId") as? UUID, main.book.id, "bookId一致")

        // 更新確認（BudgetSettingView.saveの既存分岐と同じ手順）
        budget.amount = 35000
        budget.updatedAt = Date()
        BudgetDataSync.update(budget)

        let updatedCD = try XCTUnwrap(cdContext.fetch(request).first)
        XCTAssertEqual(updatedCD.value(forKey: "amount") as? Int64, 35000, "更新後の金額一致")

        // 削除確認（金額0で既存を削除する分岐と同じ手順）
        let deletedId = budget.id
        BudgetDataSync.delete(id: deletedId)
        XCTAssertEqual(try cdContext.count(for: request), 0, "削除後の件数一致")
    }

    func testRecurringBudgetDualWriteMatchesCoreData() throws {
        // BudgetSettingView.saveの定期予算分岐と同じ手順を再現する。
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var recurring = RecurringBudgetData(categoryName: "食費", amount: 25000)
        recurring.bookId = main.book.id
        RecurringBudgetDataSync.insert(recurring)

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "RecurringBudgetData")
        request.predicate = NSPredicate(format: "id == %@", recurring.id as CVarArg)
        let cdRecurring = try XCTUnwrap(cdContext.fetch(request).first)

        XCTAssertEqual(cdRecurring.value(forKey: "id") as? UUID, recurring.id, "UUID一致")
        XCTAssertEqual(cdRecurring.value(forKey: "categoryName") as? String, "食費", "カテゴリー名一致")
        XCTAssertEqual(cdRecurring.value(forKey: "amount") as? Int64, 25000, "金額一致")
        XCTAssertEqual(cdRecurring.value(forKey: "isEnabled") as? Bool, true, "有効フラグ一致")
        XCTAssertEqual(cdRecurring.value(forKey: "bookId") as? UUID, main.book.id, "bookId一致")

        // 更新確認
        recurring.amount = 27000
        recurring.updatedAt = Date()
        RecurringBudgetDataSync.update(recurring)

        let updatedCD = try XCTUnwrap(cdContext.fetch(request).first)
        XCTAssertEqual(updatedCD.value(forKey: "amount") as? Int64, 27000, "更新後の金額一致")

        // 削除確認
        let deletedId = recurring.id
        RecurringBudgetDataSync.delete(id: deletedId)
        XCTAssertEqual(try cdContext.count(for: request), 0, "削除後の件数一致")
    }

    func testRecurringTransferSettingDualWriteMatchesCoreData() throws {
        // RecurringTransferEditView.saveと同じ手順を再現する。
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var setting = RecurringTransferSettingData(
            fromMethodId: main.cash.id, fromMethodName: main.cash.methodName,
            fromType: TransferAccountType.paymentMethod.rawValue,
            toMethodId: main.bankAccount.id, toMethodName: main.bankAccount.accountName,
            toType: TransferAccountType.bank.rawValue,
            amount: 10000, day: 25
        )
        setting.bookId = main.book.id
        RecurringTransferSettingDataSync.insert(setting)

        let cdContext = CoreDataStack.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "RecurringTransferSettingData")
        request.predicate = NSPredicate(format: "id == %@", setting.id as CVarArg)
        let cdSetting = try XCTUnwrap(cdContext.fetch(request).first)

        XCTAssertEqual(cdSetting.value(forKey: "id") as? UUID, setting.id, "UUID一致")
        XCTAssertEqual(cdSetting.value(forKey: "amount") as? Int64, 10000, "金額一致")
        XCTAssertEqual(cdSetting.value(forKey: "day") as? Int64, 25, "実行日一致")
        XCTAssertEqual(cdSetting.value(forKey: "fromMethodId") as? UUID, main.cash.id, "振替元UUID一致")
        XCTAssertEqual(cdSetting.value(forKey: "toMethodId") as? UUID, main.bankAccount.id, "振替先UUID一致")
        XCTAssertEqual(cdSetting.value(forKey: "bookId") as? UUID, main.book.id, "bookId一致")
        XCTAssertEqual(cdSetting.value(forKey: "isActive") as? Bool, true, "有効フラグ一致")

        // 更新確認
        setting.amount = 12000
        setting.updatedAt = Date()
        RecurringTransferSettingDataSync.update(setting)

        let updatedCD = try XCTUnwrap(cdContext.fetch(request).first)
        XCTAssertEqual(updatedCD.value(forKey: "amount") as? Int64, 12000, "更新後の金額一致")

        // 削除相当（isActive=false）確認（RecurringTransferEditView.deleteと同じ手順）
        setting.isActive = false
        RecurringTransferSettingDataSync.update(setting)

        let deactivatedCD = try XCTUnwrap(cdContext.fetch(request).first)
        XCTAssertEqual(deactivatedCD.value(forKey: "isActive") as? Bool, false, "無効化後のフラグ一致")
    }

    // MARK: - ゴミ箱機能追加（isInTrash/trashedAt）の軽量マイグレーション検証
    //
    // 「isInTrash/trashedAtを追加する前」の旧スキーマを、その2属性を含まない最小限の
    // NSManagedObjectModelとしてゼロから組み立て（representedClassNameは意図的に設定しない
    // ＝ 生成済みCDExpenseDataクラスとは紐付けない。実の.momdを重複ロードすると、そのクラスを
    // 「claim」するNSEntityDescriptionが2つ存在することになり、プロセス内の以降の
    // +[CDXxx entity] 解決が全て曖昧になってしまうため）、実ディスク上のストアへ
    // 既存データを1件書き込む。その後、現行モデル（isInTrash/trashedAtあり、CoreDataStackが
    // 保持する唯一のモデルインスタンス）で同じストアURLを開き直し、Core Data標準の
    // 軽量マイグレーション（属性追加のみ・自動推論マッピング）が実際に効いて
    // （a）クラッシュしない、（b）既存データが保持される、（c）新属性がデフォルト値
    // （isInTrash=false, trashedAt=nil）になることを確認する。

    private func makePreTrashExpenseEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ExpenseData"
        // 生成済みCDExpenseDataクラスとは紐付けず、汎用NSManagedObjectのままにする
        // （実クラスに紐付けると、プロセス内で+[CDExpenseData entity]の解決が曖昧になるため）
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        func attr(_ name: String, _ type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            a.defaultValue = defaultValue
            return a
        }

        entity.properties = [
            attr("id", .UUIDAttributeType),
            attr("amount", .integer64AttributeType, defaultValue: 0),
            attr("date", .dateAttributeType),
            attr("paymentMethod", .stringAttributeType),
            attr("category", .stringAttributeType),
            attr("memo", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("bookId", .UUIDAttributeType),
            attr("bankAccountId", .UUIDAttributeType),
            attr("fixedExpenseId", .UUIDAttributeType),
            attr("receiptImagePath", .stringAttributeType),
            attr("isTestData", .booleanAttributeType, defaultValue: false),
        ]
        return entity
    }

    func testLightweightMigrationFromPreTrashSchemaPreservesExistingData() throws {
        let oldModel = NSManagedObjectModel()
        oldModel.entities = [makePreTrashExpenseEntity()]

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QARegressionMigrationTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("Kakeibo3.sqlite")

        let expenseId = UUID()
        let bookId = UUID()

        // 1. 旧スキーマ（isInTrash/trashedAtが存在しない）で実ストアを作り、支出データを1件書き込む
        do {
            let oldContainer = NSPersistentContainer(name: "Kakeibo3", managedObjectModel: oldModel)
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldAddStoreAsynchronously = false
            oldContainer.persistentStoreDescriptions = [description]

            let semaphore = DispatchSemaphore(value: 0)
            var loadError: Error?
            oldContainer.loadPersistentStores { _, error in
                loadError = error
                semaphore.signal()
            }
            semaphore.wait()
            XCTAssertNil(loadError, "旧モデルでのストア作成に失敗した: \(String(describing: loadError))")

            let ctx = oldContainer.viewContext
            let entity = try XCTUnwrap(oldModel.entitiesByName["ExpenseData"])
            let obj = NSManagedObject(entity: entity, insertInto: ctx)
            obj.setValue(expenseId, forKey: "id")
            obj.setValue(Int64(1234), forKey: "amount")
            obj.setValue(Date(), forKey: "date")
            obj.setValue("現金", forKey: "paymentMethod")
            obj.setValue("食費", forKey: "category")
            obj.setValue("旧スキーマ確認", forKey: "memo")
            obj.setValue(Date(), forKey: "createdAt")
            obj.setValue(bookId, forKey: "bookId")
            obj.setValue(false, forKey: "isTestData")
            try ctx.save()
        }

        // 2〜4. 現行モデル（isInTrash/trashedAtあり）で同じストアURLを開き直す
        //       （軽量マイグレーションが走る。失敗すればCoreDataStack.init内でfatalErrorしテストごと落ちる）
        CoreDataStack.shared = CoreDataStack(storeURL: storeURL)

        // 5. 既存データが保持され、新属性がデフォルト値になっていることを確認
        let migrated = ExpenseDataSync.fetch(id: expenseId)
        XCTAssertEqual(migrated?.amount, 1234, "旧スキーマのデータが軽量マイグレーション後も残っている必要がある")
        XCTAssertEqual(migrated?.memo, "旧スキーマ確認", "旧スキーマのメモが残っている必要がある")
        XCTAssertEqual(migrated?.bookId, bookId, "旧スキーマのbookIdが残っている必要がある")
        XCTAssertEqual(migrated?.isInTrash, false, "新属性isInTrashはマイグレーション後デフォルトfalseになる必要がある")
        XCTAssertNil(migrated?.trashedAt, "新属性trashedAtはマイグレーション後デフォルトnilになる必要がある")
    }
}
