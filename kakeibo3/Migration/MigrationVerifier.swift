import CoreData

// MARK: - 書き込み後の検証(帳簿別件数・合計金額・主要IDの一致確認)
//
// Core Data側のエンティティ名(NSFetchRequest(entityName:)に渡す名前)は、
// representedClassNameのCD接頭辞を除いた素の名前(例: "ExpenseData")である
// (Kakeibo3.xcdatamodeld/.../contents参照)。全13Entityの主キー属性名は
// 共通して"id"のため、KVCで汎用的に扱う。

enum MigrationVerificationError: Error, Equatable {
    case idSetMismatch(entity: String, missingFromCoreData: Int, unexpectedInCoreData: Int)
    case countMismatch(entity: String, expected: Int, actual: Int)
    case bookSummaryMismatch(bookId: UUID, detail: String)
    case bookIdsMismatch(missing: Int, unexpected: Int)
}

enum MigrationVerifier {

    static let migratedEntityNames = [
        "BookData", "CategoryData", "ExpenseData", "IncomeData", "TransferData",
        "BankAccountData", "ReceiveMethodData", "PaymentMethodSettingData",
        "BudgetData", "RecurringBudgetData", "FixedExpenseData",
        "RecurringIncomeData", "RecurringTransferSettingData",
    ]

    // MARK: - 書き込み直後の検証 + Manifest生成

