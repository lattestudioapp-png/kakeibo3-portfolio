import SwiftUI

// MARK: - アプリ共通フォント

enum AppFonts {
    static let screenTitle = Font.system(size: 26, weight: .bold, design: .default)
    static let sectionTitle = Font.system(size: 18, weight: .semibold, design: .default)
    static let rowTitle = Font.system(size: 17, weight: .regular, design: .default)
    static let body = Font.system(size: 16, weight: .regular, design: .default)
    static let caption = Font.system(size: 13, weight: .regular, design: .default)
    static let button = Font.system(size: 18, weight: .semibold, design: .default)
    static let navigationTitle = Font.system(size: 11, weight: .regular, design: .default)
    static let navigationTitleSelected = Font.system(size: 11, weight: .semibold, design: .default)

    // 金額表示（丸みのあるデザインは使わず、太くしすぎない）
    // 履歴リスト・分析画面の一覧行などで使う金額
    static let listAmount = Font.system(size: 18, weight: .regular, design: .default)
    // 収入・支出・合計や総資産などのサマリー金額
    static let summaryAmount = Font.system(size: 24, weight: .regular, design: .default)
    // カレンダーの日付セル内に表示する小さい金額
    static let calendarSmallAmount = Font.system(size: 13, weight: .regular, design: .default)
}
