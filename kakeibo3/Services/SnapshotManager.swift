import CoreData
import os

// MARK: - DailySnapshot / MonthlySnapshot の生成・更新を担う管理クラス
//
// カレンダーView・分析Viewが「毎回全履歴をスキャンして集計する」のを避けるため、
// 取引の保存・編集・削除のたびに影響範囲だけを差分更新し、事前計算済みの集計を
// DailySnapshot/MonthlySnapshotに保持する。DowngradeLockService等と同じ流儀で、
// 状態を持たない static func の enum にする。
//
// Core Data移行（Phase 1・Snapshot系）：CDDailySnapshot/CDMonthlySnapshotを
// CoreDataStack.shared.container.viewContext経由で直接読み書きする。
// DailySnapshotSync/MonthlySnapshotSyncはView向けの読み取り専用APIのみを提供し、
// ここでは書き込み（find-or-create+属性更新+save）を直接行う。
//
// 【複数帳簿対応】DailySnapshot/MonthlySnapshotは (date/yearMonth, bookId) の組で一意になる。
// 振替(TransferData)は帳簿をまたがない設計のため、IncomeData/ExpenseDataと同じくbookIdで絞り込む。
//
// carryoverBalance は MonthlySnapshot.swift のコメントの通りチェーン方式。carryoverの連鎖は
// 帳簿ごとに独立している。touch() は「編集した日」から「現在存在する最新の月」までの
// carryoverBalance を連鎖的に再計算する。ロック状態・資産反映タイミングの変更など、
// 複数日にまたがって計上内容そのものが変わる操作の後は rebuildAll() で全期間を作り直す。

enum SnapshotManager {

