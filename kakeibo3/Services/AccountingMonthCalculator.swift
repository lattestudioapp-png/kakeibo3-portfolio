import Foundation

// MARK: - 会計月の期間計算（カレンダー・予算・分析・グラフ共通）
//
// 「月の開始日」設定（1〜31日・土日祝の前倒し/後ろ倒し・年月表示の基準）から、
// 実際の集計期間（開始日〜終了日）とその表示用ラベル年月を計算する共通ユーティリティ。
// DailySnapshot/MonthlySnapshot（暦月キャッシュ）のスキーマは一切変更しない。
// 必要な場所がこのユーティリティを使って読み取り時に会計月へマッピングし直すだけにする
// （詳細は CalendarTransactionCalculator.monthAggregate の resolveCarryover パターン参照）。
//
// anchorYear/anchorMonth は「actualStartDateが属する暦月」を表す内部識別用の値。
// 「次/前の月へ」ナビゲーションは常にこのanchorを暦月単位で±1するだけでよく、
// 表示用のlabelYear/labelMonthはそこから導出される派生値であってナビゲーションの
// 入力には使わない（年月表示設定によってラベルは暦月とズレることがあるため）。

struct AccountingMonthRange {
    let anchorYear: Int
    let anchorMonth: Int
    /// 集計期間の開始日（土日祝調整を適用済み）
    let actualStartDate: Date
    /// 集計期間の終了日（排他的。次の期間のactualStartDateと同じ）
    let actualEndDate: Date
    /// 表示用の年月（年月表示設定を反映済み）
    let labelYear: Int
    let labelMonth: Int
}

enum AccountingMonthCalculator {

    // MARK: - 設定読み取り（UserDefaults直読み。View以外からも呼べるようにするため@AppStorageは使わない）

    private static func currentStartDay() -> Int {
        let stored = UserDefaults.standard.integer(forKey: AccountingMonthSettings.startDayStorageKey)
        return stored == 0 ? AccountingMonthSettings.startDayDefaultValue : AccountingMonthSettings.clampedStoredDay(stored)
    }

    private static func currentAdjustment() -> WeekendHolidayAdjustment {
        UserDefaults.standard.string(forKey: WeekendHolidayAdjustment.storageKey)
            .flatMap { WeekendHolidayAdjustment(rawValue: $0) } ?? WeekendHolidayAdjustment.defaultValue
    }

    private static func currentLabelBasis() -> AccountingMonthLabelBasis {
        UserDefaults.standard.string(forKey: AccountingMonthLabelBasis.storageKey)
            .flatMap { AccountingMonthLabelBasis(rawValue: $0) } ?? AccountingMonthLabelBasis.defaultValue
    }

    /// 現在の設定が「デフォルト（開始日=1・調整=なし）」かどうか。
    /// 予算/分析側で「暦月ショートカット（スナップショット高速パス）を使ってよいか」の判定に使う。
    /// labelBasisは境界計算に無関係なので判定に含めない。
    static func isDefaultBoundary() -> Bool {
        currentStartDay() == AccountingMonthSettings.startDayDefaultValue && currentAdjustment() == .none
    }

    // MARK: - 期間計算

    /// anchorYear/anchorMonthを軸に、実際の集計開始日を計算する（土日祝調整を適用済み）。
    private static func actualStart(year: Int, month: Int, calendar: Calendar) -> Date? {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count
        else { return nil }

        let day = AccountingMonthSettings.resolvedDay(for: currentStartDay(), daysInMonth: daysInMonth)
        guard let raw = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }

