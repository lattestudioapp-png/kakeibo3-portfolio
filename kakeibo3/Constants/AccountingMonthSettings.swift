import Foundation

// MARK: - 会計月（月の開始日）設定
//
// カレンダー・予算・分析・グラフで共通して使う「月」の区切り日。
// 保存済みの取引データ（日付）自体は一切変更せず、表示・集計時の期間の切り方だけを変える。
// 実際の期間計算は AccountingMonthCalculator が担う。

enum AccountingMonthSettings {
    static let startDayStorageKey = "accountingMonthStartDay"
    static let startDayDefaultValue = 1
    static let minDay = 1
    static let maxDay = 31

    static func clampedStoredDay(_ value: Int) -> Int {
        (minDay...maxDay).contains(value) ? value : startDayDefaultValue
    }

    /// 実際の月の日数に合わせてクランプする（31日設定で2月なら28/29日、4月なら30日）
    static func resolvedDay(for storedDay: Int, daysInMonth: Int) -> Int {
        min(storedDay, daysInMonth)
    }
}

// MARK: - 開始日が土日祝の場合の調整

enum WeekendHolidayAdjustment: String, CaseIterable {
    case none
    case shiftEarlier
    case shiftLater

    static let storageKey = "accountingMonthWeekendHolidayAdjustment"
    static let defaultValue = WeekendHolidayAdjustment.none

    var displayName: String {
        switch self {
        case .none:         return "何もしない"
        case .shiftEarlier: return "直前の平日にする"
        case .shiftLater:   return "直後の平日にする"
        }
    }
}

// MARK: - 年月表示の基準

enum AccountingMonthLabelBasis: String, CaseIterable {
    case startDate
    case endDate

    static let storageKey = "accountingMonthLabelBasis"
    static let defaultValue = AccountingMonthLabelBasis.startDate

    var displayName: String {
        switch self {
        case .startDate: return "開始日に合わせる"
        case .endDate:   return "終了日に合わせる"
        }
    }
}
