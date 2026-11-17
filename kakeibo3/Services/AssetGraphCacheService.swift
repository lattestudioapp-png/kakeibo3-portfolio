import CoreData
import Foundation

// MARK: - 資産推移グラフキャッシュの読み書き
//
// 分析Viewを開くたびに元データから再計算するのを避けるため、「更新」ボタンを押した時だけ
// ExpenseData/IncomeData/TransferData等の元データから計算し、結果をAssetGraphCacheDataに
// 保存する。取引の保存/編集/削除や設定変更では自動的に再計算しない
// （SnapshotManager/AnalysisSnapshotManagerとは意図的に別方針）。
//
// 計算方式：日付ごとに全取引をfilterする（O(日数 × 取引件数)）と長期間で重くなるため、
// 各取引を「日付 + 増減額」の AssetEvent に変換して1回だけ日付順にソートし（O(E log E)）、
// 日付を進めながらイベントを順番に適用する1回の走査（O(日数 + イベント数)）で日別残高を作る。
//
// 「計算中...」のまま戻らなくなる事故を防ぐため：
// - 日付ループには安全上限（最大36500日=約100年）を設け、超えたら例外を投げて確実に失敗として返す
// - 全体に30秒のタイムアウトを設け、超えたら計算を中断してタイムアウトとして返す
// - 各工程の開始/終了をTimingDebugLogに書き、途中で止まった場合にどこで止まったか分かるようにする
// - 呼び出し側（AssetTrendCacheCardView）は成功・失敗・タイムアウトのいずれでも
//   必ず isCalculating 相当の状態を戻す

enum AssetGraphError: LocalizedError {
    case tooManyDays
    case timeout

    var errorDescription: String? {
        switch self {
        case .tooManyDays:
            return "対象期間が長すぎるため計算できませんでした。"
        case .timeout:
            return "計算に時間がかかっています。データ量を減らすか、もう一度お試しください。"
        }
    }
}

// MARK: - 資産推移イベント（1件の取引・引き落としがもたらす、ある1日の総資産増減額）

private struct AssetEvent {
    let date: Date
    let amountDelta: Int
}

enum AssetGraphCacheService {

    /// 日付ループの安全上限（約100年ぶん）。これを超える場合は不正な日付範囲とみなし失敗させる。
    private static let maxDays = 36_500
    /// 全体のタイムアウト秒数。
    private static let timeoutSeconds: UInt64 = 30

    // MARK: - 読み込み（メインスレッドから同期で呼んでよい。単純な主キー1件検索）

    static func fetchTotalAssetsCache(bookId: UUID) -> AssetGraphCacheData? {
        AssetGraphCacheDataSync.fetch(bookId: bookId)
    }

