import Foundation
import SwiftData

// MARK: - 旧SwiftDataストアの安全な読み取り
//
// 「書き込みメソッドを呼ばないだけ」は読み取り専用として扱わない方針のため、
// 元の default.store / -wal / -shm には一切触れず、必ず一時ディレクトリへ
// コピーしてからコピー側だけを ModelContainer で開く。WALに未checkpointの
// 差分があってもコピー側だけに反映されるため、元ストアは常に無傷のまま残る。
//
// import SwiftData はMigration層(このファイルとLegacy/配下)だけに隔離し、
// 通常のView・Repository・Serviceからは参照しない。

enum LegacyReaderError: Error, Equatable {
    case storeNotFound
}

enum SwiftDataLegacyReader {

    struct LegacyStorePaths {
        let store: URL
        let wal: URL
        let shm: URL
    }

    // MARK: - ストアの所在確認

    static func applicationSupportDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// default.store が実在する場合のみパス一式を返す(-wal/-shmは無くてもよい)
    static func legacyStorePaths() -> LegacyStorePaths? {
        guard let appSupport = applicationSupportDirectory() else { return nil }
        let store = appSupport.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: store.path) else { return nil }
        return LegacyStorePaths(
            store: store,
            wal: appSupport.appendingPathComponent("default.store-wal"),
            shm: appSupport.appendingPathComponent("default.store-shm")
        )
    }

    static func legacyStoreExists() -> Bool {
        legacyStorePaths() != nil
    }

    // MARK: - 読み取り

    /// default.store(+wal/shm)を一時ディレクトリへコピーし、コピー側だけをSwiftDataで開いて
    /// 全17モデルをプレーンなDTOへ変換して返す。元の旧ストアは一切変更しない。
    static func readSnapshot() throws -> LegacySnapshot {
        try readSnapshot(paths: legacyStorePaths())
    }

    /// テスト用に任意のストアパスを指定できるオーバーロード
    static func readSnapshot(paths explicitPaths: LegacyStorePaths?) throws -> LegacySnapshot {
        guard let paths = explicitPaths else {
            throw LegacyReaderError.storeNotFound
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataLegacyReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let copiedStore = workDir.appendingPathComponent("default.store")
        try FileManager.default.copyItem(at: paths.store, to: copiedStore)
        for sidecar in [paths.wal, paths.shm] where FileManager.default.fileExists(atPath: sidecar.path) {
            let destination = workDir.appendingPathComponent(sidecar.lastPathComponent)
            try FileManager.default.copyItem(at: sidecar, to: destination)
        }

        let schema = Schema(LegacySchema.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: copiedStore, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        var snapshot = LegacySnapshot()
        snapshot.books = try context.fetch(FetchDescriptor<LegacyBookData>()).map(map)
        snapshot.categories = try context.fetch(FetchDescriptor<LegacyCategoryData>()).map(map)
        snapshot.expenses = try context.fetch(FetchDescriptor<LegacyExpenseData>()).map(map)
        snapshot.incomes = try context.fetch(FetchDescriptor<LegacyIncomeData>()).map(map)
        snapshot.transfers = try context.fetch(FetchDescriptor<LegacyTransferData>()).map(map)
        snapshot.bankAccounts = try context.fetch(FetchDescriptor<LegacyBankAccountData>()).map(map)
        snapshot.receiveMethods = try context.fetch(FetchDescriptor<LegacyReceiveMethodData>()).map(map)
        snapshot.paymentMethodSettings = try context.fetch(FetchDescriptor<LegacyPaymentMethodSettingData>()).map(map)
        snapshot.budgets = try context.fetch(FetchDescriptor<LegacyBudgetData>()).map(map)
        snapshot.recurringBudgets = try context.fetch(FetchDescriptor<LegacyRecurringBudgetData>()).map(map)
        snapshot.fixedExpenses = try context.fetch(FetchDescriptor<LegacyFixedExpenseData>()).map(map)
        snapshot.recurringIncomes = try context.fetch(FetchDescriptor<LegacyRecurringIncomeData>()).map(map)
        snapshot.recurringTransferSettings = try context.fetch(FetchDescriptor<LegacyRecurringTransferSettingData>()).map(map)

        // 再生成する派生データ4種:件数把握のみに使う(Core Dataへは書き込まない)
        snapshot.dailySnapshots = try context.fetch(FetchDescriptor<LegacyDailySnapshot>()).map(map)
        snapshot.monthlySnapshots = try context.fetch(FetchDescriptor<LegacyMonthlySnapshot>()).map(map)
        snapshot.analysisMonthlySnapshots = try context.fetch(FetchDescriptor<LegacyAnalysisMonthlySnapshot>()).map(map)
        snapshot.assetGraphCaches = try context.fetch(FetchDescriptor<LegacyAssetGraphCacheData>()).map(map)

        return snapshot
    }

    // MARK: - @Model -> DTO マッピング(名前突合は一切行わない、フィールドのコピーのみ)

    private static func map(_ m: LegacyBookData) -> LegacyBookDataDTO {
        LegacyBookDataDTO(
            id: m.id, name: m.name, createdAt: m.createdAt, updatedAt: m.updatedAt,
            sortOrder: m.sortOrder, isArchived: m.isArchived, isMain: m.isMain
        )
    }

    private static func map(_ m: LegacyCategoryData) -> LegacyCategoryDataDTO {
        LegacyCategoryDataDTO(
            id: m.id, name: m.name, colorHex: m.colorHex, type: m.type, sortOrder: m.sortOrder,
            createdAt: m.createdAt, updatedAt: m.updatedAt, isTestData: m.isTestData,
            bookId: m.bookId, isSuspended: m.isSuspended, isProtected: m.isProtected
        )
    }

    private static func map(_ m: LegacyExpenseData) -> LegacyExpenseDataDTO {
        LegacyExpenseDataDTO(
            id: m.id, amount: m.amount, date: m.date, paymentMethod: m.paymentMethod,
            category: m.category, memo: m.memo, createdAt: m.createdAt, updatedAt: m.updatedAt,
            bookId: m.bookId, bankAccountId: m.bankAccountId, fixedExpenseId: m.fixedExpenseId,
            receiptImagePath: m.receiptImagePath, isTestData: m.isTestData,
            isInTrash: m.isInTrash, trashedAt: m.trashedAt
        )
    }

    private static func map(_ m: LegacyIncomeData) -> LegacyIncomeDataDTO {
        LegacyIncomeDataDTO(
            id: m.id, amount: m.amount, date: m.date, receiveMethod: m.receiveMethod,
            category: m.category, memo: m.memo, createdAt: m.createdAt, updatedAt: m.updatedAt,
            bookId: m.bookId, bankAccountId: m.bankAccountId, recurringIncomeId: m.recurringIncomeId,
            receiptImagePath: m.receiptImagePath, isTestData: m.isTestData,
            isInTrash: m.isInTrash, trashedAt: m.trashedAt
        )
    }

    private static func map(_ m: LegacyTransferData) -> LegacyTransferDataDTO {
        LegacyTransferDataDTO(
            id: m.id, date: m.date, fromType: m.fromType, fromId: m.fromId, fromName: m.fromName,
            toType: m.toType, toId: m.toId, toName: m.toName, amount: m.amount, feeAmount: m.feeAmount,
            memo: m.memo, receiptImagePath: m.receiptImagePath, createdAt: m.createdAt,
            updatedAt: m.updatedAt, isTestData: m.isTestData,
            recurringTransferSettingId: m.recurringTransferSettingId, bookId: m.bookId,
            isInTrash: m.isInTrash, trashedAt: m.trashedAt
        )
    }

    private static func map(_ m: LegacyBankAccountData) -> LegacyBankAccountDataDTO {
        LegacyBankAccountDataDTO(
            id: m.id, accountName: m.accountName, initialBalance: m.initialBalance, memo: m.memo,
            isActive: m.isActive, sortOrder: m.sortOrder, createdAt: m.createdAt, updatedAt: m.updatedAt,
            initialBalanceIncomeId: m.initialBalanceIncomeId, showAsPaymentMethod: m.showAsPaymentMethod,
            showAsReceiveMethod: m.showAsReceiveMethod, showInAnalysis: m.showInAnalysis, isAsset: m.isAsset,
            recurringTransferSettingId: m.recurringTransferSettingId,
            recurringTransferSettingIds: m.recurringTransferSettingIds, isTestData: m.isTestData,
            isLocked: m.isLocked, bookId: m.bookId, colorHex: m.colorHex
        )
    }

    private static func map(_ m: LegacyReceiveMethodData) -> LegacyReceiveMethodDataDTO {
        LegacyReceiveMethodDataDTO(
            id: m.id, methodName: m.methodName, isActive: m.isActive, sortOrder: m.sortOrder,
            createdAt: m.createdAt, updatedAt: m.updatedAt, bookId: m.bookId
        )
    }

    private static func map(_ m: LegacyPaymentMethodSettingData) -> LegacyPaymentMethodSettingDataDTO {
        LegacyPaymentMethodSettingDataDTO(
            id: m.id, methodName: m.methodName, type: m.type, closingDay: m.closingDay,
            withdrawalDay: m.withdrawalDay,
            adjustPaymentDateToNextBusinessDay: m.adjustPaymentDateToNextBusinessDay,
            holidayAdjustment: m.holidayAdjustment, bankAccount: m.bankAccount,
            withdrawalBankAccountId: m.withdrawalBankAccountId, memo: m.memo, createdAt: m.createdAt,
            updatedAt: m.updatedAt, sortOrder: m.sortOrder, isActive: m.isActive, isAsset: m.isAsset,
            assetInitialBalance: m.assetInitialBalance, includeInAnalysis: m.includeInAnalysis,
            assetInitialBalanceIncomeId: m.assetInitialBalanceIncomeId,
            assetInitialBalanceExpenseId: m.assetInitialBalanceExpenseId,
            showInInputPicker: m.showInInputPicker, useForReceive: m.useForReceive,
            showInAnalysis: m.showInAnalysis, recurringTransferSettingId: m.recurringTransferSettingId,
            recurringTransferSettingIds: m.recurringTransferSettingIds, isTestData: m.isTestData,
            isLocked: m.isLocked, bookId: m.bookId, colorHex: m.colorHex
        )
    }

    private static func map(_ m: LegacyBudgetData) -> LegacyBudgetDataDTO {
        LegacyBudgetDataDTO(
            id: m.id, year: m.year, month: m.month, categoryName: m.categoryName, amount: m.amount,
            createdAt: m.createdAt, updatedAt: m.updatedAt, isTestData: m.isTestData, bookId: m.bookId
        )
    }

    private static func map(_ m: LegacyRecurringBudgetData) -> LegacyRecurringBudgetDataDTO {
        LegacyRecurringBudgetDataDTO(
            id: m.id, categoryName: m.categoryName, amount: m.amount, isEnabled: m.isEnabled,
            createdAt: m.createdAt, updatedAt: m.updatedAt, bookId: m.bookId
        )
    }

    private static func map(_ m: LegacyFixedExpenseData) -> LegacyFixedExpenseDataDTO {
        LegacyFixedExpenseDataDTO(
            id: m.id, name: m.name, amount: m.amount, categoryName: m.categoryName,
            paymentMethodType: m.paymentMethodType, paymentMethodId: m.paymentMethodId,
            dayOfMonth: m.dayOfMonth, startDate: m.startDate, memo: m.memo, isActive: m.isActive,
            createdAt: m.createdAt, updatedAt: m.updatedAt, isTestData: m.isTestData,
            isLocked: m.isLocked, bookId: m.bookId, holidayAdjustment: m.holidayAdjustment,
            generatedScheduleMonths: m.generatedScheduleMonths
        )
    }

    private static func map(_ m: LegacyRecurringIncomeData) -> LegacyRecurringIncomeDataDTO {
        LegacyRecurringIncomeDataDTO(
            id: m.id, name: m.name, amount: m.amount, categoryName: m.categoryName,
            receiveMethodType: m.receiveMethodType, receiveMethodId: m.receiveMethodId,
            dayOfMonth: m.dayOfMonth, startDate: m.startDate, memo: m.memo, isActive: m.isActive,
            createdAt: m.createdAt, updatedAt: m.updatedAt, isTestData: m.isTestData,
            isLocked: m.isLocked, bookId: m.bookId, holidayAdjustment: m.holidayAdjustment,
            generatedScheduleMonths: m.generatedScheduleMonths
        )
    }

    private static func map(_ m: LegacyRecurringTransferSettingData) -> LegacyRecurringTransferSettingDataDTO {
        LegacyRecurringTransferSettingDataDTO(
            id: m.id, fromMethodId: m.fromMethodId, fromMethodName: m.fromMethodName,
            fromType: m.fromType, toMethodId: m.toMethodId, toMethodName: m.toMethodName,
            toType: m.toType, amount: m.amount, day: m.day, startDate: m.startDate,
            isActive: m.isActive, createdAt: m.createdAt, updatedAt: m.updatedAt,
            isLocked: m.isLocked, isTestData: m.isTestData, bookId: m.bookId,
            holidayAdjustment: m.holidayAdjustment, generatedScheduleMonths: m.generatedScheduleMonths
        )
    }

    private static func map(_ m: LegacyDailySnapshot) -> LegacyDailySnapshotDTO {
        LegacyDailySnapshotDTO(
            date: m.date, bookId: m.bookId, incomeTotal: m.incomeTotal, expenseTotal: m.expenseTotal,
            creditCardExpenseTotal: m.creditCardExpenseTotal, transferFeeTotal: m.transferFeeTotal,
            transactionCount: m.transactionCount, updatedAt: m.updatedAt
        )
    }

    private static func map(_ m: LegacyMonthlySnapshot) -> LegacyMonthlySnapshotDTO {
        LegacyMonthlySnapshotDTO(
            yearMonth: m.yearMonth, bookId: m.bookId, year: m.year, month: m.month,
            incomeTotal: m.incomeTotal, expenseTotal: m.expenseTotal,
            creditCardExpenseTotal: m.creditCardExpenseTotal, transferFeeTotal: m.transferFeeTotal,
            carryoverBalance: m.carryoverBalance, rawCarryoverBalance: m.rawCarryoverBalance,
            updatedAt: m.updatedAt
        )
    }

    private static func map(_ m: LegacyAnalysisMonthlySnapshot) -> LegacyAnalysisMonthlySnapshotDTO {
        LegacyAnalysisMonthlySnapshotDTO(
            yearMonth: m.yearMonth, bookId: m.bookId, year: m.year, month: m.month,
            incomeTotal: m.incomeTotal, expenseTotal: m.expenseTotal,
            creditCardExpenseTotal: m.creditCardExpenseTotal, transferFeeTotal: m.transferFeeTotal,
            carryoverBalance: m.carryoverBalance, updatedAt: m.updatedAt,
            displayExpenseTotal: m.displayExpenseTotal, displayIncomeTotal: m.displayIncomeTotal,
            expenseCategoryTotals: m.expenseCategoryTotals.map {
                LegacyAnalysisCategoryAmountDTO(categoryId: $0.categoryId, categoryName: $0.categoryName, amount: $0.amount, percentage: $0.percentage)
            },
            incomeCategoryTotals: m.incomeCategoryTotals.map {
                LegacyAnalysisCategoryAmountDTO(categoryId: $0.categoryId, categoryName: $0.categoryName, amount: $0.amount, percentage: $0.percentage)
            },
            paymentMethodTotals: m.paymentMethodTotals.map {
                LegacyAnalysisMethodAmountDTO(methodId: $0.methodId, methodName: $0.methodName, amount: $0.amount, percentage: $0.percentage)
            },
            receiveMethodTotals: m.receiveMethodTotals.map {
                LegacyAnalysisMethodAmountDTO(methodId: $0.methodId, methodName: $0.methodName, amount: $0.amount, percentage: $0.percentage)
            },
            expenseTransactionCount: m.expenseTransactionCount, incomeTransactionCount: m.incomeTransactionCount,
            dailyExpenseTotals: m.dailyExpenseTotals, dailyIncomeTotals: m.dailyIncomeTotals,
            dailyCreditCardExpenseTotals: m.dailyCreditCardExpenseTotals, dailyTransferFeeTotals: m.dailyTransferFeeTotals
        )
    }

    private static func map(_ m: LegacyAssetGraphCacheData) -> LegacyAssetGraphCacheDataDTO {
        LegacyAssetGraphCacheDataDTO(
            id: m.id, bookId: m.bookId, updatedAt: m.updatedAt, maxPointsUsed: m.maxPointsUsed,
            granularityUsed: m.granularityUsed, firstDate: m.firstDate, lastDate: m.lastDate,
            points: m.points.map { LegacyAssetGraphCachePointDTO(date: $0.date, value: $0.value) }
        )
    }
}
