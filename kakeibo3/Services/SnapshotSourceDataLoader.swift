import CoreData

// MARK: - Snapshot/AnalysisSnapshot/AssetGraphCache共通の元データ読み込み
//
// SnapshotManager/AnalysisSnapshotManager/AssetGraphCacheServiceはいずれも
// 「ある帳簿の口座・支払い方法・受け取り方法・カテゴリー・支出・収入・振替を読み、
// 派生データを計算する」という同じ入力を必要とする。*DataSync系はCoreDataStack.shared.
// container.viewContext固定のため、backgroundContextから安全に使えない。
//
// このローダーは呼び出し側が渡したcontext(通常はnewBackgroundContext())上で直接
// NSFetchRequestを実行し、その場でプレーンな値型(既存のdomain struct)へ変換する。
// 呼び出し側は必ず context.perform / context.performAndWait のブロック内から呼ぶこと
// (NSManagedObjectをcontext外へ持ち出さないため、ここで完全に値型へ変換してから返す)。
//
// フェッチ失敗は`try?`で握りつぶさずthrowする。ここを握りつぶすと、I/O障害等で
// 一時的にfetchが失敗した場合に「その帳簿にはデータが無い」と誤認し、既存の正しい
// Snapshotを削除したまま空で確定してしまう(データ消失)おそれがあるため。
//
// ゴミ箱データ(isInTrash == true)は常に除外する(既存の*DataSync.fetchAll系と同じ既定動作)。

enum SnapshotSourceDataLoader {

    struct BookSourceData {
        let bankAccounts: [BankAccountData]
        let paymentMethods: [PaymentMethodSettingData]
        let receiveMethods: [ReceiveMethodData]
        let categories: [CategoryData]
        let expenses: [ExpenseData]
        let incomes: [IncomeData]
        let transfers: [TransferData]
    }

    /// 全期間ぶん(rebuildAll用)。context.perform内から呼ぶこと。
    static func loadAll(bookId: UUID, context: NSManagedObjectContext) throws -> BookSourceData {
        BookSourceData(
            bankAccounts: try fetchBankAccounts(bookId: bookId, context: context),
            paymentMethods: try fetchPaymentMethods(bookId: bookId, context: context),
            receiveMethods: try fetchReceiveMethods(bookId: bookId, context: context),
            categories: try fetchCategories(bookId: bookId, context: context),
            expenses: try fetchExpenses(bookId: bookId, context: context),
            incomes: try fetchIncomes(bookId: bookId, context: context),
            transfers: try fetchTransfers(bookId: bookId, context: context)
        )
    }

    /// 全帳簿IDの一覧。context.perform内から呼ぶこと。
    static func loadAllBookIds(context: NSManagedObjectContext) throws -> [UUID] {
        let request = CDBookData.fetchRequest()
        return try context.fetch(request).compactMap(\.id)
    }

    // MARK: - Fetch + map(bookId条件のみ。日付範囲はEntity側で絞らず呼び出し側でフィルタする)

    static func fetchBankAccounts(bookId: UUID, context: NSManagedObjectContext) throws -> [BankAccountData] {
        let request = CDBankAccountData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return try context.fetch(request).compactMap(map)
    }

    static func fetchPaymentMethods(bookId: UUID, context: NSManagedObjectContext) throws -> [PaymentMethodSettingData] {
        let request = CDPaymentMethodSettingData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return try context.fetch(request).compactMap(map)
    }

    static func fetchReceiveMethods(bookId: UUID, context: NSManagedObjectContext) throws -> [ReceiveMethodData] {
        let request = CDReceiveMethodData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return try context.fetch(request).compactMap(map)
    }

    static func fetchCategories(bookId: UUID, context: NSManagedObjectContext) throws -> [CategoryData] {
        let request = CDCategoryData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return try context.fetch(request).compactMap(map)
    }

