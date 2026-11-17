import Foundation

// MARK: - カレンダータブ設定：週の開始曜日
//
// 「月の開始日」（会計月の区切り日）はアプリ全体共通の設定になったため
// AccountingMonthSettings.swift に移動した。ここに残るのは、カレンダーの
// 6×7グリッドの先頭列が何曜日から始まるかという、無関係な別設定だけ。

enum CalendarWeekStartSettings {
    // Calendar.weekday準拠：1=日, 2=月, 3=火, 4=水, 5=木, 6=金, 7=土
    static let storageKey = "calendarWeekStartWeekday"
    static let defaultValue = 1
    static let validRange = 1...7

    static func clamped(_ value: Int) -> Int {
        validRange.contains(value) ? value : defaultValue
    }
}
