import CoreData

// MARK: - 本番Cloud/Localストアの状態判定(Case A/B/C、Step 2B専用)
//
// 既存ProductionStoreCaseClassifier(単一の本番ストア用)と同じ判定基準を、
// Cloud/Local 2ストアのペアに拡張したもの。

enum SplitProductionCase: Equatable {
    /// Case A: Cloud/Localどちらの本番ストアファイルも存在しない
    case absent
    /// Case B: 存在するが初回起動時の自動生成デフォルトのみ(上書き可能)
    case empty
    /// Case C: 実データが存在する(自動上書き禁止)
    case hasRealData
}

enum SplitProductionCaseClassifier {

    private static let transactionBearingCloudEntities = [
        "ExpenseData", "IncomeData", "TransferData", "BudgetData", "RecurringBudgetData",
        "FixedExpenseData", "RecurringIncomeData", "RecurringTransferSettingData", "BankAccountData",
    ]

    static func classify(cloudStoreURL: URL, localStoreURL: URL) -> SplitProductionCase {
        let fm = FileManager.default
        let cloudExists = fm.fileExists(atPath: cloudStoreURL.path)
        let localExists = fm.fileExists(atPath: localStoreURL.path)

        guard cloudExists || localExists else { return .absent }

        // 片方だけ存在する不整合な状態は、安全側に倒して「実データあり」として扱い、自動上書きしない。
        guard cloudExists, localExists else { return .hasRealData }

        let baseDirectory = cloudStoreURL.deletingLastPathComponent()
        guard let stack = try? CoreDataStack(cloudLocalDirectory: baseDirectory, enableCloudKit: false) else {
            // 開けない(壊れている等)場合も安全側に倒す。
            return .hasRealData
        }
        defer { try? stack.releasePersistentStoresForMigration() }
        let context = stack.container.viewContext
        let model = stack.container.managedObjectModel

        if hasRealCloudData(context: context) { return .hasRealData }

        // Local側: bootstrap起動だけでは取引が無いためDailySnapshot等は1件も作られないはず。
        // 1件でも存在すれば実データ由来とみなし、自動上書きしない。
        for entityName in SplitEntityConfiguration.localEntityNames(model: model) {
            let count = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))) ?? 0
            if count > 0 { return .hasRealData }
        }

        return .empty
    }

    private static func hasRealCloudData(context: NSManagedObjectContext) -> Bool {
        for entityName in transactionBearingCloudEntities {
            let count = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))) ?? 0
            if count > 0 { return true }
        }

        let bookCount = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "BookData"))) ?? 0
        if bookCount > 1 { return true }

        let categoryCount = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "CategoryData"))) ?? 0
        if categoryCount > 0 { return true }

        let paymentMethods = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PaymentMethodSettingData"))) ?? []
        let hasNonDefaultPaymentMethod = paymentMethods.contains { obj in
            let name = obj.value(forKey: "methodName") as? String
            let type = obj.value(forKey: "type") as? String
            return !(name == "現金" && type == "cash")
        }
        if hasNonDefaultPaymentMethod { return true }

        let receiveMethods = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ReceiveMethodData"))) ?? []
        let hasNonDefaultReceiveMethod = receiveMethods.contains { obj in
            (obj.value(forKey: "methodName") as? String) != "現金"
        }
        if hasNonDefaultReceiveMethod { return true }

        return false
    }
}
