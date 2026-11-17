import CoreData

// MARK: - 本番Core Dataストアの状態判定(Case A/B/C)
//
// CDBookData.count() > 0 だけでは判定不十分(DataInitializerServiceが初回帳簿作成時に
// 自動で「現金」のPaymentMethodSettingData/ReceiveMethodDataを1件ずつ作るため、
// 移行が一度も走っていない真っさらな環境でもBookData=1件・現金2件が存在しうる)。
// トランザクション系Entityが1件でもあれば実データありとみなし、それ以外は
// 「デフォルト以外の中身」が無いかを厳密にチェックする。

enum ProductionStoreCase: Equatable {
    /// Case A: 本番ストアファイルが存在しない
    case absent
    /// Case B: 存在するが初回起動時の自動生成デフォルトのみ(上書き可能)
    case empty
    /// Case C: 実データが存在する(自動上書き禁止)
    case hasRealData
}

enum ProductionStoreCaseClassifier {

    private static let transactionBearingEntities = [
        "ExpenseData", "IncomeData", "TransferData", "BudgetData", "RecurringBudgetData",
        "FixedExpenseData", "RecurringIncomeData", "RecurringTransferSettingData", "BankAccountData",
    ]

    static func classify(storeURL: URL) -> ProductionStoreCase {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return .absent }

        guard let stack = try? CoreDataStack(throwingStoreURL: storeURL) else {
            // 開けない(壊れている等)場合は、安全側に倒して「実データあり」として扱い、
            // 自動上書きしない。
            return .hasRealData
        }
        defer { try? stack.releasePersistentStoresForMigration() }
        let context = stack.container.viewContext

        for entityName in transactionBearingEntities {
            let count = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))) ?? 0
            if count > 0 { return .hasRealData }
        }

        let bookCount = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "BookData"))) ?? 0
        if bookCount > 1 { return .hasRealData }

        let categoryCount = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "CategoryData"))) ?? 0
        if categoryCount > 0 { return .hasRealData }

        let paymentMethods = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PaymentMethodSettingData"))) ?? []
        let hasNonDefaultPaymentMethod = paymentMethods.contains { obj in
            let name = obj.value(forKey: "methodName") as? String
            let type = obj.value(forKey: "type") as? String
            return !(name == "現金" && type == "cash")
        }
        if hasNonDefaultPaymentMethod { return .hasRealData }

        let receiveMethods = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ReceiveMethodData"))) ?? []
        let hasNonDefaultReceiveMethod = receiveMethods.contains { obj in
            (obj.value(forKey: "methodName") as? String) != "現金"
        }
        if hasNonDefaultReceiveMethod { return .hasRealData }

        return .empty
    }
}
