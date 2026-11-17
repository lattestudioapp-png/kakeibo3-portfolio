import CoreData
import Foundation

// MARK: - CloudKitのremote change（他端末での変更のCloudKit経由の取り込み）を監視し、
// このデバイス自身の書き込みと同じようにSnapshot系派生データを再計算させる。
//
// CloudKit Step 2Aで両ストア（Cloud/Local）に persistent history tracking / remote change通知
// （NSPersistentHistoryTrackingKey / NSPersistentStoreRemoteChangeNotificationPostOptionKey）を
// 有効化済みだが、その通知を受け取って実際に何かする処理はまだ無かった
// （CoreDataStack.swift冒頭コメント参照）。このデバイス自身の書き込みは
// SnapshotUpdateService.handle(_:)経由でSnapshotManager/AnalysisSnapshotManagerを
// 直接再計算しているが、別端末での変更がCloudKit経由で取り込まれた場合はこの経路を通らないため、
// Local ConfigurationのDailySnapshot/MonthlySnapshot/AnalysisMonthlySnapshotが古いままになる
// ギャップがあった。これを埋める。
//
// AssetGraphCacheDataは対象外（既存設計で「更新ボタンを押した時だけ再計算、保存/編集/削除では
// 自動リビルドしない」方針。ローカル書き込みで自動リビルドしないものをリモート変更で自動リビルド
// する理由が無いため、既存の挙動と一貫させる）。
//
// v1では「1件でもリモート起因のtransactionがあればSnapshotRebuildQueue.shared.requestRebuild()
// （全件再計算）を1回呼ぶ」という粗い粒度にとどめる。remote changeの変更内容からbookId/日付範囲を
// 精密に特定して`SnapshotManager.touch(date:bookId:)`相当の狭い範囲だけ再計算する最適化は
// 今回のスコープ外（フルリビルドの冪等性は既に実証済みで、正しさを優先する）。
final class RemoteChangeObserver {
    static let shared = RemoteChangeObserver()

    static let lastHistoryTokenKey = "RemoteChangeObserver.lastHistoryToken"

    private var observationTask: Task<Void, Never>?

    // 【調査用診断ログ】CloudKit同期イベント(setup/import/export)の開始・終了・成否・時刻を記録する
    // （調査内容8：帳簿が消えるタイミングとCloudKit同期イベントの時間的関係を確認するため）。
    private var cloudKitEventTask: Task<Void, Never>?

