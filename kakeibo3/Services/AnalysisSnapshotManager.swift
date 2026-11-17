import CoreData
import os

// MARK: - AnalysisMonthlySnapshot の生成・更新を担う管理クラス
//
// SnapshotManager（カレンダー用）とほぼ同じ構造・チェーン方式だが、月ごとに
// 集計対象の異なる2系統のデータを別々に持つ点が異なるため、別モデル・別マネージャーにしている。
// - 総資産・資産推移用のtotals/日別配列: 「資産に含める」(isAsset)だけで集計対象を決める
//   （DowngradeLockService.isExcludedFromAssetTotal参照）。
// - 支出/収入/決済タブの内訳（カテゴリー別・方法別・件数）: ロック中かどうかだけで判定する
//   （カレンダーと同じ基準。DowngradeLockService.visibleExpenses/visibleIncomes参照）。
//
// Core Data移行（Phase 1・Snapshot系）：CDAnalysisMonthlySnapshotを
// CoreDataStack.shared.container.viewContext経由で直接読み書きする。カテゴリー別/方法別内訳・
// 日別配列はBinary属性のため、JSONEncoder/Decoderで変換する（AnalysisMonthlySnapshotSync.encode/decode参照）。
//
// 【複数帳簿対応】AnalysisMonthlySnapshotは (yearMonth, bookId) の組で一意になる。
// 振替(TransferData)も帳簿をまたがない設計のため、IncomeData/ExpenseDataと同じくbookIdで絞り込む。

enum AnalysisSnapshotManager {

