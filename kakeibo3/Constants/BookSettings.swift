import Foundation

// MARK: - 現在選択中の帳簿設定
//
// UUIDは@AppStorageで直接扱えないため、uuidStringとして保存する。
// View以外（Service層）からはUserDefaults.standard.string(forKey:)で直読みする
// （AccountingMonthCalculator/AnalysisSnapshotManager.currentAssetReflectionTiming()と同じ理由）。

enum BookSettings {
    static let storageKey = "selectedBookId"

    // 「帳簿の共有」画面で選択中の共有対象帳簿。アプリ全体で選択中の帳簿（storageKey）とは別に持つ。
    // 画面を開くたびにアプリの選択中帳簿へ合わせてしまうと、既に共有中の帳簿から
    // 別の帳簿へ勝手に共有対象が切り替わってしまうため、明示的に選んだ帳簿をここへ保持する。
    static let sharingTargetStorageKey = "bookSharingTargetBookId"
}
