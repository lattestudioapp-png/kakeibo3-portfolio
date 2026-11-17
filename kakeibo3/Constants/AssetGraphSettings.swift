import Foundation

// MARK: - 資産推移グラフの表示点数設定
//
// グラフの「細かさ」＝表示に使う最大点数。この値だけを見て、
// AssetGraphPointReducer が実際の粒度（日別/週別/月別/年別）を選ぶ。
// 設定を変更しても ExpenseData/IncomeData や各種snapshotの中身は一切変更しない
// （表示用データの作り方が変わるだけ）。

enum AssetGraphSettings {
    static let storageKey = "assetGraphMaxPoints"
    static let defaultValue = 60

    static let minCustom = 20
    static let maxCustom = 150

    /// プリセットの選択肢（少なめ/標準/多め）
    static let presets: [Int] = [30, 60, 100]

    static func presetLabel(for value: Int) -> String? {
        switch value {
        case 30: return "少なめ"
        case 60: return "標準"
        case 100: return "多め"
        default: return nil
        }
    }

    /// 保存前に必ずこの範囲へ収める
    static func clamped(_ value: Int) -> Int {
        min(maxCustom, max(minCustom, value))
    }
}
