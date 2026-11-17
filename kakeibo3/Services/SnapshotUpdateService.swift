import Foundation

// MARK: - スナップショット更新の唯一の窓口
//
// 「どのイベントでどのsnapshotを更新するか」の判定をここに集約する。
// ViewやRepository/Serviceは保存処理の後にこの handle(_:) を呼ぶだけにし、
// SnapshotManager/AnalysisSnapshotManager/SnapshotRebuildQueue を直接呼んではいけない。
//
// 中身は既存の SnapshotManager/AnalysisSnapshotManager/SnapshotRebuildQueue の
// 呼び出しをそのまま流用しているだけで、実際の再計算ロジック・範囲は一切変えていない
// （振る舞いを変えずに呼び出し経路だけを一本化するリファクタリング）。

enum SnapshotUpdateService {

    static func handle(_ event: SnapshotEvent) {
        switch event {
        case .expenseCreated(let date, let bookId), .incomeCreated(let date, let bookId), .transferCreated(let date, let bookId):
            SnapshotManager.touch(date: date, bookId: bookId)
            AnalysisSnapshotManager.touch(date: date, bookId: bookId)

        case .expenseUpdated(let oldDate, let newDate, let bookId),
             .incomeUpdated(let oldDate, let newDate, let bookId),
             .transferUpdated(let oldDate, let newDate, let bookId):
            SnapshotManager.touch(date: oldDate, bookId: bookId)
            AnalysisSnapshotManager.touch(date: oldDate, bookId: bookId)
            if newDate != oldDate {
                SnapshotManager.touch(date: newDate, bookId: bookId)
                AnalysisSnapshotManager.touch(date: newDate, bookId: bookId)
            }

        case .expenseDeleted(let date, let bookId), .incomeDeleted(let date, let bookId), .transferDeleted(let date, let bookId):
            SnapshotManager.touch(date: date, bookId: bookId)
            AnalysisSnapshotManager.touch(date: date, bookId: bookId)

        case .bankAccountTouched(let id):
            SnapshotRebuildQueue.shared.requestBankAccountTouch(bankAccountId: id)

        case .methodTouched(let name):
            SnapshotRebuildQueue.shared.requestMethodTouch(methodName: name)

        case .fullRebuildRequested:
            SnapshotRebuildQueue.shared.requestRebuild()

        case .categoryRenamed:
            break // 金額は変わらないため何もしない

        case .categoryDeleted, .categoryMerged:
            // 現状カテゴリー内訳はsnapshotに無いため実質no-opに近いが、
            // 将来カテゴリー内訳を追加した際にそのまま効くようにルールだけ先に反映しておく
            SnapshotRebuildQueue.shared.requestRebuild()
        }
    }
}
