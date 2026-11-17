import Foundation

/// 日本の祝日判定・営業日計算を行う共通サービス。
///
/// カレンダーの色分け表示と、将来のクレジットカード引落日の翌営業日計算の
/// 両方から共通で利用することを想定している。祝日データは日付から計算するため、
/// DailySnapshot / MonthlySnapshot 等の永続データには一切保存しない。
///
/// 対応範囲は `supportedYearRange`（2020〜2035年）。この範囲外の年は祝日なし
/// （土日判定のみ）として扱われるため、「土日祝完全対応」を謳える精度ではない。
enum HolidayCalendarService {

    // MARK: - 対応範囲

    static let supportedYearRange = 2020...2035

    // MARK: - Public API

    /// 指定した日付が日本の祝日（振替休日・国民の休日を含む）かどうか
    static func isJapaneseHoliday(_ date: Date) -> Bool {
        holidayName(for: date) != nil
    }

    /// 指定した日付の祝日名（祝日でなければ nil）
    static func holidayName(for date: Date) -> String? {
        let cal = businessCalendar
        let year = cal.component(.year, from: date)
        return holidays(forYear: year)[dayKey(for: date, calendar: cal)]
    }

    /// 土曜日か
    static func isSaturday(_ date: Date) -> Bool {
        businessCalendar.component(.weekday, from: date) == 7
    }

    /// 日曜日か
    static func isSunday(_ date: Date) -> Bool {
        businessCalendar.component(.weekday, from: date) == 1
    }