    static func verify(
        snapshot: LegacySnapshot,
        context: NSManagedObjectContext,
        sourceStoreFileSize: Int64 = 0,
        sourceStoreModifiedAt: Date = .distantPast
    ) throws -> MigrationManifest {
        var entityCounts: [String: Int] = [:]

        try checkIdSet(entityName: "BookData", expected: Set(snapshot.books.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "CategoryData", expected: Set(snapshot.categories.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "ExpenseData", expected: Set(snapshot.expenses.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "IncomeData", expected: Set(snapshot.incomes.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "TransferData", expected: Set(snapshot.transfers.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "BankAccountData", expected: Set(snapshot.bankAccounts.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "ReceiveMethodData", expected: Set(snapshot.receiveMethods.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "PaymentMethodSettingData", expected: Set(snapshot.paymentMethodSettings.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "BudgetData", expected: Set(snapshot.budgets.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "RecurringBudgetData", expected: Set(snapshot.recurringBudgets.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "FixedExpenseData", expected: Set(snapshot.fixedExpenses.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "RecurringIncomeData", expected: Set(snapshot.recurringIncomes.map(\.id)), context: context, entityCounts: &entityCounts)
        try checkIdSet(entityName: "RecurringTransferSettingData", expected: Set(snapshot.recurringTransferSettings.map(\.id)), context: context, entityCounts: &entityCounts)

        let bookSummaries = try snapshot.books.map { book in
            try buildAndVerifyBookSummary(bookId: book.id, snapshot: snapshot, context: context)
        }

        return MigrationManifest(
            migrationVersion: MigrationManifest.currentVersion,
            completedAt: Date(),
            sourceStoreFileSize: sourceStoreFileSize,
            sourceStoreModifiedAt: sourceStoreModifiedAt,
            sourceBookIDs: snapshot.books.map(\.id),
            entityCounts: entityCounts,
            regeneratedModelSourceCounts: [
                "DailySnapshot": snapshot.dailySnapshots.count,
                "MonthlySnapshot": snapshot.monthlySnapshots.count,
                "AnalysisMonthlySnapshot": snapshot.analysisMonthlySnapshots.count,
                "AssetGraphCacheData": snapshot.assetGraphCaches.count,
            ],
            bookSummaries: bookSummaries,
            targetStoreIdentifier: nil
        )
    }

    // MARK: - close→reopen後の再検証(件数のみ。IDセットは高コストなので件数一致で代表させる)

    static func reverify(manifest: MigrationManifest, context: NSManagedObjectContext) throws {
        for entityName in migratedEntityNames {
            let expected = manifest.entityCounts[entityName] ?? 0
            let actual = try count(entityName: entityName, in: context)
            guard actual == expected else {
                throw MigrationVerificationError.countMismatch(entity: entityName, expected: expected, actual: actual)
            }
        }
        for summary in manifest.bookSummaries {
            let recomputed = try computeBookSummary(bookId: summary.bookId, context: context)
            guard recomputed == summary else {
                throw MigrationVerificationError.bookSummaryMismatch(bookId: summary.bookId, detail: "再オープン後に帳簿別集計が一致しない")
            }
        }
    }

    /// 本番昇格後の最終確認用:「主要UUID」の維持を、件数だけでは検知できない
    /// 空の帳簿(取引が1件も無い帳簿)の欠落も含めて確認する。
    static func verifyBookIdsExist(manifest: MigrationManifest, context: NSManagedObjectContext) throws {
        let expected = Set(manifest.sourceBookIDs)
        let actual = try fetchIdSet(entityName: "BookData", context: context)
        guard actual == expected else {
            let missing = expected.subtracting(actual).count
            let unexpected = actual.subtracting(expected).count
            throw MigrationVerificationError.bookIdsMismatch(missing: missing, unexpected: unexpected)
        }
    }

    // MARK: - Helpers

    private static func checkIdSet(
        entityName: String, expected: Set<UUID>, context: NSManagedObjectContext,
        entityCounts: inout [String: Int]
    ) throws {
        let actual = try fetchIdSet(entityName: entityName, context: context)
        entityCounts[entityName] = actual.count
        guard actual == expected else {
            let missing = expected.subtracting(actual).count
            let unexpected = actual.subtracting(expected).count
            throw MigrationVerificationError.idSetMismatch(entity: entityName, missingFromCoreData: missing, unexpectedInCoreData: unexpected)
        }
    }

    private static func fetchIdSet(entityName: String, context: NSManagedObjectContext) throws -> Set<UUID> {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let objects = try context.fetch(request)
        return Set(objects.compactMap { $0.value(forKey: "id") as? UUID })
    }

    private static func count(entityName: String, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try context.count(for: request)
    }

    private static func buildAndVerifyBookSummary(
        bookId: UUID, snapshot: LegacySnapshot, context: NSManagedObjectContext
    ) throws -> MigrationBookSummary {
        let fromSnapshot = MigrationBookSummary(
            bookId: bookId,
            entityCounts: [
                "CategoryData": snapshot.categories.filter { $0.bookId == bookId }.count,
                "ExpenseData": snapshot.expenses.filter { $0.bookId == bookId }.count,
                "IncomeData": snapshot.incomes.filter { $0.bookId == bookId }.count,
                "TransferData": snapshot.transfers.filter { $0.bookId == bookId }.count,
                "BankAccountData": snapshot.bankAccounts.filter { $0.bookId == bookId }.count,
                "ReceiveMethodData": snapshot.receiveMethods.filter { $0.bookId == bookId }.count,
                "PaymentMethodSettingData": snapshot.paymentMethodSettings.filter { $0.bookId == bookId }.count,
                "BudgetData": snapshot.budgets.filter { $0.bookId == bookId }.count,
                "RecurringBudgetData": snapshot.recurringBudgets.filter { $0.bookId == bookId }.count,
                "FixedExpenseData": snapshot.fixedExpenses.filter { $0.bookId == bookId }.count,
                "RecurringIncomeData": snapshot.recurringIncomes.filter { $0.bookId == bookId }.count,
                "RecurringTransferSettingData": snapshot.recurringTransferSettings.filter { $0.bookId == bookId }.count,
            ],
            expenseTotal: snapshot.expenses.filter { $0.bookId == bookId }.reduce(0) { $0 + $1.amount },
            incomeTotal: snapshot.incomes.filter { $0.bookId == bookId }.reduce(0) { $0 + $1.amount },
            transferTotal: snapshot.transfers.filter { $0.bookId == bookId }.reduce(0) { $0 + $1.amount }
        )

        let fromCoreData = try computeBookSummary(bookId: bookId, context: context)
        guard fromCoreData == fromSnapshot else {
            throw MigrationVerificationError.bookSummaryMismatch(bookId: bookId, detail: "書き込み直後の帳簿別集計がLegacySnapshotと一致しない")
        }
        return fromCoreData
    }

    private static func computeBookSummary(bookId: UUID, context: NSManagedObjectContext) throws -> MigrationBookSummary {
        var entityCounts: [String: Int] = [:]
        for entityName in migratedEntityNames where entityName != "BookData" {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            entityCounts[entityName] = try context.count(for: request)
        }

        func sumAmount(entityName: String) throws -> Int {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            let objects = try context.fetch(request)
            return objects.reduce(0) { $0 + Int(($1.value(forKey: "amount") as? Int64) ?? 0) }
        }

        return MigrationBookSummary(
            bookId: bookId,
            entityCounts: entityCounts,
            expenseTotal: try sumAmount(entityName: "ExpenseData"),
            incomeTotal: try sumAmount(entityName: "IncomeData"),
            transferTotal: try sumAmount(entityName: "TransferData")
        )
    }
}