        switch currentAdjustment() {
        case .none:
            return raw
        case .shiftEarlier:
            guard HolidayCalendarService.isNonBusinessDay(raw) else { return raw }
            return HolidayCalendarService.previousBusinessDay(from: raw)
        case .shiftLater:
            guard HolidayCalendarService.isNonBusinessDay(raw) else { return raw }
            return HolidayCalendarService.nextBusinessDay(from: raw)
        }
    }

    /// anchorYear/anchorMonthをoffset分だけ進める（year*12+month の整数演算で
    /// 月またぎ・年またぎを処理し、Calendar.date(byAdding:.month:)の月末挙動の曖昧さを避ける）。
    static func adjacentAnchor(year: Int, month: Int, offset: Int) -> (year: Int, month: Int) {
        let total = year * 12 + (month - 1) + offset
        return (total / 12, total % 12 + 1)
    }

    /// anchorYear/anchorMonthを軸に集計期間を返す。
    static func range(anchorYear: Int, anchorMonth: Int, calendar: Calendar = .current) -> AccountingMonthRange? {
        guard let start = actualStart(year: anchorYear, month: anchorMonth, calendar: calendar) else { return nil }
        let next = adjacentAnchor(year: anchorYear, month: anchorMonth, offset: 1)
        guard let end = actualStart(year: next.year, month: next.month, calendar: calendar) else { return nil }

        let label = labelYearMonth(anchorYear: anchorYear, anchorMonth: anchorMonth, end: end, calendar: calendar)

        return AccountingMonthRange(
            anchorYear: anchorYear, anchorMonth: anchorMonth,
            actualStartDate: start, actualEndDate: end,
            labelYear: label.year, labelMonth: label.month
        )
    }

    private static func labelYearMonth(
        anchorYear: Int, anchorMonth: Int, end: Date, calendar: Calendar
    ) -> (year: Int, month: Int) {
        switch currentLabelBasis() {
        case .startDate:
            return (anchorYear, anchorMonth)
        case .endDate:
            // 期間内の最終日（endDateの1日前）が属する暦月をラベルにする
            guard let lastDay = calendar.date(byAdding: .day, value: -1, to: end) else {
                return (anchorYear, anchorMonth)
            }
            let comps = calendar.dateComponents([.year, .month], from: lastDay)
            return (comps.year ?? anchorYear, comps.month ?? anchorMonth)
        }
    }

    /// 指定日が属する会計期間を返す（繰越金計算・「今はどの会計月か」判定に使う）。
    ///
    /// rawStartは常にその暦月自身の中に収まる（DateComponents(year,month,day)で作るため）が、
    /// 土日祝調整（前倒し/後ろ倒し）によって隣の暦月にずれることがある。ただし調整幅は
    /// HolidayCalendarServiceの最長連続非営業日ラン（1週間未満）で頭打ちになり、暦月の
    /// 最短日数（28日）より必ず短いため、dateの暦月を初期推測にして±1（念のため±2まで）
    /// を試せば必ず正しいanchorに辿り着く。
    static func range(containing date: Date, calendar: Calendar = .current) -> AccountingMonthRange? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let guessYear = comps.year, let guessMonth = comps.month else { return nil }

        for offset in [0, -1, 1, -2, 2] {
            let candidate = adjacentAnchor(year: guessYear, month: guessMonth, offset: offset)
            guard let candidateRange = range(anchorYear: candidate.year, anchorMonth: candidate.month, calendar: calendar)
            else { continue }
            if date >= candidateRange.actualStartDate && date < candidateRange.actualEndDate {
                return candidateRange
            }
        }
        // 理論上ここには到達しないはずだが、念のためdate自身の暦月にフォールバックする
        return range(anchorYear: guessYear, anchorMonth: guessMonth, calendar: calendar)
    }

    // MARK: - ラベル年月からanchorを逆引き（月ピッカー用）
    //
    // 通常はlabel(anchor)==anchorだが、開始日が小さい値＋前倒し設定の組み合わせでは
    // 稀に非単射になりうる（複数のanchorが同じラベルを生成する）。その場合は最も新しい
    // （直近の）anchorを採用する。

    static func anchor(forLabelYear targetYear: Int, labelMonth targetMonth: Int, calendar: Calendar = .current) -> (year: Int, month: Int) {
        var best: (year: Int, month: Int)? = nil
        for offset in -2...1 {
            let candidate = adjacentAnchor(year: targetYear, month: targetMonth, offset: offset)
            guard let candidateRange = range(anchorYear: candidate.year, anchorMonth: candidate.month, calendar: calendar)
            else { continue }
            guard candidateRange.labelYear == targetYear, candidateRange.labelMonth == targetMonth else { continue }
            if let current = best {
                let currentTotal = current.year * 12 + current.month
                let candidateTotal = candidate.year * 12 + candidate.month
                if candidateTotal > currentTotal { best = candidate }
            } else {
                best = candidate
            }
        }
        return best ?? (targetYear, targetMonth)
    }
}