    // MARK: - 再計算（「更新」ボタン押下時だけ呼ぶ。メインスレッドを塞がないよう別Contextで実行）
    //
    // 30秒でタイムアウトする。タイムアウト時は計算タスクをcancelし、AssetGraphError.timeoutを投げる。
    // 呼び出し側は必ずdo/catchでエラーを受け取り、成功・失敗・タイムアウトいずれでも
    // 「計算中」状態を解除すること。
    //
    // 【重要】以前はTask.detached + performAndWait（同期・ブロッキング）という構成だった。
    // Task.detachedはSwift Concurrencyのグローバルcooperativeスレッドプールへ投げられるが、
    // その中でperformAndWaitのようなブロッキング呼び出しを行うのは、Appleが明示的に
    // 避けるよう案内しているアンチパターン（cooperativeプールのスレッドを長時間塞ぐと、
    // プール枯渇・スケジューリング遅延を招く）。ユニットテスト390件を連続実行するような
    // 高負荷時に、testAssetGraphCacheRebuildsSuccessfullyがまれに捕捉不能な
    // NSInvalidArgumentException（Core Data内部破壊）でクラッシュする不具合の一因になっていた。
    // NSManagedObjectContextの非同期版perform(_:)（iOS 15+）は、contextの専用キューへ
    // 正しく非同期dispatchするだけでcooperativeプールのスレッドをブロックしないため、
    // Task.detachedを完全に廃止してこちらへ置き換える。
    static func rebuildTotalAssetsCache(bookId: UUID, maxPoints: Int) async throws {
        let context = CoreDataStack.shared.container.newBackgroundContext()
        let totalStart = CFAbsoluteTimeGetCurrent()

        do {
            // context.perform(_:)をそのままawaitするだけだと、万が一fetch/save自体が
            // 固まった場合（cancelは協調的なため同期処理の途中では効かないことがある）に
            // このawait自体が永遠に返らず、UI側の「計算中」も戻せなくなる。
            // そこで30秒のタイムアウトをタスクグループで競わせ、どちらかが先に終わった
            // 時点で必ずこの関数が返る/throwするようにする（タイムアウト側が勝った場合、
            // TaskGroupが未完了の子タスクを自動的にcancelしてから抜けるため、
            // 明示的なcancel呼び出しは不要）。
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await context.perform {
                        do {
                            try runRebuild(bookId: bookId, maxPoints: maxPoints, context: context, totalStart: totalStart)
                        } catch {
                            context.rollback()
                            throw error
                        }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    throw AssetGraphError.timeout
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            if case AssetGraphError.timeout = error {
                TimingDebugLog.write("AssetGraph rebuild timed out (\(timeoutSeconds)s)")
            } else {
                TimingDebugLog.write("AssetGraph rebuild failed: \(error)")
            }
            throw error
        }
    }

    // MARK: - 実処理（別スレッド上で同期実行。定期的にキャンセルをチェックする）

    // MARK: - イベント構築（fetch + 資産増減イベントへの変換 + 日付ソートまで）
    //
    // runRebuild本体（日別残高の展開・間引き）とhasEnoughDataForTotalAssetsChart（軽量な
    // データ有無チェック）の両方から使う共通処理。ここを2箇所に分けて重複させると、
    // クレジットカード引落判定・振替の資産内/外判定などの分岐がズレるリスクがあるため、
    // 「イベントを作るところまで」は必ずこの1箇所だけに実装する。
    // 呼び出し側が渡したcontext上でそのまま同期fetchする(このメソッド自体はperformで
    // 包まない)。hasEnoughDataForTotalAssetsChartはviewContextを主スレッドから直接渡し、
    // runRebuildはbackgroundContextをperformAndWaitの内側から渡す。
    private static func buildEvents(bookId: UUID, context: NSManagedObjectContext) throws -> (events: [AssetEvent], initialOffset: Int) {
        let cal = Calendar.current

        // [DEBUG] この総資産推移グラフはAnalysisMonthlySnapshot等のスナップショットには一切依存せず、
        // ExpenseData/IncomeData/TransferDataを毎回直接fetchする（「更新」ボタン押下時のみ）。
        // そのため「資産スナップショットの更新有無」はこのグラフには影響しない。
        // 影響するのは (1) 対象取引がisAssetな支払い/受け取り方法・口座を使っているか、
        // (2) 「更新」ボタンを取引保存後に押したか、の2点のみ。
        TimingDebugLog.write("[AssetDebug] buildEvents: fetching ExpenseData/IncomeData/TransferData directly (no snapshot dependency)")

        let bankAccounts = try SnapshotSourceDataLoader.fetchBankAccounts(bookId: bookId, context: context)
        let paymentMethods = try SnapshotSourceDataLoader.fetchPaymentMethods(bookId: bookId, context: context)
        let rawExpenses = try SnapshotSourceDataLoader.fetchExpenses(bookId: bookId, context: context)
        let rawIncomes = try SnapshotSourceDataLoader.fetchIncomes(bookId: bookId, context: context)
        let transfers = try SnapshotSourceDataLoader.fetchTransfers(bookId: bookId, context: context)

        // 「資産に含める」(isAsset) だけで集計対象を決める
        // （総資産・資産推移・分析>資産の内訳表示と同じ基準。DowngradeLockService参照）。
        let assetExpenses = DowngradeLockService.assetTotalExpenses(
            rawExpenses, bankAccounts: bankAccounts, paymentMethods: paymentMethods
        )
        let assetIncomes = DowngradeLockService.assetTotalIncomes(
            rawIncomes, bankAccounts: bankAccounts, paymentMethods: paymentMethods
        )

        let creditCardNames = Set(
            paymentMethods
                .filter { $0.type == PaymentMethodType.creditCard.rawValue }
                .map(\.methodName)
        )
        let timing = currentAssetReflectionTiming()

        // O(1)引き用の索引
        let methodByName = Dictionary(paymentMethods.map { ($0.methodName, $0) }, uniquingKeysWith: { first, _ in first })
        let bankById = Dictionary(uniqueKeysWithValues: bankAccounts.map { ($0.id, $0) })
        let methodById = Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0) })

        // 資産に含めるONの初期残高を合計する（現金・銀行口座・電子マネー・デビットカード・証券口座・暗号資産・その他）
        let methodAssets = paymentMethods.filter {
            $0.isAsset && $0.isActive && !$0.isLocked && $0.type != PaymentMethodType.creditCard.rawValue
        }
        let pmInitialOffset = methodAssets
            .filter { $0.assetInitialBalanceIncomeId == nil && $0.assetInitialBalanceExpenseId == nil }
            .reduce(0) { $0 + Int($1.assetInitialBalance ?? 0) }
        let assetBanks = bankAccounts.filter { $0.isAsset && $0.isActive && !$0.isLocked }
        let bankInitialOffset = assetBanks
            .filter { $0.initialBalanceIncomeId == nil }
            .reduce(0) { $0 + Int($1.initialBalance ?? 0) }
        let initialOffset = pmInitialOffset + bankInitialOffset

        // [DEBUG] 「現金」が資産に含める対象として取得できているか
        if let cashMethod = paymentMethods.first(where: { $0.methodName == "現金" }) {
            TimingDebugLog.write(
                "[AssetDebug] 現金 found: isAsset=\(cashMethod.isAsset) isActive=\(cashMethod.isActive) "
                + "isLocked=\(cashMethod.isLocked) type=\(cashMethod.type)"
            )
        } else {
            TimingDebugLog.write("[AssetDebug] 現金 not found in paymentMethods for this book")
        }

        var events: [AssetEvent] = []
        events.reserveCapacity(assetIncomes.count + assetExpenses.count + transfers.count)

        for income in assetIncomes {
            events.append(AssetEvent(date: cal.startOfDay(for: income.date), amountDelta: income.amount))
        }

        let creditCardExpenses = assetExpenses.filter { creditCardNames.contains($0.paymentMethod) }
        let normalExpenses = assetExpenses.filter { !creditCardNames.contains($0.paymentMethod) }

        for expense in normalExpenses {
            events.append(AssetEvent(date: cal.startOfDay(for: expense.date), amountDelta: -expense.amount))
        }

        switch timing {
        case .usageDate:
            // 利用日に反映：クレジットカードも他の支払い方法と同じく利用日に減らす
            for expense in creditCardExpenses {
                events.append(AssetEvent(date: cal.startOfDay(for: expense.date), amountDelta: -expense.amount))
            }
        case .withdrawalDate:
            // 引き落とし日に反映：利用日には減らさず、締め日/引き落とし日/引き落とし口座の設定から
            // 計算した引き落とし日に、引き落とし口座（資産に含めるONの場合のみ）から減らす。
            // 設定が無い・引き落とし口座が資産に含まれない場合は、この支出は資産推移に反映しない
            // （現状の口座別残高に実際の引き落とし取引が別途記録されている前提のため）。
            var withdrawalTotals: [Date: Int] = [:]
            for expense in creditCardExpenses {
                guard let method = methodByName[expense.paymentMethod],
                      let closingDay = method.closingDay,
                      let withdrawalDay = method.withdrawalDay,
                      let bankId = method.withdrawalBankAccountId,
                      let bank = bankById[bankId],
                      bank.isAsset, bank.isActive, !bank.isLocked
                else { continue }

                let withdrawalDate = cal.startOfDay(for: creditCardWithdrawalDate(
                    forExpenseDate: expense.date,
                    closingDay: closingDay,
                    withdrawalDay: withdrawalDay,
                    adjustForBusinessDay: method.adjustPaymentDateToNextBusinessDay,
                    cal: cal
                ))
                withdrawalTotals[withdrawalDate, default: 0] += expense.amount
            }
            for (date, total) in withdrawalTotals {
                events.append(AssetEvent(date: date, amountDelta: -total))
            }
        }

        // 振替：総資産内（資産に含めるON同士）の移動なら総資産は変えない。
        // ONからOFF・OFFからONへの移動がある場合は増減させる。手数料は「資産に含めるON」の
        // 移動元から出ていく想定なので、移動元が資産に含まれる場合のみ減らす。
        for transfer in transfers {
            let fromIsAsset = isAssetTransferSide(
                type: transfer.fromType, id: transfer.fromId, bankById: bankById, methodById: methodById
            )
            let toIsAsset = isAssetTransferSide(
                type: transfer.toType, id: transfer.toId, bankById: bankById, methodById: methodById
            )
            var delta = 0
            if toIsAsset { delta += transfer.amount }
            if fromIsAsset { delta -= transfer.amount }
            if fromIsAsset && transfer.feeAmount > 0 { delta -= transfer.feeAmount }
            guard delta != 0 else { continue }
            events.append(AssetEvent(date: cal.startOfDay(for: transfer.date), amountDelta: delta))
        }

        events.sort { $0.date < $1.date }

        // [DEBUG] 資産推移グラフ判定前の全資産ポイント（イベント）と、日付重複を除いた後の件数
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        TimingDebugLog.write("[AssetDebug] raw events count=\(events.count)")
        for e in events {
            TimingDebugLog.write("[AssetDebug]   event date=\(df.string(from: e.date)) amountDelta=\(e.amountDelta)")
        }
        let distinctDates = Set(events.map { df.string(from: $0.date) })
        TimingDebugLog.write("[AssetDebug] distinct event dates count=\(distinctDates.count) dates=\(distinctDates.sorted())")

        return (events, initialOffset)
    }

    // MARK: - グラフに足るデータがあるかの軽量チェック（日別残高の展開は行わない）
    //
    // runRebuildの日別展開ループ（最大約100年ぶん回る可能性がある）を実行せずに、
    // 「資産推移グラフとして2点以上になるか」だけを判定する。runRebuildの日別展開は
    // firstEventDateからtodayまで1日ずつ残高を forward-fill するため、todayより前の
    // イベントが1件でもあれば必ず2点以上になる（そのイベント当日 + today の最低2点）。
    // そのため判定は「イベントが存在し、かつ最も古いイベントの日付が今日より前か」だけでよい。
    static func hasEnoughDataForTotalAssetsChart(bookId: UUID) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        // 呼び出し元のスレッドによらず正しく動くよう、viewContextへのアクセスは
        // performAndWaitで包む(AssetGraphCacheDataSync.fetch/fetchAllと同じ理由。
        // async関数からの復帰後にメインスレッドへ戻っている保証が無いコード経路が
        // 実際に存在したため、「主スレッドから呼ばれる想定」に頼らない)。
        // ここは「グラフを表示できるだけのデータがあるか」という軽量なUI用チェックのため、
        // fetch失敗時はエラーを伝播させず「データ不足」として安全側に倒す
        // (再構築本体のrunRebuildとは異なり、ここでの失敗はデータ消失につながらない)。
        let viewContext = CoreDataStack.shared.container.viewContext
        var buildResult: (events: [AssetEvent], initialOffset: Int)?
        viewContext.performAndWait {
            buildResult = try? buildEvents(bookId: bookId, context: viewContext)
        }
        guard let firstEventDate = buildResult?.events.first?.date else {
            TimingDebugLog.write("[AssetDebug] hasEnoughData=false reason=no events at all")
            return false
        }
        let result = firstEventDate < today
        TimingDebugLog.write(
            "[AssetDebug] hasEnoughData=\(result) firstEventDate=\(df.string(from: firstEventDate)) "
            + "today=\(df.string(from: today)) reason=" + (result ? "firstEventDate < today" : "firstEventDate >= today (今日以降の日付しか無い＝forward-fillで2点にならない)")
        )
        return result
    }

    // context.perform(_:)の内側から呼ばれる（rebuildTotalAssetsCache参照）。fetch〜計算〜保存
    // までをそのcontextの専用キュー上の1ブロックで完結させる。NSManagedObjectはこのcontext外へ
    // 持ち出さず、結果は最後に1回だけsaveする（失敗時は呼び出し元でrollbackして例外を投げる）。
    private static func runRebuild(bookId: UUID, maxPoints: Int, context: NSManagedObjectContext, totalStart: CFAbsoluteTime) throws {
        TimingDebugLog.write("AssetGraph rebuild started")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        try Task.checkCancellation()

        TimingDebugLog.write("fetch started")
        let fetchStart = CFAbsoluteTimeGetCurrent()
        let (events, initialOffset) = try buildEvents(bookId: bookId, context: context)
        TimingDebugLog.mark("fetch finished", since: fetchStart)
        TimingDebugLog.write("events count: \(events.count)")

        try Task.checkCancellation()

        guard let firstEventDate = events.first?.date else {
            // イベントが1件も無い場合はキャッシュを消して終了（「まだグラフが作成されていません」に戻す）
            try deleteCache(bookId: bookId, context: context)
            try context.save()
            TimingDebugLog.mark("AssetGraph rebuild finished (no data)", since: totalStart)
            return
        }

        // firstDate/lastDate が逆転・異常な場合は安全に失敗させる（無限ループ防止の入口）
        guard firstEventDate <= today else {
            TimingDebugLog.write("AssetGraph rebuild aborted: firstEventDate(\(firstEventDate)) is after today(\(today))")
            throw AssetGraphError.tooManyDays
        }
        let totalDaySpan = cal.dateComponents([.day], from: firstEventDate, to: today).day ?? 0
        guard totalDaySpan >= 0, totalDaySpan <= maxDays else {
            TimingDebugLog.write("AssetGraph rebuild aborted: day span \(totalDaySpan) exceeds safety limit \(maxDays)")
            throw AssetGraphError.tooManyDays
        }

        // 4. startDateからendDateまで日付を進めながら、イベントを順番に適用する（1回の走査）
        TimingDebugLog.write("daily points build started")
        let dailyStart = CFAbsoluteTimeGetCurrent()

        var days: [Date] = []
        days.reserveCapacity(totalDaySpan + 1)
        var cur = firstEventDate
        var dayLoopCount = 0
        while cur <= today {
            dayLoopCount += 1
            if dayLoopCount > maxDays {
                TimingDebugLog.write("AssetGraph rebuild aborted: day loop exceeded safety limit \(maxDays)")
                throw AssetGraphError.tooManyDays
            }
            days.append(cur)
            guard let next = cal.date(byAdding: .day, value: 1, to: cur), next > cur else {
                // next が計算できない、または前進していない（同じ日付/過去に戻る）場合は
                // 無限ループになるためここで打ち切る
                break
            }
            cur = next
            if dayLoopCount % 3650 == 0 {
                try Task.checkCancellation()
            }
        }
        TimingDebugLog.write("days count: \(days.count)")

        var dailyPoints: [AssetChartPoint] = []
        dailyPoints.reserveCapacity(days.count)
        var eventIndex = 0
        var currentBalance = initialOffset
        for day in days {
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
            while eventIndex < events.count && events[eventIndex].date < dayEnd {
                currentBalance += events[eventIndex].amountDelta
                eventIndex += 1
            }
            dailyPoints.append(AssetChartPoint(id: day, date: day, assetAmount: currentBalance))
        }
        TimingDebugLog.mark("daily points build finished", since: dailyStart)

        // [DEBUG] 各ポイントの日付と総資産額（forward-fill後、間引き前）
        let debugDf = DateFormatter()
        debugDf.dateFormat = "yyyy-MM-dd"
        TimingDebugLog.write("[AssetDebug] dailyPoints (forward-fill後, 間引き前) count=\(dailyPoints.count)")
        for p in dailyPoints {
            TimingDebugLog.write("[AssetDebug]   dailyPoint date=\(debugDf.string(from: p.date)) assetAmount=\(p.assetAmount)")
        }

        try Task.checkCancellation()

        // 5. AssetGraphPointReducerで表示点数を削減する
        TimingDebugLog.write("reduce started")
        let reduceStart = CFAbsoluteTimeGetCurrent()
        let reduction = AssetGraphPointReducer.reduce(dailyPoints: dailyPoints, maxPoints: maxPoints)
        let cachePoints = reduction.points.map { AssetGraphCachePoint(date: $0.date, value: $0.assetAmount) }
        TimingDebugLog.mark("reduce finished", since: reduceStart)

        // [DEBUG] グラフに最終的に渡している配列（キャッシュに保存される配列＝AssetTrendCacheCardViewがそのまま表示する）
        TimingDebugLog.write("[AssetDebug] cachePoints (最終的にグラフへ渡す配列) count=\(cachePoints.count)")
        for p in cachePoints {
            TimingDebugLog.write("[AssetDebug]   cachePoint date=\(debugDf.string(from: p.date)) value=\(p.value)")
        }

        // 6. AssetGraphCacheDataに保存する(このcontext上で完結させ、最後に1回だけsaveする)
        TimingDebugLog.write("save cache started")
        let saveStart = CFAbsoluteTimeGetCurrent()
        try upsertCache(
            bookId: bookId, maxPoints: maxPoints, granularityUsed: reduction.granularity.storageValue,
            firstDate: firstEventDate, lastDate: today, points: cachePoints, context: context
        )
        try context.save()
        TimingDebugLog.mark("save cache finished", since: saveStart)

        TimingDebugLog.mark("AssetGraph rebuild finished", since: totalStart)
    }

    // MARK: - Private: CDAssetGraphCacheDataの直接操作(渡されたcontext上でのみ行う。save()は呼び出し元が行う)

    private static func deleteCache(bookId: UUID, context: NSManagedObjectContext) throws {
        let request = CDAssetGraphCacheData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", AssetGraphCacheData.cacheId(for: bookId))
        for existing in try context.fetch(request) {
            context.delete(existing)
        }
    }

    private static func upsertCache(
        bookId: UUID, maxPoints: Int, granularityUsed: String,
        firstDate: Date, lastDate: Date, points: [AssetGraphCachePoint],
        context: NSManagedObjectContext
    ) throws {
        let id = AssetGraphCacheData.cacheId(for: bookId)
        let request = CDAssetGraphCacheData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        let cd = try context.fetch(request).first ?? CDAssetGraphCacheData(context: context)
        cd.id = id
        cd.bookId = bookId
        cd.updatedAt = Date()
        cd.maxPointsUsed = Int64(maxPoints)
        cd.granularityUsed = granularityUsed
        cd.firstDate = firstDate
        cd.lastDate = lastDate
        cd.points = try? JSONEncoder().encode(points)
    }

    // MARK: - クレジットカード引き落とし日の計算
    //
    // 支出日と締め日/引き落とし日設定から、その支出が引き落とされる日付を逆算する
    // （CreditCardDueCard.billingPeriod と整合する関係式の逆算）。

    private static func creditCardWithdrawalDate(
        forExpenseDate expenseDate: Date,
        closingDay: Int,
        withdrawalDay: Int,
        adjustForBusinessDay: Bool,
        cal: Calendar
    ) -> Date {
        let day = cal.component(.day, from: expenseDate)
        let expenseMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: expenseDate)) ?? expenseDate
        let daysInExpenseMonth = cal.range(of: .day, in: .month, for: expenseMonthStart)?.count ?? 28
        let effectiveClosingDay = min(closingDay, daysInExpenseMonth)

        // 支出日が締め日以前ならその月で締める。締め日を過ぎていれば翌月で締める。
        let billingEndMonthStart = day <= effectiveClosingDay
            ? expenseMonthStart
            : (cal.date(byAdding: .month, value: 1, to: expenseMonthStart) ?? expenseMonthStart)

        let withdrawalOffset = (closingDay < withdrawalDay) ? 0 : 1
        let withdrawalMonthStart = cal.date(byAdding: .month, value: withdrawalOffset, to: billingEndMonthStart) ?? billingEndMonthStart
        let daysInWithdrawalMonth = cal.range(of: .day, in: .month, for: withdrawalMonthStart)?.count ?? 28
        var comps = cal.dateComponents([.year, .month], from: withdrawalMonthStart)
        comps.day = min(withdrawalDay, daysInWithdrawalMonth)
        let rawDate = cal.date(from: comps) ?? withdrawalMonthStart

        guard adjustForBusinessDay, HolidayCalendarService.isNonBusinessDay(rawDate) else { return rawDate }
        return HolidayCalendarService.nextBusinessDay(from: rawDate)
    }

    // MARK: - 振替の移動元/移動先が「資産に含める」対象かどうか

    private static func isAssetTransferSide(
        type: String,
        id: UUID?,
        bankById: [UUID: BankAccountData],
        methodById: [UUID: PaymentMethodSettingData]
    ) -> Bool {
        guard let id else { return false }
        if type == TransferAccountType.bank.rawValue {
            guard let bank = bankById[id] else { return false }
            return bank.isAsset && bank.isActive && !bank.isLocked
        }
        guard let method = methodById[id] else { return false }
        return method.isAsset && method.isActive && !method.isLocked
            && method.type != PaymentMethodType.creditCard.rawValue
    }

    private static func currentAssetReflectionTiming() -> CreditCardAssetReflectionTiming {
        let raw = UserDefaults.standard.string(forKey: CreditCardAssetReflectionTiming.storageKey)
        return raw.flatMap { CreditCardAssetReflectionTiming(rawValue: $0) } ?? CreditCardAssetReflectionTiming.defaultValue
    }
}