    private init() {
        observationTask = Task.detached { [weak self] in
            let coordinator = CoreDataStack.shared.container.persistentStoreCoordinator
            for await _ in NotificationCenter.default.notifications(
                named: .NSPersistentStoreRemoteChange, object: coordinator
            ) {
                DiagnosticLog.write("REMOTE_CHANGE_NOTIFICATION: NSPersistentStoreRemoteChangeを受信")
                await self?.processNewHistory()
            }
        }
        cloudKitEventTask = Task.detached {
            for await note in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { continue }
                DiagnosticLog.logCloudKitEvent(event)
            }
        }
    }

    deinit {
        observationTask?.cancel()
        cloudKitEventTask?.cancel()
    }

    // MARK: - 履歴処理本体
    //
    // internal公開の理由: @testable経由でテストから直接・決定的に呼べるようにするため
    // （CoreDataStack.cloudStoreDescription(baseDirectory:enableCloudKit:)と同じ理由。
    // 実際のNSPersistentStoreRemoteChangeNotificationのタイミングに依存したテストは
    // フレーキーになりやすいため、通知配送そのものはテストしない）。
    func processNewHistory() async {
        let context = CoreDataStack.shared.container.newBackgroundContext()
        // context.perform<T>(_:) async -> T（iOS 15+の非同期版）でcontextの専用キューへ
        // 非ブロッキングにdispatchする。CoreDataStack.performAndSave<T>(_:)と同じ考え方だが、
        // あちらはviewContext専用のため、ここでは新規のbackgroundContextに対して直接使う。
        let result = await context.perform {
            Self.processHistorySynchronously(context: context)
        }
        if result.shouldRebuildSnapshots {
            SnapshotRebuildQueue.shared.requestRebuild()
        }
        // 他端末からCloudKit経由で届いたレシート写真を、ローカルのDocuments/receiptsへ書き出す。
        // ファイルI/Oのためcontextの専用キューの外（ここ）で行う。
        for photo in result.incomingPhotos {
            ReceiptPhotoSyncService.materializeIncoming(filename: photo.filename, imageData: photo.imageData)
        }
    }

    /// processHistorySynchronously(context:)の戻り値。Snapshot再計算の要否と、他端末から
    /// 届いた新規レシート写真(ローカルへの書き出しが必要なもの)の両方をまとめて返す。
    struct HistoryProcessingResult {
        let shouldRebuildSnapshots: Bool
        let incomingPhotos: [IncomingPhoto]
    }

    struct IncomingPhoto {
        let filename: String
        let imageData: Data
    }

    // context.perform{}のクロージャの中（＝そのcontextの専用キュー上）でのみ呼ぶこと。
    // NSManagedObjectContext.execute(_:)はcontextの専用キュー上で同期実行する必要がある。
    //
    // internal公開の理由: processNewHistory()自体（実際のNotificationCenter配送に依存する）
    // よりも一段テストしやすい単位として、@testableのテストから「このtransaction集合を
    // 与えたら再計算をトリガーすべきか」を同期的・決定的に検証できるようにするため
    // （RemoteChangeObserverTests参照）。
    static func processHistorySynchronously(context: NSManagedObjectContext) -> HistoryProcessingResult {
        let lastToken = loadLastHistoryToken()

        let cloudStoreID = CoreDataStack.shared.container.persistentStoreCoordinator
            .persistentStores
            .first { $0.url?.lastPathComponent == CoreDataStack.cloudStoreFileName }?
            .identifier

        let fetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
        guard let historyResult = try? context.execute(fetchRequest) as? NSPersistentHistoryResult,
              let transactions = historyResult.result as? [NSPersistentHistoryTransaction],
              !transactions.isEmpty
        else {
            return HistoryProcessingResult(shouldRebuildSnapshots: false, incomingPhotos: [])
        }

        // 【調査用診断ログ】この後すぐdeleteHistory(before:)でpurgeされ消えてしまうため、
        // purge前のこの時点で全トランザクション（自分自身の書き込み含む）のauthor・timestamp・
        // 変更内容の要約を記録する（調査内容7,8）。
        DiagnosticLog.logHistoryTransactions(transactions, cloudStoreID: cloudStoreID)

        // このデバイス自身の書き込み（author == CoreDataStack.transactionAuthor、常に"app"）は
        // SnapshotUpdateService.handle(_:)側で既にSnapshot再計算済みのため対象外。
        // Local store（storeID != cloudStoreID）の変更は絶対にCloudKit起因のリモート変更では
        // ありえないため、念のため二重にガードする。
        let remoteCloudTransactions = transactions.filter { transaction in
            transaction.author != CoreDataStack.transactionAuthor && transaction.storeID == cloudStoreID
        }

        // 他端末から届いたReceiptPhotoDataの新規・更新ぶんを抽出する（削除は対象外：
        // 所有する取引側のreceiptImagePath文字列も同じ理屈で同期されるため、UI表示は
        // そちら経由で自然に更新される。ローカルキャッシュファイルの削除は行わない
        // ＝孤立ファイルが残り得るが、二度と参照されないため実害は無い）。
        let incomingPhotos: [IncomingPhoto] = remoteCloudTransactions.flatMap { transaction -> [IncomingPhoto] in
            (transaction.changes ?? []).compactMap { change -> IncomingPhoto? in
                guard change.changedObjectID.entity.name == "ReceiptPhotoData" else { return nil }
                guard change.changeType == .insert || change.changeType == .update else { return nil }
                guard let cd = try? context.existingObject(with: change.changedObjectID) as? CDReceiptPhotoData,
                      let filename = cd.id, let imageData = cd.imageData
                else { return nil }
                return IncomingPhoto(filename: filename, imageData: imageData)
            }
        }

        // 【重要・根本原因の修正】以前はここで`NSPersistentHistoryChangeRequest.deleteHistory(before:)`
        // により、このデバイスが処理し終えた地点より前のpersistent historyを都度purgeしていた。
        // しかし実機調査で、このpurgeの直後に毎回
        // `CLOUDKIT_EVENT type=export succeeded=false error=NSCocoaErrorDomain Code=134301`
        // （persistent historyトークン無効化を示すエラー）→
        // `NSCloudKitMirroringDelegate.reset`（CloudKit同期側がローカルのCloud構成ミラー全体を
        // 削除して再インポートする内部処理）が発生し、BookData・CategoryData・ExpenseData等が
        // 丸ごと消える不具合につながっていることが、診断ログの直接観測で確認された。
        //
        // NSPersistentCloudKitContainer（CloudKitミラーリング機構）自身も、export対象の
        // 差分検出のためにpersistent historyを内部的に利用している。このアプリ側のRemoteChangeObserver
        // が「このデバイスが処理済みの地点」だけを基準に履歴を削除すると、CloudKitミラーリング機構が
        // まだ消費し終えていない履歴まで一緒に削除してしまう可能性があり、これがトークン無効化・
        // resetの引き金になっていたと考えられる。
        //
        // CloudKitミラーリング機構が内部的にどこまで処理済みかはアプリ側から正確に把握する手段が
        // 無いため、「CloudKit処理済みの範囲だけ削除する」という推測に基づく実装は行わない。
        // 安全側に倒し、履歴の削除自体を行わない設計とする。
        //
        // これにより持続的な記憶域の肥大化は起こり得るが、再処理防止自体は
        // `lastHistoryTokenKey`（このデバイスが最後に処理した地点）で既に保証されており、
        // deleteHistoryは再処理防止には必須ではなかった（純粋なディスク容量最適化のための
        // 呼び出しであり、削除してもこの関数の冪等性には影響しない）。
        if let newestToken = transactions.last?.token {
            saveLastHistoryToken(newestToken)
        }

        return HistoryProcessingResult(
            shouldRebuildSnapshots: !remoteCloudTransactions.isEmpty,
            incomingPhotos: incomingPhotos
        )
    }

    private static func loadLastHistoryToken() -> NSPersistentHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: lastHistoryTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    private static func saveLastHistoryToken(_ token: NSPersistentHistoryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: lastHistoryTokenKey)
    }
}
