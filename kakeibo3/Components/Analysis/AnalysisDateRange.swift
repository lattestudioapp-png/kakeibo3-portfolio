import Foundation

struct AnalysisDateRange {
    let start: Date
    let end: Date  // exclusive

    var daysInPeriod: Int {
        let cal = Calendar.current
        let now = Date()

        if end > now {
            // 期間が進行中（今月・今年など）→ 開始日から「今日」までを含めた日数
            let startDay = cal.startOfDay(for: start)
            let todayStart = cal.startOfDay(for: now)
            guard todayStart >= startDay else { return 1 }
            let days = cal.dateComponents([.day], from: startDay, to: todayStart).day ?? 0
            return max(1, days + 1)
        } else {
            // 期間がすでに終了している（先月・過去のカスタム期間など）→ start〜end(exclusive)の実日数
            guard end > start else { return 1 }
            let days = cal.dateComponents([.day], from: start, to: end).day ?? 1
            return max(1, days)
        }
    }
}

struct AnalysisDateRangeCalculator {

    static func current(
        for periodType: AnalysisPeriodType,
        referenceDate: Date,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> AnalysisDateRange {
        let cal = Calendar.current

        // referenceDateの暦月をそのままanchorとして使うと、月の開始日設定次第では
        // referenceDateが実際に属する会計期間とズレることがある（例：開始日=10日で
        // referenceDate=7/9の場合、7/9は6/10〜7/9の会計期間に属する）ため、
        // 必ずrange(containing:)でreferenceDateが実際に属する会計期間を検索して求める。
        let currentAccountingRange = AccountingMonthCalculator.range(containing: referenceDate, calendar: cal)

        // フォールバック用（AccountingMonthCalculatorが失敗した場合のみ使う、単純な暦月計算）
        func fallbackMonthBounds() -> (start: Date, end: Date) {
            let comps = cal.dateComponents([.year, .month], from: referenceDate)
            let monthStart = cal.date(from: comps) ?? referenceDate
            let nextMonthStart = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return (monthStart, nextMonthStart)
        }

        switch periodType {
        case .month:
            // デフォルト設定（開始日=1・調整なし）では暦月そのものと完全に一致する。
            guard let range = currentAccountingRange else {
                let fallback = fallbackMonthBounds()
                return AnalysisDateRange(start: fallback.start, end: fallback.end)
            }
            return AnalysisDateRange(start: range.actualStartDate, end: range.actualEndDate)

        case .previousMonth:
            guard let currentRange = currentAccountingRange else {
                let fallback = fallbackMonthBounds()
                let prevStart = cal.date(byAdding: .month, value: -1, to: fallback.start) ?? fallback.start
                return AnalysisDateRange(start: prevStart, end: fallback.start)
            }
            let prevAnchor = AccountingMonthCalculator.adjacentAnchor(
                year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: -1
            )
            guard let prevRange = AccountingMonthCalculator.range(anchorYear: prevAnchor.year, anchorMonth: prevAnchor.month, calendar: cal)
            else {
                let fallback = fallbackMonthBounds()
                let prevStart = cal.date(byAdding: .month, value: -1, to: fallback.start) ?? fallback.start
                return AnalysisDateRange(start: prevStart, end: fallback.start)
            }
            return AnalysisDateRange(start: prevRange.actualStartDate, end: prevRange.actualEndDate)

        case .year:
            let year = cal.component(.year, from: referenceDate)
            let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? referenceDate
            let yearEnd = cal.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
            return AnalysisDateRange(start: yearStart, end: yearEnd)

        case .allTime:
            // 全データを対象とする。終端は今日の終わり（明日の開始）
            let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
            return AnalysisDateRange(start: .distantPast, end: tomorrowStart)

        case .custom:
            let start = cal.startOfDay(for: customStart ?? referenceDate)
            let endDay = cal.startOfDay(for: customEnd ?? referenceDate)
            let end = cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return AnalysisDateRange(start: start, end: max(end, start))
        }
    }

    static func previous(
        for periodType: AnalysisPeriodType,
        referenceDate: Date,
        customStart: Date? = nil,
        customEnd: Date? = nil
    ) -> AnalysisDateRange {
        let cal = Calendar.current

        // referenceDateの暦月をそのままanchorとして使うと、月の開始日設定次第では
        // 実際に属する会計期間とズレることがあるため、range(containing:)で求める。
        let currentAccountingRange = AccountingMonthCalculator.range(containing: referenceDate, calendar: cal)

        func fallbackMonthBounds() -> (start: Date, end: Date) {
            let comps = cal.dateComponents([.year, .month], from: referenceDate)
            let monthStart = cal.date(from: comps) ?? referenceDate
            let nextMonthStart = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return (monthStart, nextMonthStart)
        }

        switch periodType {
        case .month:
            guard let currentRange = currentAccountingRange else {
                let fallback = fallbackMonthBounds()
                let prevStart = cal.date(byAdding: .month, value: -1, to: fallback.start) ?? fallback.start
                return AnalysisDateRange(start: prevStart, end: fallback.start)
            }
            let prevAnchor = AccountingMonthCalculator.adjacentAnchor(
                year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: -1
            )
            guard let prevRange = AccountingMonthCalculator.range(anchorYear: prevAnchor.year, anchorMonth: prevAnchor.month, calendar: cal)
            else {
                let fallback = fallbackMonthBounds()
                let prevStart = cal.date(byAdding: .month, value: -1, to: fallback.start) ?? fallback.start
                return AnalysisDateRange(start: prevStart, end: fallback.start)
            }
            return AnalysisDateRange(start: prevRange.actualStartDate, end: currentRange.actualStartDate)

        case .previousMonth:
            guard let currentRange = currentAccountingRange else {
                let fallback = fallbackMonthBounds()
                let prevStart = cal.date(byAdding: .month, value: -2, to: fallback.start) ?? fallback.start
                let prevEnd = cal.date(byAdding: .month, value: -1, to: fallback.start) ?? fallback.start
                return AnalysisDateRange(start: prevStart, end: prevEnd)
            }
            let prevAnchor = AccountingMonthCalculator.adjacentAnchor(
                year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: -1
            )
            let prevPrevAnchor = AccountingMonthCalculator.adjacentAnchor(
                year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: -2
            )
            guard let prevRange = AccountingMonthCalculator.range(anchorYear: prevAnchor.year, anchorMonth: prevAnchor.month, calendar: cal),
                  let prevPrevRange = AccountingMonthCalculator.range(anchorYear: prevPrevAnchor.year, anchorMonth: prevPrevAnchor.month, calendar: cal)
            else {
                let fallback = fallbackMonthBounds()
                let prevStart = cal.date(byAdding: .month, value: -2, to: fallback.start) ?? fallback.start
                let prevEnd = cal.date(byAdding: .month, value: -1, to: fallback.start) ?? fallback.start
                return AnalysisDateRange(start: prevStart, end: prevEnd)
            }
            return AnalysisDateRange(start: prevPrevRange.actualStartDate, end: prevRange.actualStartDate)

        case .year:
            let year = cal.component(.year, from: referenceDate)
            let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? referenceDate
            let prevYearStart = cal.date(byAdding: .year, value: -1, to: yearStart) ?? yearStart
            return AnalysisDateRange(start: prevYearStart, end: yearStart)

        case .allTime:
            // 全期間は前期間比なし。空の範囲を返すと prevData が空になり比較が非表示になる
            return AnalysisDateRange(start: .distantPast, end: .distantPast)

        case .custom:
            let rangeStart = cal.startOfDay(for: customStart ?? referenceDate)
            let rangeEndDay = cal.startOfDay(for: customEnd ?? referenceDate)
            let rangeEnd = cal.date(byAdding: .day, value: 1, to: rangeEndDay) ?? rangeEndDay
            let duration = max(1, cal.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 1)
            let prevEnd = rangeStart
            let prevStart = cal.date(byAdding: .day, value: -duration, to: prevEnd) ?? prevEnd
            return AnalysisDateRange(start: prevStart, end: prevEnd)
        }
    }
}