    static let logger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "SnapshotManager")

    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 起動時バックフィル

    // アプリ起動時に1回だけ呼ぶ。MonthlySnapshotが1件も無ければ初回とみなし、
    // 既存の全ExpenseData/IncomeData/TransferDataから全期間ぶんを構築する。
    static func backfillIfNeeded() {
        let existingCount = (try? context.count(for: CDMonthlySnapshot.fetchRequest())) ?? 0
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

        // 同名の支払い方法（例：どの帳簿にもある「現金」）が複数帳簿にあっても、
        // ロック判定・クレジットカード判定は必ずこの帳簿の口座・支払い方法だけを見て行う。
        let bankAccounts = BankAccountDataSync.fetchAll(bookId: bookId)
        let paymentMethods = PaymentMethodSettingDataSync.fetchAll(bookId: bookId)
        let creditCardNames = creditCardMethodNames(paymentMethods)

        let dayIncomes = DowngradeLockService.visibleIncomes(
            fetchIncomes(on: day, bookId: bookId), bankAccounts: bankAccounts, paymentMethods: paymentMethods
        )
        let dayExpenses = DowngradeLockService.visibleExpenses(
            fetchExpenses(on: day, bookId: bookId), bankAccounts: bankAccounts, paymentMethods: paymentMethods
        )
        let dayTransfers = fetchTransfers(on: day, bookId: bookId)

        upsertDailySnapshot(
            day: day, bookId: bookId, incomes: dayIncomes, expenses: dayExpenses, transfers: dayTransfers,
            creditCardNames: creditCardNames
        )
        cascadeMonthly(from: day, bookId: bookId)
        try? context.save()
    }

    // MARK: - 1口座ぶんだけの差分更新（ロックのON/OFFなど、影響が1つの口座に閉じる場合に使う軽量版）

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

    // MARK: - 1支払い方法ぶんだけの差分更新（クレジットカード・その他・受け取り方法のロックON/OFF用）

    static func touchMethodName(_ methodName: String) {
        let start = Date()
        let dates = datesForMethodName(methodName)
        touchDates(dates)
        logger.debug("touchMethodName(\(methodName)): \(dates.count) dates, \(Date().timeIntervalSince(start), format: .fixed(precision: 3))s")
    }

    // (day, bookId) の組ごとにグルーピングして処理する。範囲をまとめて1回だけfetchし、
    // メモリ上でグループ化してから処理するのはrebuildAllと同じ方式。
    private struct DayBookKey: Hashable {
        let day: Date
        let bookId: UUID
    }

    private static func touchDates(_ dates: [(date: Date, bookId: UUID)]) {
        let cal = Calendar.current
        let keys = Set(dates.map { DayBookKey(day: cal.startOfDay(for: $0.date), bookId: $0.bookId) })
        guard !keys.isEmpty else { return }
        let days = keys.map(\.day)
        guard let rangeStart = days.min(), let rangeLastDay = days.max(),
              let rangeEnd = cal.date(byAdding: .day, value: 1, to: rangeLastDay) else { return }

        let allBankAccounts = BankAccountDataSync.fetchAll()
        let allPaymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let bankAccountsByBook = Dictionary(grouping: allBankAccounts.filter { $0.bookId != nil }, by: { $0.bookId! })
        let paymentMethodsByBook = Dictionary(grouping: allPaymentMethods.filter { $0.bookId != nil }, by: { $0.bookId! })
        let creditCardNamesByBook = Dictionary(uniqueKeysWithValues: Set(keys.map(\.bookId)).map {
            ($0, creditCardMethodNames(paymentMethodsByBook[$0] ?? []))
        })

        let allRangeIncomes = IncomeDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@", rangeStart as NSDate, rangeEnd as NSDate))
        let allRangeExpenses = ExpenseDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@", rangeStart as NSDate, rangeEnd as NSDate))
        let rangeTransfers = TransferDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@", rangeStart as NSDate, rangeEnd as NSDate))

        let rangeIncomesByBook = Dictionary(grouping: allRangeIncomes.filter { $0.bookId != nil }, by: { $0.bookId! })
        let rangeExpensesByBook = Dictionary(grouping: allRangeExpenses.filter { $0.bookId != nil }, by: { $0.bookId! })
        let rangeIncomes = rangeIncomesByBook.flatMap { bookId, incomes in
            DowngradeLockService.visibleIncomes(incomes, bankAccounts: bankAccountsByBook[bookId] ?? [], paymentMethods: paymentMethodsByBook[bookId] ?? [])
        }
        let rangeExpenses = rangeExpensesByBook.flatMap { bookId, expenses in
            DowngradeLockService.visibleExpenses(expenses, bankAccounts: bankAccountsByBook[bookId] ?? [], paymentMethods: paymentMethodsByBook[bookId] ?? [])
        }

        let incomesByKey = Dictionary(grouping: rangeIncomes.filter { $0.bookId != nil }) {
            DayBookKey(day: cal.startOfDay(for: $0.date), bookId: $0.bookId!)
        }
        let expensesByKey = Dictionary(grouping: rangeExpenses.filter { $0.bookId != nil }) {
            DayBookKey(day: cal.startOfDay(for: $0.date), bookId: $0.bookId!)
        }
        let transfersByKey = Dictionary(grouping: rangeTransfers.filter { $0.bookId != nil }) {
            DayBookKey(day: cal.startOfDay(for: $0.date), bookId: $0.bookId!)
        }
        let cdSnapshotsByKey = Dictionary(
            uniqueKeysWithValues: fetchCDDailySnapshotsAnyBook(from: rangeStart, to: rangeEnd)
                .compactMap { cd -> (DayBookKey, CDDailySnapshot)? in
                    guard let date = cd.date, let bookId = cd.bookId else { return nil }
                    return (DayBookKey(day: cal.startOfDay(for: date), bookId: bookId), cd)
                }
        )

        for key in keys.sorted(by: { $0.day < $1.day }) {
            upsertDailySnapshot(
                day: key.day,
                bookId: key.bookId,
                incomes: incomesByKey[key] ?? [],
                expenses: expensesByKey[key] ?? [],
                transfers: transfersByKey[key] ?? [],
                creditCardNames: creditCardNamesByBook[key.bookId] ?? [],
                existing: cdSnapshotsByKey[key]
            )
        }

        let earliestByBook = Dictionary(grouping: keys, by: \.bookId).compactMapValues { $0.map(\.day).min() }
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

    // MARK: - 全期間再構築（バックアップ復元・ロック状態変化・資産反映タイミング変更後に呼ぶ）
    //
    // 1帳簿だけを対象にする版と、全帳簿を対象にする版を分ける。全帳簿版は「1帳簿を1トランザクション」
    // として帳簿ごとに独立して実行するため、ある帳簿の失敗が他帳簿の結果を巻き戻すことはない。
    // 呼び出し元は SnapshotRebuildResult で成功/失敗した帳簿IDを把握できる。
    //
    // 実装はCoreDataStack.shared.container.newBackgroundContext()で作った専用contextの上で
    // 読み取り〜delete〜insert〜saveまでを完結させる(NSManagedObjectはこのcontext外へ持ち出さない。
    // 元データはSnapshotSourceDataLoaderでその場でプレーンな値型に変換して扱う)。
    // 対象帳簿の削除は同じ未保存トランザクション内で行い、最後に1回だけsaveするため、
    // 「削除だけ確定して再構築は未完了」という中途半端な状態が保存されることはない
    // (save失敗時はcontext.rollback()して例外を投げ、呼び出し元に伝える)。

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

    /// 全帳簿を対象に再構築する。帳簿ごとに独立したトランザクションで実行するため、
    /// 途中の帳簿が失敗しても、それまでに成功した帳簿の結果は保持される。
    @discardableResult
    static func rebuildAll() -> SnapshotRebuildResult {
        let backgroundContext = CoreDataStack.shared.container.newBackgroundContext()
        var bookIds: [UUID] = []
        backgroundContext.performAndWait {
            do {
                bookIds = try SnapshotSourceDataLoader.loadAllBookIds(context: backgroundContext)
            } catch {
                // 帳簿一覧そのものが取得できない場合、対象帳簿が特定できないため
                // 個々のfailedBooksとしては記録できない。ログにだけ残し、空の結果を返す。
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
        try deleteExistingSnapshots(bookId: bookId, context: context)

        let source = try SnapshotSourceDataLoader.loadAll(bookId: bookId, context: context)
        let creditCardNames = creditCardMethodNames(source.paymentMethods)
        let visibleIncomes = DowngradeLockService.visibleIncomes(source.incomes, bankAccounts: source.bankAccounts, paymentMethods: source.paymentMethods)
        let visibleExpenses = DowngradeLockService.visibleExpenses(source.expenses, bankAccounts: source.bankAccounts, paymentMethods: source.paymentMethods)
        let transfers = source.transfers

        guard !(visibleIncomes.isEmpty && visibleExpenses.isEmpty && transfers.isEmpty) else {
            try context.save()
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let incomesByDay = Dictionary(grouping: visibleIncomes) { cal.startOfDay(for: $0.date) }
        let expensesByDay = Dictionary(grouping: visibleExpenses) { cal.startOfDay(for: $0.date) }
        let transfersByDay = Dictionary(grouping: transfers) { cal.startOfDay(for: $0.date) }

        let allDates = visibleIncomes.map(\.date) + visibleExpenses.map(\.date) + transfers.map(\.date)
        guard let earliestRaw = allDates.min() else {
            try context.save()
            return
        }
        // 【不具合修正】生の取引日時(時刻付き)をそのまま月次チェーンの起点にすると、
        // DailySnapshot.date(常に0時正規化済み)がその起点より前として扱われ、
        // 最初の月の集計からその日ぶんが漏れる(rebuildAll()の既知不具合)。
        // ここで必ず0時へ正規化してから月次集計の範囲計算に使う。
        let earliest = cal.startOfDay(for: earliestRaw)
        let latestDataDay = cal.startOfDay(for: allDates.max() ?? today)
        let end = max(today, latestDataDay)

        struct DayTotals {
            var income = 0
            var expense = 0
            var creditCard = 0
            var fees = 0
        }
        var dailyTotalsByDay: [Date: DayTotals] = [:]

        var day = earliest
        while day <= end {
            let dayIncomes = incomesByDay[day] ?? []
            let dayExpenses = expensesByDay[day] ?? []
            let dayTransfers = transfersByDay[day] ?? []

            var totals = DayTotals()
            totals.income = dayIncomes.reduce(0) { $0 + $1.amount }
            totals.expense = dayExpenses.reduce(0) { $0 + $1.amount }
            totals.creditCard = dayExpenses.filter { creditCardNames.contains($0.paymentMethod) }.reduce(0) { $0 + $1.amount }
            totals.fees = dayTransfers.reduce(0) { $0 + $1.feeAmount }
            dailyTotalsByDay[day] = totals

            let cdDaily = CDDailySnapshot(context: context)
            cdDaily.date = day
            cdDaily.bookId = bookId
            cdDaily.incomeTotal = Int64(totals.income)
            cdDaily.expenseTotal = Int64(totals.expense)
            cdDaily.creditCardExpenseTotal = Int64(totals.creditCard)
            cdDaily.transferFeeTotal = Int64(totals.fees)
            cdDaily.transactionCount = Int64(dayIncomes.count + dayExpenses.count)
            cdDaily.updatedAt = Date()

            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        var dailyTotalsByMonth: [Date: [DayTotals]] = [:]
        for (d, totals) in dailyTotalsByDay {
            guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: d)) else { continue }
            dailyTotalsByMonth[ms, default: []].append(totals)
        }

        guard var cursor = cal.date(from: cal.dateComponents([.year, .month], from: earliest)),
              let lastMonth = cal.date(from: cal.dateComponents([.year, .month], from: end)) else {
            try context.save()
            return
        }

        let timing = currentAssetReflectionTiming()
        var runningCarryover = 0
        var runningRawCarryover = 0

        while cursor <= lastMonth {
            let monthDaily = dailyTotalsByMonth[cursor] ?? []
            let income = monthDaily.reduce(0) { $0 + $1.income }
            let expense = monthDaily.reduce(0) { $0 + $1.expense }
            let creditCard = monthDaily.reduce(0) { $0 + $1.creditCard }
            let fees = monthDaily.reduce(0) { $0 + $1.fees }

            let comps = cal.dateComponents([.year, .month], from: cursor)
            let year = comps.year ?? 0
            let month = comps.month ?? 0

            let cdMonthly = CDMonthlySnapshot(context: context)
            cdMonthly.yearMonth = yearMonthKey(year: year, month: month)
            cdMonthly.bookId = bookId
            cdMonthly.year = Int64(year)
            cdMonthly.month = Int64(month)
            cdMonthly.incomeTotal = Int64(income)
            cdMonthly.expenseTotal = Int64(expense)
            cdMonthly.creditCardExpenseTotal = Int64(creditCard)
            cdMonthly.transferFeeTotal = Int64(fees)
            cdMonthly.carryoverBalance = Int64(runningCarryover)
            cdMonthly.rawCarryoverBalance = Int64(runningRawCarryover)
            cdMonthly.updatedAt = Date()

            let assetExpense = timing == .withdrawalDate ? expense - creditCard : expense
            runningCarryover += income - assetExpense - fees
            runningRawCarryover += income - expense

            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        try context.save()
    }

    private static func deleteExistingSnapshots(bookId: UUID, context: NSManagedObjectContext) throws {
        let dailyRequest = CDDailySnapshot.fetchRequest()
        dailyRequest.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        for existing in try context.fetch(dailyRequest) { context.delete(existing) }

        let monthlyRequest = CDMonthlySnapshot.fetchRequest()
        monthlyRequest.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        for existing in try context.fetch(monthlyRequest) { context.delete(existing) }
    }

    // MARK: - Private: 日次スナップショットの作成/更新

    @discardableResult
    private static func upsertDailySnapshot(
        day: Date, bookId: UUID, incomes: [IncomeData], expenses: [ExpenseData], transfers: [TransferData],
        creditCardNames: Set<String>, existing: CDDailySnapshot? = nil,
        skipExistingLookup: Bool = false
    ) -> CDDailySnapshot {
        let incomeTotal = incomes.reduce(0) { $0 + $1.amount }
        let expenseTotal = expenses.reduce(0) { $0 + $1.amount }
        let creditCardExpenseTotal = expenses.filter { creditCardNames.contains($0.paymentMethod) }.reduce(0) { $0 + $1.amount }
        let transferFeeTotal = transfers.reduce(0) { $0 + $1.feeAmount }
        let count = incomes.count + expenses.count

        let snapshot: CDDailySnapshot
        if let existing {
            snapshot = existing
        } else if skipExistingLookup {
            let created = CDDailySnapshot(context: context)
            created.date = day
            created.bookId = bookId
            snapshot = created
        } else {
            snapshot = fetchCDDailySnapshot(day, bookId: bookId) ?? {
                let created = CDDailySnapshot(context: context)
                created.date = day
                created.bookId = bookId
                return created
            }()
        }
        snapshot.incomeTotal = Int64(incomeTotal)
        snapshot.expenseTotal = Int64(expenseTotal)
        snapshot.creditCardExpenseTotal = Int64(creditCardExpenseTotal)
        snapshot.transferFeeTotal = Int64(transferFeeTotal)
        snapshot.transactionCount = Int64(count)
        snapshot.updatedAt = Date()
        return snapshot
    }

    // MARK: - Private: 月次チェーンの差分カスケード（touch用。編集月〜現在存在する最新月まで連鎖更新）

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
        let previous = previousMonthEndBalances(before: cascadeStart, bookId: bookId, timing: timing)
        var runningCarryover = previous.carryover
        var runningRawCarryover = previous.rawCarryover

        guard let cascadeEndExclusive = cal.date(byAdding: .month, value: 1, to: endMonthStart) else { return }
        let dailyInRange = fetchCDDailySnapshots(from: cascadeStart, to: cascadeEndExclusive, bookId: bookId)
        var dailyByMonth: [Date: [CDDailySnapshot]] = [:]
        for snap in dailyInRange {
            guard let date = snap.date, let ms = cal.date(from: cal.dateComponents([.year, .month], from: date)) else { continue }
            dailyByMonth[ms, default: []].append(snap)
        }
        let existingMonthlyByKey = Dictionary(
            uniqueKeysWithValues: fetchCDMonthlySnapshots(from: cascadeStart, to: cascadeEndExclusive, bookId: bookId)
                .compactMap { snap -> (String, CDMonthlySnapshot)? in
                    guard let key = snap.yearMonth else { return nil }
                    return (key, snap)
                }
        )

        var cursor = cascadeStart
        while cursor <= endMonthStart {
            let days = dailyByMonth[cursor] ?? []
            let totals = (
                income: days.reduce(0) { $0 + Int($1.incomeTotal) },
                expense: days.reduce(0) { $0 + Int($1.expenseTotal) },
                creditCard: days.reduce(0) { $0 + Int($1.creditCardExpenseTotal) },
                fees: days.reduce(0) { $0 + Int($1.transferFeeTotal) }
            )
            let key = yearMonthComponentsKey(cursor)
            let snapshot = upsertMonthlySnapshot(
                monthStart: cursor, bookId: bookId, carryoverBalance: runningCarryover, rawCarryoverBalance: runningRawCarryover,
                precomputedTotals: totals, existing: existingMonthlyByKey[key]
            )
            runningCarryover += monthlyAssetNetTotal(snapshot, assetReflectionTiming: timing)
            runningRawCarryover += monthlyNetTotal(snapshot)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
    }

    @discardableResult
    private static func upsertMonthlySnapshot(
        monthStart: Date, bookId: UUID, carryoverBalance: Int, rawCarryoverBalance: Int,
        precomputedTotals: (income: Int, expense: Int, creditCard: Int, fees: Int)? = nil,
        existing: CDMonthlySnapshot? = nil, skipExistingLookup: Bool = false
    ) -> CDMonthlySnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthStart)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let key = yearMonthKey(year: year, month: month)
        let (income, expense, creditCard, fees) = precomputedTotals ?? sumDailySnapshots(inMonth: monthStart, bookId: bookId)

        let snapshot: CDMonthlySnapshot
        if let existing {
            snapshot = existing
        } else if skipExistingLookup {
            let created = CDMonthlySnapshot(context: context)
            created.yearMonth = key
            created.bookId = bookId
            created.year = Int64(year)
            created.month = Int64(month)
            snapshot = created
        } else {
            snapshot = fetchCDMonthlySnapshot(key, bookId: bookId) ?? {
                let created = CDMonthlySnapshot(context: context)
                created.yearMonth = key
                created.bookId = bookId
                created.year = Int64(year)
                created.month = Int64(month)
                return created
            }()
        }
        snapshot.incomeTotal = Int64(income)
        snapshot.expenseTotal = Int64(expense)
        snapshot.creditCardExpenseTotal = Int64(creditCard)
        snapshot.transferFeeTotal = Int64(fees)
        snapshot.carryoverBalance = Int64(carryoverBalance)
        snapshot.rawCarryoverBalance = Int64(rawCarryoverBalance)
        snapshot.updatedAt = Date()
        return snapshot
    }

    private static func previousMonthEndBalances(
        before monthStart: Date, bookId: UUID, timing: CreditCardAssetReflectionTiming
    ) -> (carryover: Int, rawCarryover: Int) {
        let cal = Calendar.current
        guard let prevMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return (0, 0) }
        let key = yearMonthComponentsKey(prevMonthStart)
        guard let prev = fetchCDMonthlySnapshot(key, bookId: bookId) else { return (0, 0) }
        return (monthlyEndOfMonthBalance(prev, assetReflectionTiming: timing), monthlyRawEndOfMonthBalance(prev))
    }

    private static func latestMonthlySnapshotMonthStart(bookId: UUID) -> Date? {
        let request = CDMonthlySnapshot.fetchRequest()
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

    // MARK: - Private: その月内のDailySnapshotを合算する（carryoverBalanceの積み上げ対象は月単位のみ）

    private static func sumDailySnapshots(inMonth monthStart: Date, bookId: UUID) -> (income: Int, expense: Int, creditCard: Int, fees: Int) {
        let cal = Calendar.current
        guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return (0, 0, 0, 0) }
        let days = fetchCDDailySnapshots(from: monthStart, to: monthEnd, bookId: bookId)
        let income = days.reduce(0) { $0 + Int($1.incomeTotal) }
        let expense = days.reduce(0) { $0 + Int($1.expenseTotal) }
        let creditCard = days.reduce(0) { $0 + Int($1.creditCardExpenseTotal) }
        let fees = days.reduce(0) { $0 + Int($1.transferFeeTotal) }
        return (income, expense, creditCard, fees)
    }

    // MARK: - Private: フェッチ系ヘルパー（CD型を直接扱う）

    private static func fetchCDDailySnapshot(_ day: Date, bookId: UUID) -> CDDailySnapshot? {
        let request = CDDailySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@ AND bookId == %@", day as NSDate, bookId as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private static func fetchCDDailySnapshots(from start: Date, to end: Date, bookId: UUID) -> [CDDailySnapshot] {
        let request = CDDailySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", start as NSDate, end as NSDate, bookId as CVarArg)
        return (try? context.fetch(request)) ?? []
    }

    private static func fetchCDDailySnapshotsAnyBook(from start: Date, to end: Date) -> [CDDailySnapshot] {
        let request = CDDailySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        return (try? context.fetch(request)) ?? []
    }

    private static func fetchCDMonthlySnapshot(_ key: String, bookId: UUID) -> CDMonthlySnapshot? {
        let request = CDMonthlySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "yearMonth == %@ AND bookId == %@", key, bookId as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    // MonthlySnapshotはDateではなくyear/monthで持っているため範囲predicateが組めない。
    // 全件fetchしてメモリ上で絞り込む。
    private static func fetchCDMonthlySnapshots(from start: Date, to end: Date, bookId: UUID) -> [CDMonthlySnapshot] {
        let cal = Calendar.current
        func monthIndex(_ d: Date) -> Int {
            let c = cal.dateComponents([.year, .month], from: d)
            return (c.year ?? 0) * 12 + (c.month ?? 0)
        }
        let startIdx = monthIndex(start)
        let endIdx = monthIndex(end)
        let request = CDMonthlySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        let all = (try? context.fetch(request)) ?? []
        return all.filter { snap in
            let idx = Int(snap.year) * 12 + Int(snap.month)
            return idx >= startIdx && idx < endIdx
        }
    }

    private static func fetchIncomes(on day: Date, bookId: UUID) -> [IncomeData] {
        let cal = Calendar.current
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        return IncomeDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", day as NSDate, dayEnd as NSDate, bookId as CVarArg))
    }

    private static func fetchExpenses(on day: Date, bookId: UUID) -> [ExpenseData] {
        let cal = Calendar.current
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        return ExpenseDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", day as NSDate, dayEnd as NSDate, bookId as CVarArg))
    }

    private static func fetchTransfers(on day: Date, bookId: UUID) -> [TransferData] {
        let cal = Calendar.current
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        return TransferDataSync.fetch(matching: NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", day as NSDate, dayEnd as NSDate, bookId as CVarArg))
    }

    // MARK: - Private: MonthlySnapshot(struct)の計算プロパティ相当（CD型に対して計算する版）

    private static func monthlyNetTotal(_ cd: CDMonthlySnapshot) -> Int {
        Int(cd.incomeTotal) - Int(cd.expenseTotal)
    }

    private static func monthlyAssetNetTotal(_ cd: CDMonthlySnapshot, assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        let assetExpense = assetReflectionTiming == .withdrawalDate
            ? Int(cd.expenseTotal) - Int(cd.creditCardExpenseTotal)
            : Int(cd.expenseTotal)
        return Int(cd.incomeTotal) - assetExpense - Int(cd.transferFeeTotal)
    }

    private static func monthlyEndOfMonthBalance(_ cd: CDMonthlySnapshot, assetReflectionTiming: CreditCardAssetReflectionTiming) -> Int {
        Int(cd.carryoverBalance) + monthlyAssetNetTotal(cd, assetReflectionTiming: assetReflectionTiming)
    }

    private static func monthlyRawEndOfMonthBalance(_ cd: CDMonthlySnapshot) -> Int {
        Int(cd.rawCarryoverBalance) + monthlyNetTotal(cd)
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