    /// 土曜日または日曜日か
    static func isWeekend(_ date: Date) -> Bool {
        let weekday = businessCalendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// 土曜・日曜・祝日のいずれかであれば true（＝休業日）
    static func isNonBusinessDay(_ date: Date) -> Bool {
        isWeekend(date) || isJapaneseHoliday(date)
    }

    /// 土日祝ではない次の営業日を返す（クレジットカード引落日の翌営業日計算等に利用）
    static func nextBusinessDay(from date: Date) -> Date {
        let cal = businessCalendar
        var candidate = cal.date(byAdding: .day, value: 1, to: date) ?? date
        while isNonBusinessDay(candidate) {
            candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    /// 土日祝ではない直前の営業日を返す（月の開始日の前倒し等に利用）。
    /// 呼び出し側は nextBusinessDay と同様、isNonBusinessDay(date) で事前確認してから呼ぶこと
    /// （この関数は常に1日前から探索を始めるため、date自体が既に営業日の場合は使わない）。
    static func previousBusinessDay(from date: Date) -> Date {
        let cal = businessCalendar
        var candidate = cal.date(byAdding: .day, value: -1, to: date) ?? date
        while isNonBusinessDay(candidate) {
            candidate = cal.date(byAdding: .day, value: -1, to: candidate) ?? candidate
        }
        return candidate
    }

    /// dateがWeekendHolidayAdjustmentに従って調整された結果の日付を返す
    /// （.noneならそのまま。休業日でなければ何もしない。月またぎ・年またぎも
    /// previousBusinessDay/nextBusinessDayの日単位ループでそのまま処理される）。
    /// AccountingMonthCalculator.actualStartと同じ判定パターン。
    static func adjustedDate(for date: Date, adjustment: WeekendHolidayAdjustment) -> Date {
        switch adjustment {
        case .none:
            return date
        case .shiftEarlier:
            guard isNonBusinessDay(date) else { return date }
            return previousBusinessDay(from: date)
        case .shiftLater:
            guard isNonBusinessDay(date) else { return date }
            return nextBusinessDay(from: date)
        }
    }

    // MARK: - Calendar

    private static var businessCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return cal
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    // MARK: - 年ごとの祝日キャッシュ

    private static let cacheLock = NSLock()
    private static var cache: [Int: [String: String]] = [:]

    private static func holidays(forYear year: Int) -> [String: String] {
        guard supportedYearRange.contains(year) else { return [:] }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[year] { return cached }
        let computed = computeHolidays(year: year)
        cache[year] = computed
        return computed
    }

    // MARK: - 祝日の計算

    private static func computeHolidays(year: Int) -> [String: String] {
        let cal = businessCalendar
        var base: [(date: Date, name: String)] = []

        func addFixed(_ month: Int, _ day: Int, _ name: String) {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            if let date = cal.date(from: comps) {
                base.append((date, name))
            }
        }

        func addNthWeekday(_ month: Int, weekday: Int, nth: Int, name: String) {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.weekday = weekday
            comps.weekdayOrdinal = nth
            if let date = cal.date(from: comps) {
                base.append((date, name))
            }
        }

        // 元日
        addFixed(1, 1, "元日")
        // 成人の日：1月第2月曜（2000年以降）
        addNthWeekday(1, weekday: 2, nth: 2, name: "成人の日")
        // 建国記念の日
        addFixed(2, 11, "建国記念の日")
        // 天皇誕生日（2020年以降）
        addFixed(2, 23, "天皇誕生日")
        // 春分の日（近似計算）
        addFixed(3, vernalEquinoxDay(year: year), "春分の日")
        // 昭和の日
        addFixed(4, 29, "昭和の日")
        // 憲法記念日・みどりの日・こどもの日
        addFixed(5, 3, "憲法記念日")
        addFixed(5, 4, "みどりの日")
        addFixed(5, 5, "こどもの日")

        // 海の日・山の日・スポーツの日
        // 2020年・2021年は東京オリンピック特例で日付が変更されている
        switch year {
        case 2020:
            addFixed(7, 23, "海の日")
            addFixed(7, 24, "スポーツの日")
            addFixed(8, 10, "山の日")
        case 2021:
            addFixed(7, 22, "海の日")
            addFixed(7, 23, "スポーツの日")
            addFixed(8, 8, "山の日")
        default:
            addNthWeekday(7, weekday: 2, nth: 3, name: "海の日")
            addFixed(8, 11, "山の日")
            addNthWeekday(10, weekday: 2, nth: 2, name: "スポーツの日")
        }

        // 敬老の日：9月第3月曜
        addNthWeekday(9, weekday: 2, nth: 3, name: "敬老の日")
        // 秋分の日（近似計算）
        addFixed(9, autumnalEquinoxDay(year: year), "秋分の日")
        // 文化の日・勤労感謝の日
        addFixed(11, 3, "文化の日")
        addFixed(11, 23, "勤労感謝の日")

        return applySubstituteAndCitizensHolidays(base: base, calendar: cal)
    }

    /// 春分の日（近似式。2020〜2035年の範囲では実際の暦と一致する）
    private static func vernalEquinoxDay(year: Int) -> Int {
        Int(floor(20.8431 + 0.242194 * Double(year - 1980))) - (year - 1980) / 4
    }

    /// 秋分の日（近似式。2020〜2035年の範囲では実際の暦と一致する）
    private static func autumnalEquinoxDay(year: Int) -> Int {
        Int(floor(23.2488 + 0.242194 * Double(year - 1980))) - (year - 1980) / 4
    }

    // MARK: - 振替休日・国民の休日

    /// 振替休日（祝日が日曜日の場合、その後最初の祝日でない日を休日にする）と
    /// 国民の休日（前後を祝日に挟まれた、日曜日以外の平日を休日にする）を適用する
    private static func applySubstituteAndCitizensHolidays(
        base: [(date: Date, name: String)],
        calendar: Calendar
    ) -> [String: String] {
        var dict: [String: String] = [:]
        for (date, name) in base {
            dict[dayKey(for: date, calendar: calendar)] = name
        }

        let sortedDates = base.map(\.date).sorted()

        // 振替休日
        for date in sortedDates where calendar.component(.weekday, from: date) == 1 {
            var candidate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while dict[dayKey(for: candidate, calendar: calendar)] != nil {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            dict[dayKey(for: candidate, calendar: calendar)] = "振替休日"
        }

        // 国民の休日：祝日と祝日に挟まれた、日曜日以外の平日
        for date in sortedDates {
            guard
                let middleDate = calendar.date(byAdding: .day, value: 1, to: date),
                let nextDate = calendar.date(byAdding: .day, value: 2, to: date)
            else { continue }

            let middleKey = dayKey(for: middleDate, calendar: calendar)
            let nextKey = dayKey(for: nextDate, calendar: calendar)
            let middleWeekday = calendar.component(.weekday, from: middleDate)

            if dict[middleKey] == nil, middleWeekday != 1, dict[nextKey] != nil {
                dict[middleKey] = "国民の休日"
            }
        }

        return dict
    }
}