    static let logger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "AnalysisSnapshotManager")

    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 起動時バックフィル

    static func backfillIfNeeded() {
        let existingCount = (try? context.count(for: CDAnalysisMonthlySnapshot.fetchRequest())) ?? 0
        guard existingCount == 0 else { return }
        let result = rebuildAll()
        if result.hasFailures {
            logger.error("backfillIfNeeded: \(result.failedBooks.count) book(s) failed to rebuild")
        }
    }

    // MARK: - 差分更新（取引1件の保存・編集・削除の直後に呼ぶ）

    static func touch(date: Date, bookId: UUID) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        cascadeMonthly(from: day, bookId: bookId)
        try? context.save()
    }

    // MARK: - 1口座ぶんだけの差分更新（SnapshotManager.touchBankAccountと同じ考え方・同じ制約）

    static func touchBankAccount(_ bankAccountId: UUID) {
        let start = Date()
        let paymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let linkedCardNames = paymentMethods
            .filter { $0.type == PaymentMethodType.creditCard.rawValue && $0.withdrawalBankAccountId == bankAccountId }
            .map(\.methodName)

        var dates = datesForBankAccount(bankAccountId)
        for cardName in linkedCardNames {
            dates += datesForMethodName(cardName)
        }
        touchDates(dates)
        logger.debug("touchBankAccount: \(dates.count) dates, \(Date().timeIntervalSince(start), format: .fixed(precision: 3))s")
    }

    // MARK: - 1支払い方法ぶんだけの差分更新

    static func touchMethodName(_ methodName: String) {
        let start = Date()
        let dates = datesForMethodName(methodName)
        touchDates(dates)
        logger.debug("touchMethodName(\(methodName)): \(dates.count) dates, \(Date().timeIntervalSince(start), format: .fixed(precision: 3))s")
    }

    private static func touchDates(_ dates: [(date: Date, bookId: UUID)]) {
        let cal = Calendar.current
        let earliestByBook = Dictionary(grouping: dates, by: \.bookId)
            .compactMapValues { $0.map { cal.startOfDay(for: $0.date) }.min() }
        guard !earliestByBook.isEmpty else { return }

        for (bookId, earliestAffectedDay) in earliestByBook {
            cascadeMonthly(from: earliestAffectedDay, bookId: bookId)
        }
        try? context.save()
    }

    private static func datesForBankAccount(_ bankAccountId: UUID) -> [(date: Date, bookId: UUID)] {
        let expenses = ExpenseDataSync.fetch(matching: NSPredicate(format: "bankAccountId == %@", bankAccountId as CVarArg))
        let incomes = IncomeDataSync.fetch(matching: NSPredicate(format: "bankAccountId == %@", bankAccountId as CVarArg))
        return expenses.compactMap { e in e.bookId.map { (date: e.date, bookId: $0) } }
            + incomes.compactMap { i in i.bookId.map { (date: i.date, bookId: $0) } }
    }

    private static func datesForMethodName(_ methodName: String) -> [(date: Date, bookId: UUID)] {
        guard !methodName.isEmpty else { return [] }
        let expenses = ExpenseDataSync.fetch(matching: NSPredicate(format: "paymentMethod == %@", methodName))
        let incomes = IncomeDataSync.fetch(matching: NSPredicate(format: "receiveMethod == %@", methodName))
        return expenses.compactMap { e in e.bookId.map { (date: e.date, bookId: $0) } }
            + incomes.compactMap { i in i.bookId.map { (date: i.date, bookId: $0) } }
    }

    // MARK: - 全期間再構築
    //
    // SnapshotManagerと同じ方針: 1帳簿を1トランザクションとして専用backgroundContext上で
    // 完結させる(削除〜計算〜挿入〜保存を1回のsaveにまとめ、失敗時はrollbackする)。
    // 全帳簿版は帳簿ごとに独立して実行し、ある帳簿の失敗が他帳簿の結果を巻き戻さない。

    /// 1帳簿だけを対象に再構築する。
    static func rebuildAll(bookId: UUID) throws {
        let start = Date()
        defer { logger.debug("rebuildAll(bookId: \(bookId)): \(Date().timeIntervalSince(start), format: .fixed(precision: 3))s") }

        let backgroundContext = CoreDataStack.shared.container.newBackgroundContext()
        var thrownError: Error?
        backgroundContext.performAndWait {
            do {
                try rebuildOnBackgroundContext(bookId: bookId, context: backgroundContext)
            } catch {
                backgroundContext.rollback()
                thrownError = error
            }
        }
        if let thrownError {
            throw thrownError
        }
    }

    /// 全帳簿を対象に再構築する。帳簿ごとに独立したトランザクションで実行する。
    @discardableResult
    static func rebuildAll() -> SnapshotRebuildResult {
        let backgroundContext = CoreDataStack.shared.container.newBackgroundContext()
        var bookIds: [UUID] = []
        backgroundContext.performAndWait {
            do {
                bookIds = try SnapshotSourceDataLoader.loadAllBookIds(context: backgroundContext)
            } catch {
                logger.error("rebuildAll(): failed to list book IDs: \(String(describing: error))")
            }
        }

        var result = SnapshotRebuildResult()
        for bookId in bookIds {
            do {
                try rebuildAll(bookId: bookId)
                result.recordSuccess(bookId: bookId)
            } catch {
                logger.error("rebuildAll(bookId: \(bookId)) failed: \(String(describing: error))")
                result.recordFailure(bookId: bookId, error: error)
            }
        }
        return result
    }

    // MARK: - Private: 1帳簿ぶんの再構築本体(backgroundContext上で完結させる)

    private static func rebuildOnBackgroundContext(bookId: UUID, context: NSManagedObjectContext) throws {
        let deleteRequest = CDAnalysisMonthlySnapshot.fetchRequest()
        deleteRequest.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        for existing in try context.fetch(deleteRequest) {
            context.delete(existing)
        }

        let source = try SnapshotSourceDataLoader.loadAll(bookId: bookId, context: context)
        let inputs = makeBreakdownInputs(from: source)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let bookDates = source.incomes.map(\.date) + source.expenses.map(\.date) + source.transfers.map(\.date)
        guard let earliestRaw = bookDates.min() else {
            try context.save()
            return
        }
        // SnapshotManagerと同じ不具合修正: 生の取引日時ではなく0時正規化した日付を
        // 月次チェーンの起点にする。
        let earliest = cal.startOfDay(for: earliestRaw)
        let latestDataDay = cal.startOfDay(for: bookDates.max() ?? today)
        let end = max(today, latestDataDay)

        guard var cursor = cal.date(from: cal.dateComponents([.year, .month], from: earliest)),
              let lastMonth = cal.date(from: cal.dateComponents([.year, .month], from: end)) else {
            try context.save()
            return
        }

        let byMonth = groupBreakdownInputsByMonth(inputs, cal: cal)
        let timing = currentAssetReflectionTiming()
        var runningCarryover = 0

        while cursor <= lastMonth {
            let monthItems = byMonth[cursor] ?? MonthBreakdownItems()
            let totals = monthlyTotals(items: monthItems, resolvers: inputs.resolvers)
            let breakdown = buildMonthlyBreakdown(monthStart: cursor, items: monthItems, resolvers: inputs.resolvers)

            let comps = cal.dateComponents([.year, .month], from: cursor)
            let year = comps.year ?? 0
            let month = comps.month ?? 0

            let cd = CDAnalysisMonthlySnapshot(context: context)
            cd.yearMonth = yearMonthKey(year: year, month: month)
            cd.bookId = bookId
            cd.year = Int64(year)
            cd.month = Int64(month)
            cd.incomeTotal = Int64(totals.income)
            cd.expenseTotal = Int64(totals.expense)
            cd.creditCardExpenseTotal = Int64(totals.creditCard)
            cd.transferFeeTotal = Int64(totals.fees)
            cd.carryoverBalance = Int64(runningCarryover)
            cd.updatedAt = Date()
            cd.displayExpenseTotal = Int64(breakdown.displayExpenseTotal)
            cd.displayIncomeTotal = Int64(breakdown.displayIncomeTotal)
            cd.expenseCategoryTotals = AnalysisMonthlySnapshotSync.encode(breakdown.expenseCategoryTotals)
            cd.incomeCategoryTotals = AnalysisMonthlySnapshotSync.encode(breakdown.incomeCategoryTotals)
            cd.paymentMethodTotals = AnalysisMonthlySnapshotSync.encode(breakdown.paymentMethodTotals)
            cd.receiveMethodTotals = AnalysisMonthlySnapshotSync.encode(breakdown.receiveMethodTotals)
            cd.dailyExpenseTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyExpenseTotals)
            cd.dailyIncomeTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyIncomeTotals)
            cd.dailyCreditCardExpenseTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyCreditCardExpenseTotals)
            cd.dailyTransferFeeTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyTransferFeeTotals)
            cd.expenseTransactionCount = Int64(breakdown.expenseTransactionCount)
            cd.incomeTransactionCount = Int64(breakdown.incomeTransactionCount)

            let assetExpense = timing == .withdrawalDate ? totals.expense - totals.creditCard : totals.expense
            runningCarryover += totals.income - assetExpense - totals.fees

            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        try context.save()
    }

    private static func makeBreakdownInputs(from source: SnapshotSourceDataLoader.BookSourceData) -> BreakdownInputs {
        let assetExpenses = DowngradeLockService.assetTotalExpenses(source.expenses, bankAccounts: source.bankAccounts, paymentMethods: source.paymentMethods)
        let assetIncomes = DowngradeLockService.assetTotalIncomes(source.incomes, bankAccounts: source.bankAccounts, paymentMethods: source.paymentMethods)
        let breakdownExpenses = DowngradeLockService.visibleExpenses(source.expenses, bankAccounts: source.bankAccounts, paymentMethods: source.paymentMethods)
        let breakdownIncomes = DowngradeLockService.visibleIncomes(source.incomes, bankAccounts: source.bankAccounts, paymentMethods: source.paymentMethods)

        return BreakdownInputs(
            assetExpenses: assetExpenses, assetIncomes: assetIncomes,
            breakdownExpenses: breakdownExpenses, breakdownIncomes: breakdownIncomes,
            transfers: source.transfers,
            resolvers: BreakdownResolvers(
                categories: source.categories, paymentMethods: source.paymentMethods, receiveMethods: source.receiveMethods,
                creditCardNames: creditCardMethodNames(source.paymentMethods)
            )
        )
    }

    // MARK: - Private: 月次チェーンの差分カスケード（touch用）

    private static func cascadeMonthly(from day: Date, bookId: UUID) {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: day)) else { return }

        let today = cal.startOfDay(for: Date())
        guard let todayMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) else { return }
        let latestExistingMonthStart = latestMonthlySnapshotMonthStart(bookId: bookId) ?? todayMonthStart

        let endMonthStart = [todayMonthStart, latestExistingMonthStart, monthStart].max() ?? monthStart

        let cascadeStart: Date
        if monthStart > latestExistingMonthStart,
           let nextAfterExisting = cal.date(byAdding: .month, value: 1, to: latestExistingMonthStart) {
            cascadeStart = min(monthStart, nextAfterExisting)
        } else {
            cascadeStart = monthStart
        }

        let timing = currentAssetReflectionTiming()
        var runningCarryover = previousMonthEndBalance(before: cascadeStart, bookId: bookId, timing: timing)

        guard let cascadeEndExclusive = cal.date(byAdding: .month, value: 1, to: endMonthStart) else { return }
        let existingMonthlyByKey = Dictionary(
            uniqueKeysWithValues: fetchCDMonthlySnapshots(from: cascadeStart, to: cascadeEndExclusive, bookId: bookId)
                .compactMap { snap -> (String, CDAnalysisMonthlySnapshot)? in
                    guard let key = snap.yearMonth else { return nil }
                    return (key, snap)
                }
        )

        let breakdownInputs = fetchBreakdownInputs(from: cascadeStart, to: cascadeEndExclusive, bookId: bookId)
        let byMonth = groupBreakdownInputsByMonth(breakdownInputs, cal: cal)

        var cursor = cascadeStart
        while cursor <= endMonthStart {
            let key = yearMonthComponentsKey(cursor)
            let monthItems = byMonth[cursor] ?? MonthBreakdownItems()
            let totals = monthlyTotals(items: monthItems, resolvers: breakdownInputs.resolvers)
            let breakdown = buildMonthlyBreakdown(monthStart: cursor, items: monthItems, resolvers: breakdownInputs.resolvers)
            let snapshot = upsertMonthlySnapshot(
                monthStart: cursor, bookId: bookId, carryoverBalance: runningCarryover,
                totals: totals, breakdown: breakdown, existing: existingMonthlyByKey[key]
            )
            runningCarryover += monthlyAssetNetTotal(snapshot, assetReflectionTiming: timing)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
    }

    @discardableResult
    private static func upsertMonthlySnapshot(
        monthStart: Date, bookId: UUID, carryoverBalance: Int,
        totals: (income: Int, expense: Int, creditCard: Int, fees: Int),
        breakdown: MonthlyBreakdown,
        existing: CDAnalysisMonthlySnapshot? = nil, skipExistingLookup: Bool = false
    ) -> CDAnalysisMonthlySnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthStart)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let key = yearMonthKey(year: year, month: month)

        let snapshot: CDAnalysisMonthlySnapshot
        if let existing {
            snapshot = existing
        } else if skipExistingLookup {
            let created = CDAnalysisMonthlySnapshot(context: context)
            created.yearMonth = key
            created.bookId = bookId
            created.year = Int64(year)
            created.month = Int64(month)
            snapshot = created
        } else {
            snapshot = fetchCDMonthlySnapshot(key, bookId: bookId) ?? {
                let created = CDAnalysisMonthlySnapshot(context: context)
                created.yearMonth = key
                created.bookId = bookId
                created.year = Int64(year)
                created.month = Int64(month)
                return created
            }()
        }
        snapshot.incomeTotal = Int64(totals.income)
        snapshot.expenseTotal = Int64(totals.expense)
        snapshot.creditCardExpenseTotal = Int64(totals.creditCard)
        snapshot.transferFeeTotal = Int64(totals.fees)
        snapshot.carryoverBalance = Int64(carryoverBalance)
        snapshot.updatedAt = Date()

        snapshot.displayExpenseTotal = Int64(breakdown.displayExpenseTotal)
        snapshot.displayIncomeTotal = Int64(breakdown.displayIncomeTotal)

        snapshot.expenseCategoryTotals = AnalysisMonthlySnapshotSync.encode(breakdown.expenseCategoryTotals)
        snapshot.incomeCategoryTotals = AnalysisMonthlySnapshotSync.encode(breakdown.incomeCategoryTotals)
        snapshot.paymentMethodTotals = AnalysisMonthlySnapshotSync.encode(breakdown.paymentMethodTotals)
        snapshot.receiveMethodTotals = AnalysisMonthlySnapshotSync.encode(breakdown.receiveMethodTotals)
        snapshot.dailyExpenseTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyExpenseTotals)
        snapshot.dailyIncomeTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyIncomeTotals)
        snapshot.dailyCreditCardExpenseTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyCreditCardExpenseTotals)
        snapshot.dailyTransferFeeTotals = AnalysisMonthlySnapshotSync.encode(breakdown.dailyTransferFeeTotals)
        snapshot.expenseTransactionCount = Int64(breakdown.expenseTransactionCount)
        snapshot.incomeTransactionCount = Int64(breakdown.incomeTransactionCount)

        return snapshot
    }

    private static func previousMonthEndBalance(
        before monthStart: Date, bookId: UUID, timing: CreditCardAssetReflectionTiming
    ) -> Int {
        let cal = Calendar.current
        guard let prevMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return 0 }
        let key = yearMonthComponentsKey(prevMonthStart)
        guard let prev = fetchCDMonthlySnapshot(key, bookId: bookId) else { return 0 }
        return monthlyEndOfMonthBalance(prev, assetReflectionTiming: timing)
    }

    private static func latestMonthlySnapshotMonthStart(bookId: UUID) -> Date? {
        let request = CDAnalysisMonthlySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "yearMonth", ascending: false)]
        request.fetchLimit = 1
        guard let latest = (try? context.fetch(request))?.first else { return nil }
        var comps = DateComponents()
        comps.year = Int(latest.year)
        comps.month = Int(latest.month)
        comps.day = 1
        return Calendar.current.date(from: comps)
    }

    // MARK: - Private: その月のtotals（income/expense/creditCard/fees）を生データから合算する

    private static func monthlyTotals(
        items: MonthBreakdownItems, resolvers: BreakdownResolvers
    ) -> (income: Int, expense: Int, creditCard: Int, fees: Int) {
        let income = items.assetIncomes.reduce(0) { $0 + $1.amount }
        let expense = items.assetExpenses.reduce(0) { $0 + $1.amount }
        let creditCard = items.assetExpenses.filter { resolvers.creditCardNames.contains($0.paymentMethod) }.reduce(0) { $0 + $1.amount }
        let fees = items.transfers.reduce(0) { $0 + $1.feeAmount }
        return (income, expense, creditCard, fees)
    }

    // MARK: - Private: カテゴリー別・方法別内訳 + 日別配列の組み立て

    private struct MonthlyBreakdown {
        var expenseCategoryTotals: [AnalysisCategoryAmount] = []
        var incomeCategoryTotals: [AnalysisCategoryAmount] = []
        var paymentMethodTotals: [AnalysisMethodAmount] = []
        var receiveMethodTotals: [AnalysisMethodAmount] = []
        var dailyExpenseTotals: [Int] = []
        var dailyIncomeTotals: [Int] = []
        var dailyCreditCardExpenseTotals: [Int] = []
        var dailyTransferFeeTotals: [Int] = []
        var expenseTransactionCount: Int = 0
        var incomeTransactionCount: Int = 0
        var displayExpenseTotal: Int = 0
        var displayIncomeTotal: Int = 0
    }

    private struct BreakdownResolvers {
        let categories: [CategoryData]
        let paymentMethods: [PaymentMethodSettingData]
        let receiveMethods: [ReceiveMethodData]
        let creditCardNames: Set<String>
    }

    private struct BreakdownInputs {
        let assetExpenses: [ExpenseData]
        let assetIncomes: [IncomeData]
        let breakdownExpenses: [ExpenseData]
        let breakdownIncomes: [IncomeData]
        let transfers: [TransferData]
        let resolvers: BreakdownResolvers
    }

    private struct MonthBreakdownItems {
        var assetExpenses: [ExpenseData] = []
        var assetIncomes: [IncomeData] = []
        var breakdownExpenses: [ExpenseData] = []
        var breakdownIncomes: [IncomeData] = []
        var transfers: [TransferData] = []
    }

    private static func fetchBreakdownInputs(from start: Date, to end: Date, bookId: UUID) -> BreakdownInputs {
        let bankAccounts = BankAccountDataSync.fetchAll(bookId: bookId)
        let paymentMethods = PaymentMethodSettingDataSync.fetchAll(bookId: bookId)
        let receiveMethods = ReceiveMethodDataSync.fetchAll(bookId: bookId)
        let categories = CategoryDataSync.fetchAll(bookId: bookId)

        let rawExpenses = ExpenseDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", start as NSDate, end as NSDate, bookId as CVarArg))
        let rawIncomes = IncomeDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", start as NSDate, end as NSDate, bookId as CVarArg))
        let transfers = TransferDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", start as NSDate, end as NSDate, bookId as CVarArg))

        let assetExpenses = DowngradeLockService.assetTotalExpenses(rawExpenses, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        let assetIncomes = DowngradeLockService.assetTotalIncomes(rawIncomes, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        let breakdownExpenses = DowngradeLockService.visibleExpenses(rawExpenses, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        let breakdownIncomes = DowngradeLockService.visibleIncomes(rawIncomes, bankAccounts: bankAccounts, paymentMethods: paymentMethods)

        return BreakdownInputs(
            assetExpenses: assetExpenses, assetIncomes: assetIncomes,
            breakdownExpenses: breakdownExpenses, breakdownIncomes: breakdownIncomes,
            transfers: transfers,
            resolvers: BreakdownResolvers(
                categories: categories, paymentMethods: paymentMethods, receiveMethods: receiveMethods,
                creditCardNames: creditCardMethodNames(paymentMethods)
            )
        )
    }

    private static func groupBreakdownInputsByMonth(_ inputs: BreakdownInputs, cal: Calendar) -> [Date: MonthBreakdownItems] {
        var byMonth: [Date: MonthBreakdownItems] = [:]
        for e in inputs.assetExpenses {
            guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: e.date)) else { continue }
            byMonth[ms, default: MonthBreakdownItems()].assetExpenses.append(e)
        }
        for i in inputs.assetIncomes {
            guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: i.date)) else { continue }
            byMonth[ms, default: MonthBreakdownItems()].assetIncomes.append(i)
        }
        for e in inputs.breakdownExpenses {
            guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: e.date)) else { continue }
            byMonth[ms, default: MonthBreakdownItems()].breakdownExpenses.append(e)
        }
        for i in inputs.breakdownIncomes {
            guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: i.date)) else { continue }
            byMonth[ms, default: MonthBreakdownItems()].breakdownIncomes.append(i)
        }
        for t in inputs.transfers {
            guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: t.date)) else { continue }
            byMonth[ms, default: MonthBreakdownItems()].transfers.append(t)
        }
        return byMonth
    }

    private static func buildMonthlyBreakdown(
        monthStart: Date, items: MonthBreakdownItems, resolvers: BreakdownResolvers
    ) -> MonthlyBreakdown {
        var result = MonthlyBreakdown()

        let feeItems = items.transfers.filter { $0.feeAmount > 0 }.map { (category: "手数料", amount: $0.feeAmount) }
        let expenseCategoryItems = items.breakdownExpenses.map { (category: $0.category, amount: $0.amount) } + feeItems
        result.expenseCategoryTotals = categoryBreakdown(items: expenseCategoryItems, type: "支出", categories: resolvers.categories)
        result.incomeCategoryTotals = categoryBreakdown(
            items: items.breakdownIncomes.map { (category: $0.category, amount: $0.amount) }, type: "収入", categories: resolvers.categories
        )
        result.paymentMethodTotals = methodBreakdown(
            items: items.breakdownExpenses.map { (method: $0.paymentMethod, amount: $0.amount) },
            paymentMethods: resolvers.paymentMethods, receiveMethods: resolvers.receiveMethods
        )
        result.receiveMethodTotals = methodBreakdown(
            items: items.breakdownIncomes.map { (method: $0.receiveMethod, amount: $0.amount) },
            paymentMethods: resolvers.paymentMethods, receiveMethods: resolvers.receiveMethods
        )
        result.expenseTransactionCount = items.breakdownExpenses.count + feeItems.count
        result.incomeTransactionCount = items.breakdownIncomes.count

        result.displayExpenseTotal = items.breakdownExpenses.reduce(0) { $0 + $1.amount }
            + items.transfers.reduce(0) { $0 + $1.feeAmount }
        result.displayIncomeTotal = items.breakdownIncomes.reduce(0) { $0 + $1.amount }

        let cal = Calendar.current
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        var dailyExpense = [Int](repeating: 0, count: daysInMonth)
        var dailyIncome = [Int](repeating: 0, count: daysInMonth)
        var dailyCreditCard = [Int](repeating: 0, count: daysInMonth)
        var dailyFees = [Int](repeating: 0, count: daysInMonth)

        for e in items.assetExpenses {
            let idx = cal.component(.day, from: e.date) - 1
            guard idx >= 0 && idx < daysInMonth else { continue }
            dailyExpense[idx] += e.amount
            if resolvers.creditCardNames.contains(e.paymentMethod) {
                dailyCreditCard[idx] += e.amount
            }
        }
        for i in items.assetIncomes {
            let idx = cal.component(.day, from: i.date) - 1
            guard idx >= 0 && idx < daysInMonth else { continue }
            dailyIncome[idx] += i.amount
        }
        for t in items.transfers {
            let idx = cal.component(.day, from: t.date) - 1
            guard idx >= 0 && idx < daysInMonth else { continue }
            dailyFees[idx] += t.feeAmount
        }

        result.dailyExpenseTotals = dailyExpense
        result.dailyIncomeTotals = dailyIncome
        result.dailyCreditCardExpenseTotals = dailyCreditCard
        result.dailyTransferFeeTotals = dailyFees

        return result
    }

    private static func categoryBreakdown(
        items: [(category: String, amount: Int)], type: String, categories: [CategoryData]
    ) -> [AnalysisCategoryAmount] {
        var totals: [String: Int] = [:]
        for item in items { totals[item.category, default: 0] += item.amount }
        let total = totals.values.reduce(0, +)
        guard total > 0 else { return [] }
        return totals.map { name, amount in
            let categoryId = categories.first(where: { $0.name == name && $0.type == type })?.id
            let percentage = Double(amount) / Double(total) * 100
            return AnalysisCategoryAmount(categoryId: categoryId, categoryName: name, amount: amount, percentage: percentage)
        }
    }

    private static func methodBreakdown(
        items: [(method: String, amount: Int)], paymentMethods: [PaymentMethodSettingData], receiveMethods: [ReceiveMethodData]
    ) -> [AnalysisMethodAmount] {
        var totals: [String: Int] = [:]
        for item in items { totals[item.method, default: 0] += item.amount }
        let total = totals.values.reduce(0, +)
        guard total > 0 else { return [] }
        return totals.map { name, amount in
            let methodId = paymentMethods.first(where: { $0.methodName == name })?.id
                ?? receiveMethods.first(where: { $0.methodName == name })?.id
            let percentage = Double(amount) / Double(total) * 100
            return AnalysisMethodAmount(methodId: methodId, methodName: name, amount: amount, percentage: percentage)
        }
    }

    // MARK: - Private: フェッチ系ヘルパー（CD型を直接扱う）

    private static func fetchCDMonthlySnapshot(_ key: String, bookId: UUID) -> CDAnalysisMonthlySnapshot? {
        let request = CDAnalysisMonthlySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "yearMonth == %@ AND bookId == %@", key, bookId as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private static func fetchCDMonthlySnapshots(from start: Date, to end: Date, bookId: UUID) -> [CDAnalysisMonthlySnapshot] {
        let cal = Calendar.current
        func monthIndex(_ d: Date) -> Int {
            let c = cal.dateComponents([.year, .month], from: d)
            return (c.year ?? 0) * 12 + (c.month ?? 0)
        }
        let startIdx = monthIndex(start)
        let endIdx = monthIndex(end)
        let request = CDAnalysisMonthlySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        let all = (try? context.fetch(request)) ?? []
        return all.filter { snap in
            let idx = Int(snap.year) * 12 + Int(snap.month)
            return idx >= startIdx && idx < endIdx
        }
    }

    // MARK: - Private: CD型に対する計算プロパティ相当

    private static func monthlyAssetNetTotal(_ cd: CDAnalysisMonthlySnapshot, assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        let assetExpense = assetReflectionTiming == .withdrawalDate
            ? Int(cd.expenseTotal) - Int(cd.creditCardExpenseTotal)
            : Int(cd.expenseTotal)
        return Int(cd.incomeTotal) - assetExpense - Int(cd.transferFeeTotal)
    }

    private static func monthlyEndOfMonthBalance(_ cd: CDAnalysisMonthlySnapshot, assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        Int(cd.carryoverBalance) + monthlyAssetNetTotal(cd, assetReflectionTiming: assetReflectionTiming)
    }

    // MARK: - Private: その他ヘルパー

    private static func creditCardMethodNames(_ paymentMethods: [PaymentMethodSettingData]) -> Set<String> {
        Set(paymentMethods.filter { $0.type == PaymentMethodType.creditCard.rawValue }.map(\.methodName))
    }

    private static func currentAssetReflectionTiming() -> CreditCardAssetReflectionTiming {
        let raw = UserDefaults.standard.string(forKey: CreditCardAssetReflectionTiming.storageKey)
        return raw.flatMap { CreditCardAssetReflectionTiming(rawValue: $0) } ?? CreditCardAssetReflectionTiming.defaultValue
    }

    private static func yearMonthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    private static func yearMonthComponentsKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return yearMonthKey(year: comps.year ?? 0, month: comps.month ?? 0)
    }
}
