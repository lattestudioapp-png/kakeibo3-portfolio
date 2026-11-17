import SwiftUI
import Combine

enum AppColors {
    // テーマカラー管理
    static let themeColorStorageKey = "selectedThemeColorHex"
    static let defaultThemeHex     = "#52806E"  // デフォルトグリーン

    // ヘッダーの色（UserDefaults から動的に取得）
    static var main: Color {
        let hex = UserDefaults.standard.string(forKey: themeColorStorageKey) ?? defaultThemeHex
        return ColorHexConverter.color(from: hex)
    }
    // 背景（テーマカラーから動的生成）
    // 注意: .opacity() で半透明にすると、fullScreenCover の入れ子など
    // 背後に別の画面が残るケースで透けて見えるバグになるため、
    // 白に対してあらかじめ合成した「不透明な」色を返す。
    static var background: Color {
        let hex = UserDefaults.standard.string(forKey: themeColorStorageKey) ?? defaultThemeHex
        let c = ColorHexConverter.rgbComponents(from: hex)
        let tint = 0.05
        return Color(
            red:   c.red   * tint + 1.0 * (1 - tint),
            green: c.green * tint + 1.0 * (1 - tint),
            blue:  c.blue  * tint + 1.0 * (1 - tint)
        )
    }
    // sheet表示画面（検索・振替・各種設定など）共通の背景色。
    // アプリ全体の背景と同じ色を1箇所から参照させることで、
    // 変更時にここだけ直せば全sheetに反映されるようにする。
    static var sheetBackground: Color { background }
    // 縁の灰色
    static let line = Color.gray.opacity(0.18)
    // バツボタン
    static let cancel = Color.gray.opacity(0.4)
    // ヘッダータイトル文字色
    static let headerTitle = Color.white
    // ヘッダーボタン共通（Close / Done / Search）
    static let headerButtonBackground = Color.white.opacity(0.55)
    static let headerButtonIcon = Color.black.opacity(0.75)
    // 収入・プラス収支・資産増加（カレンダーViewの収入金額と同じ色）
    static let incomeColor  = Color(red: 0.00, green: 0.48, blue: 1.00).opacity(0.80)
    // 支出・マイナス収支・資産減少（カレンダーViewの支出金額と同じ色）
    static let expenseColor = Color(red: 1.00, green: 0.23, blue: 0.25).opacity(0.75)
}
