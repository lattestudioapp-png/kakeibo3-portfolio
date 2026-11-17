import Foundation
import Combine

struct CalendarTransactionCalculator {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = currentWeekStartWeekday()
        return calendar
    }

    // MARK: - 週の開始曜日設定

    /// Calendar.weekday準拠（1=日, ..., 7=土）。
    /// UserDefaults.integer(forKey:)は未設定時0を返す（1...7の範囲外）ため、
    /// その場合はデフォルト値にフォールバックする。
    private func currentWeekStartWeekday() -> Int {
        let stored = UserDefaults.standard.integer(forKey: CalendarWeekStartSettings.storageKey)
        return CalendarWeekStartSettings.validRange.contains(stored) ? stored : CalendarWeekStartSettings.defaultValue
    }

    /// グリッドの日付範囲（前後の余白セルを含む）を、週の開始曜日に揃えて計算する共通ヘルパー。
    /// periodStart/periodEnd（会計期間の実際の開始日・終了日、endは排他的）を渡し、
    /// その前後を週単位で埋めた [gridStart, gridEnd) を返す。
    /// calendar.component(.weekday:)はfirstWeekday設定の影響を受けない絶対値（日=1...土=7）
    /// なので、開始曜日とのズレを自前で計算する。
    private func weekAlignedGridRange(periodStart: Date, periodEnd: Date) -> (start: Date, end: Date)? {
        let weekStart = currentWeekStartWeekday()

        let startWeekday = calendar.component(.weekday, from: periodStart)
        let leadingOffset = (startWeekday - weekStart + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingOffset, to: periodStart) else { return nil }

        let endWeekday = calendar.component(.weekday, from: periodEnd)
        let trailingOffset = (weekStart - endWeekday + 7) % 7
        guard let gridEnd = calendar.date(byAdding: .day, value: trailingOffset, to: periodEnd) else { return nil }

        return (gridStart, gridEnd)
    }

    /// 6×7グリッドは、月の開始日設定を反映した会計月の実際の期間（開始日〜終了日前日）を表示する。
    /// デフォルト設定（開始日=1・調整なし）では暦月そのものと完全に一致する。
    /// 期間の長さは月の開始日・土日祝調整の設定次第で変動する（通常28〜31日+週単位の余白）ため、
    /// 行数は固定の6行ではなく可変になる（呼び出し側のCalendarMonthGridViewが動的に決める）。
    func makeCalendarDays(selectedDate: Date) -> [CalendarMonthDay] {
        guard let bounds = periodBounds(selectedDate: selectedDate) else { return [] }

        let periodStart = calendar.startOfDay(for: bounds.start)
        let periodEnd = calendar.startOfDay(for: bounds.end)

        guard let gridRange = weekAlignedGridRange(periodStart: periodStart, periodEnd: periodEnd) else { return [] }
        let totalDays = calendar.dateComponents([.day], from: gridRange.start, to: gridRange.end).day ?? 0
        guard totalDays > 0 else { return [] }

        return (0..<totalDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridRange.start) else { return nil }

            return CalendarMonthDay(
                date: date,
                isCurrentMonth: date >= periodStart && date < periodEnd
            )
        }
    }

    func incomeTotalOnDate(_ date: Date, incomeDataList: [IncomeData]) -> Int {
        incomeDataList
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map { $0.amount }
            .reduce(0, +)
    }

    func expenseTotalOnDate(_ date: Date, expenseDataList: [ExpenseData]) -> Int {
        expenseDataList
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map { $0.amount }
            .reduce(0, +)
    }

    func dailyTotal(date: Date, incomeDataList: [IncomeData], expenseDataList: [ExpenseData]) -> CalendarDailyTotal {
        let income = incomeTotalOnDate(date, incomeDataList: incomeDataList)
        let expense = expenseTotalOnDate(date, expenseDataList: expenseDataList)
        return CalendarDailyTotal(income: income, expense: expense, balance: income - expense)
    }

    func incomeTotalInMonth(selectedDate: Date, incomeDataList: [IncomeData]) -> Int {
        incomeDataList
            .filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
            .map { $0.amount }
            .reduce(0, +)
    }

    func expenseTotalInMonth(selectedDate: Date, expenseDataList: [ExpenseData]) -> Int {
        expenseDataList
            .filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
            .map { $0.amount }
            .reduce(0, +)
    }

    func monthlyTotal(selectedDate: Date, incomeDataList: [IncomeData], expenseDataList: [ExpenseData]) -> CalendarMonthlyTotal {
        let income = incomeTotalInMonth(selectedDate: selectedDate, incomeDataList: incomeDataList)
        let expense = expenseTotalInMonth(selectedDate: selectedDate, expenseDataList: expenseDataList)
        return CalendarMonthlyTotal(income: income, expense: expense, balance: income - expense)
    }

    func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    // MARK: - 月の開始日（会計月）設定
    //
    // アプリ全体共通の設定（AccountingMonthCalculator）に委譲する。
    // selectedDateの暦月をそのままanchorとして使うと、月の開始日設定によっては
    // selectedDateが実際にはanchorの1つ前の会計期間に属してしまうケースがある
    // （例：開始日=10日でselectedDate=7/9の場合、7/9は6/10〜7/9の期間に属する）。
    // そのため必ずAccountingMonthCalculator.range(containing:)で
    // 「selectedDateが実際に属する会計期間」を検索して求める。

    /// selectedDateが実際に属する会計期間 [actualStartDate, actualEndDate) を返す。
    /// デフォルト設定（開始日=1・調整=なし）の場合、これは暦月そのものと完全に一致する。
    func periodBounds(selectedDate: Date) -> (start: Date, end: Date)? {
        guard let range = AccountingMonthCalculator.range(containing: selectedDate, calendar: calendar) else { return nil }
        return (range.actualStartDate, range.actualEndDate)
    }

    /// monthAggregateが必要とする範囲（グリッド ∪ 繰越金計算に必要な範囲）の和集合を返す。
    /// グリッドは常に会計期間そのもの（前後の週単位の余白込み）を含むが、繰越金の計算は
    /// 「bounds.startを含む暦月の1日」から積み上げるため、月の開始日が大きい場合（例：28）は
    /// グリッドの前方余白（最大6日）だけでは足りず、別途この範囲をカバーする必要がある。
    func aggregateDateRange(selectedDate: Date) -> (start: Date, end: Date)? {
        guard let grid = gridDateRange(selectedDate: selectedDate),
              let bounds = periodBounds(selectedDate: selectedDate)
        else { return nil }
        let comps = calendar.dateComponents([.year, .month], from: bounds.start)
        guard let year = comps.year, let month = comps.month,
              let containingMonthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return nil }
        return (min(grid.start, containingMonthStart), max(grid.end, bounds.end))
    }

    /// 表示月の日別合計・月合計・繰越金を、事前計算済みのDailySnapshot/MonthlySnapshotから組み立てる。
    /// dailySnapshotsはaggregateDateRangeでカバーされる範囲で渡す。
    /// allMonthlySnapshotsは全期間ぶん（履歴の月数だけなので軽い）を渡し、内部で集計期間を解決する
    /// （SnapshotManagerが月次チェーンを構築するのは「今日を含む月」までのため、それより未来の月は
    /// 直近の過去月の月末残高をそのまま繰り越して解決する。resolveCarryoverを参照）。
    ///
    /// 月間集計（収入/支出合計）は、開始日が1以外の場合は暦月とズレるため、
    /// MonthlySnapshotの暦月ショートカットは使わず、集計期間 [bounds.start, bounds.end) の
    /// DailySnapshotを直接合算する（期間は最大でも1ヶ月+数日ぶんなので軽量）。
    /// 繰越金は、bounds.startを含む暦月の1日時点の残高（resolveCarryover）に、
    /// 「その月の1日 〜 bounds.start」ぶんのDailySnapshotの差分（最大27日+数日、軽量）を加算する。
    func monthAggregate(
        selectedDate: Date,
        dailySnapshots: [DailySnapshot],
        allMonthlySnapshots: [MonthlySnapshot]
    ) -> CalendarMonthAggregate {
        let dailyTotals = Dictionary(uniqueKeysWithValues: dailySnapshots.map { snapshot in
            (
                calendar.startOfDay(for: snapshot.date),
                CalendarDailyTotal(income: snapshot.incomeTotal, expense: snapshot.expenseTotal, balance: snapshot.netTotal)
            )
        })

        guard let bounds = periodBounds(selectedDate: selectedDate) else {
            return CalendarMonthAggregate(
                dailyTotals: dailyTotals,
                monthlyTotal: CalendarMonthlyTotal(income: 0, expense: 0, balance: 0),
                carryoverAmount: 0,
                periodStartDate: nil
            )
        }

        // 月間集計：[bounds.start, bounds.end) のDailySnapshotを合算する
        let periodSnapshots = dailySnapshots.filter { $0.date >= bounds.start && $0.date < bounds.end }
        let monthIncome = periodSnapshots.reduce(0) { $0 + $1.incomeTotal }
        let monthExpense = periodSnapshots.reduce(0) { $0 + $1.expenseTotal }
        let monthlyTotal = CalendarMonthlyTotal(
            income: monthIncome, expense: monthExpense, balance: monthIncome - monthExpense
        )

        // 繰越金：bounds.startを含む暦月の1日時点残高 + 「その月の1日 〜 bounds.start」ぶんの差分
        let startComps = calendar.dateComponents([.year, .month], from: bounds.start)
        let startYear = startComps.year ?? 0
        let startMonth = startComps.month ?? 0
        let baseCarryover = resolveCarryover(year: startYear, month: startMonth, allMonthlySnapshots: allMonthlySnapshots)
        var gap = 0
        if let containingMonthStart = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)) {
            gap = dailySnapshots
                .filter { $0.date >= containingMonthStart && $0.date < bounds.start }
                .reduce(0) { $0 + $1.netTotal }
        }

        // グリッドは常に会計期間そのもの（bounds.start〜bounds.end前日）を表示するため、
        // bounds.startは必ずグリッド内の「当該期間」セルとして表示される
        // （旧・暦月グリッド時代の「前倒しで前月にずれたらnil」という例外は不要になった）。
        return CalendarMonthAggregate(
            dailyTotals: dailyTotals,
            monthlyTotal: monthlyTotal,
            carryoverAmount: baseCarryover + gap,
            periodStartDate: bounds.start
        )
    }

    /// 指定した年月のMonthlySnapshotが存在すればそのrawCarryoverBalanceを返す。
    /// 存在しない場合（未来の月など、SnapshotManagerのチェーンがまだ届いていない月）は、
    /// 直近の過去月の月末残高（rawEndOfMonthBalance）をそのまま繰越として使う
    /// （それ以降に取引が無い以上、残高は変化しないため）。
    func resolveCarryover(year: Int, month: Int, allMonthlySnapshots: [MonthlySnapshot]) -> Int {
        let key = yearMonthKey(year: year, month: month)
        if let exact = allMonthlySnapshots.first(where: { $0.yearMonth == key }) {
            return exact.rawCarryoverBalance
        }
        guard let latestPrior = allMonthlySnapshots
            .filter({ $0.yearMonth < key })
            .max(by: { $0.yearMonth < $1.yearMonth })
        else { return 0 }
        return latestPrior.rawEndOfMonthBalance
    }

    private func yearMonthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    /// 繰越金を収入/支出のどちらに計上するかを振り分ける。
    /// プラスなら収入、マイナスなら支出（絶対値）、0ならどちらも0（非表示）。
    /// 通常の取引データには追加しない、表示・集計専用の仮想的な振り分け。
    func splitCarryover(_ amount: Int) -> (income: Int, expense: Int) {
        if amount > 0 { return (amount, 0) }
        if amount < 0 { return (0, -amount) }
        return (0, 0)
    }

    /// グリッド全体（会計期間＋前後の週単位の余白セル）の日付範囲を返す。makeCalendarDaysと同じ計算。
    func gridDateRange(selectedDate: Date) -> (start: Date, end: Date)? {
        guard let bounds = periodBounds(selectedDate: selectedDate) else { return nil }
        let periodStart = calendar.startOfDay(for: bounds.start)
        let periodEnd = calendar.startOfDay(for: bounds.end)
        return weekAlignedGridRange(periodStart: periodStart, periodEnd: periodEnd)
    }

    func formatYen(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted)円"
    }
}
