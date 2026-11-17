import Foundation
import Combine

struct CalendarMonthDay: Identifiable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
}

struct CalendarDailyTotal {
    let income: Int
    let expense: Int
    let balance: Int
}

struct CalendarMonthlyTotal {
    let income: Int
    let expense: Int
    let balance: Int
}

/// 表示月1ヶ月分の集計結果をまとめたもの。
/// 日別合計（グリッドの42セル分）・月合計・前月繰越を1回の走査で作り、
/// 以降はこの値を読むだけにするためのキャッシュ用データ。
struct CalendarMonthAggregate {
    static let empty = CalendarMonthAggregate(
        dailyTotals: [:],
        monthlyTotal: CalendarMonthlyTotal(income: 0, expense: 0, balance: 0),
        carryoverAmount: 0,
        periodStartDate: nil
    )

    /// キーは calendar.startOfDay(for:) で正規化した日付
    let dailyTotals: [Date: CalendarDailyTotal]
    let monthlyTotal: CalendarMonthlyTotal
    let carryoverAmount: Int
    /// 繰越金の集計区切り日（「月の開始日」設定を反映した実際の開始日）。
    /// この日が表示月自身に収まる場合のみ非nil（前倒しで前月にずれた場合はnil＝
    /// どのセルにも繰越をハイライト表示しない。集計金額自体は常に正しい）。
    let periodStartDate: Date?
}
