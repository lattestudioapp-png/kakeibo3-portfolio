import Foundation

// MARK: - 開発中機能のフィーチャーフラグ
//
// 実装は完了しているが公開版にはまだ出したくない機能を、ここで一括してON/OFFする。
// falseの間はUI導線を一切表示しない（コード・ファイルは削除せず再利用可能な状態で残す）。

enum FeatureFlags {
    /// レシート撮影OCR機能（入力タブの「レシート」セグメント、撮影〜保存フロー一式）。
    /// 開発継続中のため公開版では非表示。trueにすると入力タブに「レシート」が復活する。
    static let isReceiptFeatureEnabled = false
}
