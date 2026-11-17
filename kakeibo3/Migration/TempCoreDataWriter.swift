import CoreData

// MARK: - LegacySnapshotを一時Core Dataストアへ書き込む
//
// 13の「直接移行」Entityのみを対象にする(MigrationClassification参照)。スナップショット/
// キャッシュ4種は書き込まない(再生成対象として記録するのみ)。UUIDは全てソースの値を
// そのまま使う(新しいUUIDは発行しない)。呼び出し側が渡すNSManagedObjectContextは、
// CoreDataStack.shared ではなく移行専用の使い捨てCoreDataStack(storeURL:)由来のものを想定する。

enum TempCoreDataWriter {

    static func write(_ snapshot: LegacySnapshot, into context: NSManagedObjectContext) throws {
        for row in snapshot.books {
            let cd = CDBookData(context: context)
            cd.id = row.id
            cd.name = row.name
            cd.createdAt = row.createdAt
            // updatedAtはCore Data側に未追加(Phase 0-A④で意図的に保留、Phase 2以降で対応)
            cd.sortOrder = Int64(row.sortOrder)
            cd.isArchived = row.isArchived
            cd.isMain = row.isMain
        }

        for row in snapshot.categories {
            let cd = CDCategoryData(context: context)
            cd.id = row.id
            cd.name = row.name
            cd.colorHex = row.colorHex
            cd.type = row.type
            cd.sortOrder = Int64(row.sortOrder)
            cd.createdAt = row.createdAt
            // updatedAtはCore Data側に未追加(Phase 0-A④で意図的に保留、Phase 2以降で対応)
            cd.isTestData = row.isTestData
            cd.bookId = row.bookId
            cd.isSuspended = row.isSuspended
            cd.isProtected = row.isProtected
        }

        for row in snapshot.expenses {
            let cd = CDExpenseData(context: context)
            cd.id = row.id
            cd.amount = Int64(row.amount)
            cd.date = row.date
            cd.paymentMethod = row.paymentMethod
            cd.category = row.category
            cd.memo = row.memo
            cd.createdAt = row.createdAt
            // updatedAtはCore Data側に未追加(Phase 0-A④で意図的に保留、Phase 2以降で対応)
            cd.bookId = row.bookId
            cd.bankAccountId = row.bankAccountId
            cd.fixedExpenseId = row.fixedExpenseId
            cd.receiptImagePath = row.receiptImagePath
            cd.isTestData = row.isTestData
            cd.isInTrash = row.isInTrash
            cd.trashedAt = row.trashedAt
        }

        for row in snapshot.incomes {
            let cd = CDIncomeData(context: context)
            cd.id = row.id
            cd.amount = Int64(row.amount)
            cd.date = row.date
            cd.receiveMethod = row.receiveMethod
            cd.category = row.category
            cd.memo = row.memo
            cd.createdAt = row.createdAt
            // updatedAtはCore Data側に未追加(Phase 0-A④で意図的に保留、Phase 2以降で対応)
            cd.bookId = row.bookId
            cd.bankAccountId = row.bankAccountId
            cd.recurringIncomeId = row.recurringIncomeId
            cd.receiptImagePath = row.receiptImagePath
            cd.isTestData = row.isTestData
            cd.isInTrash = row.isInTrash
            cd.trashedAt = row.trashedAt
        }

        for row in snapshot.transfers {
            let cd = CDTransferData(context: context)
            cd.id = row.id
            cd.date = row.date
            cd.fromType = row.fromType
            cd.fromId = row.fromId
            cd.fromName = row.fromName
            cd.toType = row.toType
            cd.toId = row.toId
            cd.toName = row.toName
            cd.amount = Int64(row.amount)
            cd.feeAmount = Int64(row.feeAmount)
            cd.memo = row.memo
            cd.receiptImagePath = row.receiptImagePath
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.isTestData = row.isTestData
            cd.recurringTransferSettingId = row.recurringTransferSettingId
            cd.bookId = row.bookId
            cd.isInTrash = row.isInTrash
            cd.trashedAt = row.trashedAt
        }

        for row in snapshot.bankAccounts {
            let cd = CDBankAccountData(context: context)
            cd.id = row.id
            cd.accountName = row.accountName
            cd.initialBalance = row.initialBalance.map { NSNumber(value: $0) }
            cd.memo = row.memo
            cd.isActive = row.isActive
            cd.sortOrder = Int64(row.sortOrder)
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.initialBalanceIncomeId = row.initialBalanceIncomeId
            cd.showAsPaymentMethod = row.showAsPaymentMethod
            cd.showAsReceiveMethod = row.showAsReceiveMethod
            cd.showInAnalysis = row.showInAnalysis
            cd.isAsset = row.isAsset
            cd.recurringTransferSettingId = row.recurringTransferSettingId
            cd.recurringTransferSettingIds = try? JSONEncoder().encode(row.recurringTransferSettingIds)
            cd.isTestData = row.isTestData
            cd.isLocked = row.isLocked
            cd.bookId = row.bookId
            cd.colorHex = row.colorHex
        }

        for row in snapshot.receiveMethods {
            let cd = CDReceiveMethodData(context: context)
            cd.id = row.id
            cd.methodName = row.methodName
            cd.isActive = row.isActive
            cd.sortOrder = Int64(row.sortOrder)
            cd.createdAt = row.createdAt
            cd.bookId = row.bookId
        }

        for row in snapshot.paymentMethodSettings {
            let cd = CDPaymentMethodSettingData(context: context)
            cd.id = row.id
            cd.methodName = row.methodName
            cd.type = row.type
            cd.closingDay = row.closingDay.map { NSNumber(value: $0) }
            cd.withdrawalDay = row.withdrawalDay.map { NSNumber(value: $0) }
            cd.adjustPaymentDateToNextBusinessDay = row.adjustPaymentDateToNextBusinessDay
            cd.holidayAdjustment = row.holidayAdjustment
            cd.bankAccount = row.bankAccount
            cd.withdrawalBankAccountId = row.withdrawalBankAccountId
            cd.memo = row.memo
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.sortOrder = Int64(row.sortOrder)
            cd.isActive = row.isActive
            cd.isAsset = row.isAsset
            cd.assetInitialBalance = row.assetInitialBalance.map { NSNumber(value: $0) }
            cd.includeInAnalysis = row.includeInAnalysis
            cd.assetInitialBalanceIncomeId = row.assetInitialBalanceIncomeId
            cd.assetInitialBalanceExpenseId = row.assetInitialBalanceExpenseId
            cd.showInInputPicker = row.showInInputPicker
            cd.useForReceive = row.useForReceive
            cd.showInAnalysis = row.showInAnalysis
            cd.recurringTransferSettingId = row.recurringTransferSettingId
            cd.recurringTransferSettingIds = try? JSONEncoder().encode(row.recurringTransferSettingIds)
            cd.isTestData = row.isTestData
            cd.isLocked = row.isLocked
            cd.bookId = row.bookId
            cd.colorHex = row.colorHex
        }

        for row in snapshot.budgets {
            let cd = CDBudgetData(context: context)
            cd.id = row.id
            cd.year = Int64(row.year)
            cd.month = Int64(row.month)
            cd.categoryName = row.categoryName
            cd.amount = Int64(row.amount)
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.isTestData = row.isTestData
            cd.bookId = row.bookId
        }

        for row in snapshot.recurringBudgets {
            let cd = CDRecurringBudgetData(context: context)
            cd.id = row.id
            cd.categoryName = row.categoryName
            cd.amount = Int64(row.amount)
            cd.isEnabled = row.isEnabled
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.bookId = row.bookId
        }

        for row in snapshot.fixedExpenses {
            let cd = CDFixedExpenseData(context: context)
            cd.id = row.id
            cd.name = row.name
            cd.amount = Int64(row.amount)
            cd.categoryName = row.categoryName
            cd.paymentMethodType = row.paymentMethodType
            cd.paymentMethodId = row.paymentMethodId
            cd.dayOfMonth = Int64(row.dayOfMonth)
            cd.startDate = row.startDate
            cd.memo = row.memo
            cd.isActive = row.isActive
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.isTestData = row.isTestData
            cd.isLocked = row.isLocked
            cd.bookId = row.bookId
            cd.holidayAdjustment = row.holidayAdjustment
            cd.generatedScheduleMonths = try? JSONEncoder().encode(row.generatedScheduleMonths)
        }

        for row in snapshot.recurringIncomes {
            let cd = CDRecurringIncomeData(context: context)
            cd.id = row.id
            cd.name = row.name
            cd.amount = Int64(row.amount)
            cd.categoryName = row.categoryName
            cd.receiveMethodType = row.receiveMethodType
            cd.receiveMethodId = row.receiveMethodId
            cd.dayOfMonth = Int64(row.dayOfMonth)
            cd.startDate = row.startDate
            cd.memo = row.memo
            cd.isActive = row.isActive
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.isTestData = row.isTestData
            cd.isLocked = row.isLocked
            cd.bookId = row.bookId
            cd.holidayAdjustment = row.holidayAdjustment
            cd.generatedScheduleMonths = try? JSONEncoder().encode(row.generatedScheduleMonths)
        }

        for row in snapshot.recurringTransferSettings {
            let cd = CDRecurringTransferSettingData(context: context)
            cd.id = row.id
            cd.fromMethodId = row.fromMethodId
            cd.fromMethodName = row.fromMethodName
            cd.fromType = row.fromType
            cd.toMethodId = row.toMethodId
            cd.toMethodName = row.toMethodName
            cd.toType = row.toType
            cd.amount = Int64(row.amount)
            cd.day = Int64(row.day)
            cd.startDate = row.startDate
            cd.isActive = row.isActive
            cd.createdAt = row.createdAt
            cd.updatedAt = row.updatedAt
            cd.isLocked = row.isLocked
            cd.isTestData = row.isTestData
            cd.bookId = row.bookId
            cd.holidayAdjustment = row.holidayAdjustment
            cd.generatedScheduleMonths = try? JSONEncoder().encode(row.generatedScheduleMonths)
        }

        guard context.hasChanges else { return }
        try context.save()
    }
}