    static func fetchExpenses(bookId: UUID, context: NSManagedObjectContext) throws -> [ExpenseData] {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
        ])
        return try context.fetch(request).compactMap(map)
    }

    static func fetchIncomes(bookId: UUID, context: NSManagedObjectContext) throws -> [IncomeData] {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
        ])
        return try context.fetch(request).compactMap(map)
    }

    static func fetchTransfers(bookId: UUID, context: NSManagedObjectContext) throws -> [TransferData] {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
        ])
        return try context.fetch(request).compactMap(map)
    }

    private static let excludeTrashPredicate = NSPredicate(format: "isInTrash == NO")

    // MARK: - CD -> domain struct マッピング(各*DataSync.swiftのmap(_:)と同じ変換)

    private static func map(_ cd: CDBankAccountData) -> BankAccountData? {
        guard let id = cd.id, let accountName = cd.accountName,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var account = BankAccountData(
            id: id, accountName: accountName, initialBalance: cd.initialBalance?.doubleValue,
            memo: cd.memo, isActive: cd.isActive, sortOrder: Int(cd.sortOrder),
            createdAt: createdAt, updatedAt: updatedAt
        )
        account.initialBalanceIncomeId = cd.initialBalanceIncomeId
        account.showAsPaymentMethod = cd.showAsPaymentMethod
        account.showAsReceiveMethod = cd.showAsReceiveMethod
        account.showInAnalysis = cd.showInAnalysis
        account.isAsset = cd.isAsset
        account.recurringTransferSettingId = cd.recurringTransferSettingId
        account.recurringTransferSettingIds = cd.recurringTransferSettingIds
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        account.isTestData = cd.isTestData
        account.isLocked = cd.isLocked
        account.bookId = cd.bookId
        account.colorHex = cd.colorHex
        return account
    }

    private static func map(_ cd: CDPaymentMethodSettingData) -> PaymentMethodSettingData? {
        guard let id = cd.id, let methodName = cd.methodName, let type = cd.type,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var method = PaymentMethodSettingData(
            id: id, methodName: methodName, type: type,
            closingDay: cd.closingDay?.intValue, withdrawalDay: cd.withdrawalDay?.intValue,
            adjustPaymentDateToNextBusinessDay: cd.adjustPaymentDateToNextBusinessDay,
            bankAccount: cd.bankAccount, withdrawalBankAccountId: cd.withdrawalBankAccountId,
            createdAt: createdAt, updatedAt: updatedAt, sortOrder: Int(cd.sortOrder)
        )
        method.memo = cd.memo
        method.isActive = cd.isActive
        method.isAsset = cd.isAsset
        method.assetInitialBalance = cd.assetInitialBalance?.doubleValue
        method.includeInAnalysis = cd.includeInAnalysis
        method.assetInitialBalanceIncomeId = cd.assetInitialBalanceIncomeId
        method.assetInitialBalanceExpenseId = cd.assetInitialBalanceExpenseId
        method.showInInputPicker = cd.showInInputPicker
        method.useForReceive = cd.useForReceive
        method.showInAnalysis = cd.showInAnalysis
        method.recurringTransferSettingId = cd.recurringTransferSettingId
        method.recurringTransferSettingIds = cd.recurringTransferSettingIds
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        method.isTestData = cd.isTestData
        method.isLocked = cd.isLocked
        method.bookId = cd.bookId
        method.colorHex = cd.colorHex
        method.holidayAdjustment = cd.holidayAdjustment
        return method
    }

    private static func map(_ cd: CDReceiveMethodData) -> ReceiveMethodData? {
        guard let id = cd.id, let methodName = cd.methodName, let createdAt = cd.createdAt else { return nil }
        var method = ReceiveMethodData(
            id: id, methodName: methodName, isActive: cd.isActive,
            sortOrder: Int(cd.sortOrder), createdAt: createdAt
        )
        method.bookId = cd.bookId
        return method
    }

    private static func map(_ cd: CDCategoryData) -> CategoryData? {
        guard let id = cd.id, let name = cd.name, let colorHex = cd.colorHex,
              let type = cd.type, let createdAt = cd.createdAt else { return nil }
        var category = CategoryData(
            id: id, name: name, colorHex: colorHex, type: type,
            sortOrder: Int(cd.sortOrder), createdAt: createdAt
        )
        category.isTestData = cd.isTestData
        category.bookId = cd.bookId
        category.isSuspended = cd.isSuspended
        category.isProtected = cd.isProtected
        return category
    }

    private static func map(_ cd: CDExpenseData) -> ExpenseData? {
        guard let id = cd.id, let paymentMethod = cd.paymentMethod, let category = cd.category,
              let memo = cd.memo, let date = cd.date, let createdAt = cd.createdAt else { return nil }
        var expense = ExpenseData(
            id: id, amount: Int(cd.amount), date: date, paymentMethod: paymentMethod,
            category: category, memo: memo, bankAccountId: cd.bankAccountId, createdAt: createdAt
        )
        expense.bookId = cd.bookId
        expense.fixedExpenseId = cd.fixedExpenseId
        expense.receiptImagePath = cd.receiptImagePath
        expense.isTestData = cd.isTestData
        expense.isInTrash = cd.isInTrash
        expense.trashedAt = cd.trashedAt
        return expense
    }

    private static func map(_ cd: CDIncomeData) -> IncomeData? {
        guard let id = cd.id, let receiveMethod = cd.receiveMethod, let category = cd.category,
              let memo = cd.memo, let date = cd.date, let createdAt = cd.createdAt else { return nil }
        var income = IncomeData(
            id: id, amount: Int(cd.amount), date: date, receiveMethod: receiveMethod,
            category: category, memo: memo, bankAccountId: cd.bankAccountId, createdAt: createdAt
        )
        income.bookId = cd.bookId
        income.recurringIncomeId = cd.recurringIncomeId
        income.receiptImagePath = cd.receiptImagePath
        income.isTestData = cd.isTestData
        income.isInTrash = cd.isInTrash
        income.trashedAt = cd.trashedAt
        return income
    }

    private static func map(_ cd: CDTransferData) -> TransferData? {
        guard let id = cd.id, let fromType = cd.fromType, let fromName = cd.fromName,
              let toType = cd.toType, let toName = cd.toName, let memo = cd.memo,
              let date = cd.date, let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var transfer = TransferData(
            id: id, date: date, fromType: fromType, fromId: cd.fromId, fromName: fromName,
            toType: toType, toId: cd.toId, toName: toName, amount: Int(cd.amount),
            feeAmount: Int(cd.feeAmount), memo: memo, receiptImagePath: cd.receiptImagePath,
            createdAt: createdAt, updatedAt: updatedAt
        )
        transfer.isTestData = cd.isTestData
        transfer.recurringTransferSettingId = cd.recurringTransferSettingId
        transfer.bookId = cd.bookId
        transfer.isInTrash = cd.isInTrash
        transfer.trashedAt = cd.trashedAt
        return transfer
    }
}
