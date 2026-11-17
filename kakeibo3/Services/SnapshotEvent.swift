import Foundation

// MARK: - スナップショット更新イベント
//
// 支出・収入・振替の保存/編集/削除や、口座・支払い方法・カテゴリーの設定変更など、
// 「何が起きたか」だけをViewやServiceが表明するためのイベント。
// このイベントを見てどのsnapshotを実際に更新するかは SnapshotUpdateService に集約する。
// Viewやその他のServiceはこのイベントを SnapshotUpdateService.handle(_:modelContext:) に
// 渡すだけにし、SnapshotManager/AnalysisSnapshotManager/SnapshotRebuildQueueを直接呼ばない。

enum SnapshotEvent {
    // 複数帳簿対応：収入・支出・振替はいずれも自身のbookIdに閉じてスナップショットを更新すればよい
    // （振替は帳簿をまたがない設計にしたため、TransferData自身もbookIdを持つ）。
    case expenseCreated(date: Date, bookId: UUID)
    case incomeCreated(date: Date, bookId: UUID)
    case transferCreated(date: Date, bookId: UUID)

    case expenseUpdated(oldDate: Date, newDate: Date, bookId: UUID)
    case incomeUpdated(oldDate: Date, newDate: Date, bookId: UUID)
    case transferUpdated(oldDate: Date, newDate: Date, bookId: UUID)

    case expenseDeleted(date: Date, bookId: UUID)
    case incomeDeleted(date: Date, bookId: UUID)
    case transferDeleted(date: Date, bookId: UUID)

    // 口座/支払い方法単位の設定変更（ロックON/OFF、分析表示ON/OFF、名前変更、初期残高変更など）。
    // 影響が1口座・1支払い方法に閉じる場合はこちらを使い、全期間の再構築を避ける。
    case bankAccountTouched(id: UUID)
    case methodTouched(name: String)

    // 資産反映タイミング変更・バックアップ復元・分析除外設定の一括変更など、全期間作り直しが必要なもの
    case fullRebuildRequested

    // カテゴリー変更（現在は名前変更・削除のみ実装済み。統合は将来機能のためのプレースホルダー）
    case categoryRenamed
    case categoryDeleted
    case categoryMerged
}
