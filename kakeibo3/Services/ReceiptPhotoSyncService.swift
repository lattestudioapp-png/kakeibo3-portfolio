import CoreData
import Foundation

// MARK: - レシート写真のCloudKit同期オーケストレーション
//
// ReceiptImageHelperが管理するローカルファイル(Documents/receipts/*.jpg)と、CloudKit経由で
// 同期されるReceiptPhotoData(Core Data, allowsExternalBinaryDataStorage="YES")の対応を取る。
// 表示は常にローカルファイルから行う(既存のReceiptImageHelper.load系はそのまま使える)ため、
// 同期に失敗していてもローカル表示には影響しない。
//
// 設計上の前提：
// - id(ファイル名)はReceiptImageHelperが常に新規UUIDで発行するため、通常の追加・編集では
//   同じファイル名に対してensureSyncedが複数回呼ばれることはない。ただしbackfillAllIfNeeded()
//   は既存ファイル名に対して複数回呼ばれる可能性があるため、挿入前に必ず存在確認する
//   （ReceiptPhotoDataSync.insertIfMissing参照。再実行・iCloud同期OFF→ONでも重複しない）。
// - 画像データは一切リサイズ・再圧縮しない。ローカルファイルのバイト列をそのままコピーする
//   （レシートOCRの読み取り精度を優先するため。ReceiptImageHelper.loadData/writeIfMissing参照）。
// - iCloud同期OFF中のセッションでもReceiptPhotoDataへの挿入・削除自体は行う。Cloud Configuration
//   はCloudKit接続が無くても通常のCore Dataとして動作するため(CloudSyncSettings.swift参照)、
//   ローカルの読み書き自体は妨げられない。単に他端末との共有が止まるだけ。
enum ReceiptPhotoSyncService {

    /// 他端末からの写真がローカルへ新規に書き出された時に発行する通知（修正2：画面の自動更新用）。
    /// userInfo["filename"]に書き出されたファイル名（String）が入る。
    static let photoMaterializedNotification = Notification.Name("ReceiptPhotoSyncService.photoMaterialized")

    /// 取引の保存（追加・編集）成功後に呼ぶ。指定したファイル名のうち、まだReceiptPhotoDataに
    /// 無いものだけをローカルファイルから読み込んで追加する。ローカルファイルが読めない
    /// （既に失われている等）場合はそのファイルだけ静かにスキップし、他のファイルの処理は続ける。
    static func ensureSynced(
        filenames: [String],
        transactionType: ReceiptPhotoTransactionType,
        transactionId: UUID,
        bookId: UUID
    ) {
        for (index, filename) in filenames.enumerated() {
            guard !ReceiptPhotoDataSync.exists(id: filename) else { continue }
            guard let data = ReceiptImageHelper.loadData(filename) else { continue }
            let photo = ReceiptPhotoData(
                id: filename,
                transactionType: transactionType,
                transactionId: transactionId,
                bookId: bookId,
                sortOrder: index,
                imageData: data,
                createdAt: Date()
            )
            ReceiptPhotoDataSync.insertIfMissing(photo)
        }
    }

    /// 写真ファイルの削除（ReceiptImageHelper.deleteAll相当）と対で呼ぶ。
    /// ローカルファイルの削除とは独立しており、どちらを先に呼んでも問題ない。
    static func removeSynced(filenames: [String]) {
        ReceiptPhotoDataSync.deleteAll(ids: filenames)
    }

    /// 起動のたびに呼ぶ安全網。(1) この機能の実装前から存在する既存の写真を1回だけ移行する、
    /// (2) ensureSynced単体呼び出しが途中で失敗・中断したケースを後から補う、の両方を兼ねる。
    /// 既存の.jpgファイル・収支データ(receiptImagePath含む)は読み取り専用で一切変更しない。
    /// ゴミ箱内（完全削除前）のデータも対象に含める（写真ファイル自体はまだ存在するため）。
    static func backfillAllIfNeeded() {
        let bookIds = BookDataSync.fetchAll().map(\.id)

        var expenses = ExpenseDataSync.fetchAll()
        var incomes = IncomeDataSync.fetchAll()
        var transfers = TransferDataSync.fetchAll()
        for bookId in bookIds {
            expenses += ExpenseDataSync.fetchTrashed(bookId: bookId)
            incomes += IncomeDataSync.fetchTrashed(bookId: bookId)
            transfers += TransferDataSync.fetchTrashed(bookId: bookId)
        }

        for expense in expenses {
            backfill(
                paths: expense.receiptImagePath, transactionType: .expense,
                transactionId: expense.id, bookId: expense.bookId
            )
        }
        for income in incomes {
            backfill(
                paths: income.receiptImagePath, transactionType: .income,
                transactionId: income.id, bookId: income.bookId
            )
        }
        for transfer in transfers {
            backfill(
                paths: transfer.receiptImagePath, transactionType: .transfer,
                transactionId: transfer.id, bookId: transfer.bookId
            )
        }
    }

    private static func backfill(
        paths: String?,
        transactionType: ReceiptPhotoTransactionType,
        transactionId: UUID,
        bookId: UUID?
    ) {
        // bookIdが無い(移行未実施等の異常系)場合は対象外とする。通常運用では発生しない。
        guard let bookId else { return }
        let filenames = ReceiptImageHelper.decodePaths(paths)
        guard !filenames.isEmpty else { return }
        ensureSynced(filenames: filenames, transactionType: transactionType, transactionId: transactionId, bookId: bookId)
    }

    /// 別端末からCloudKit経由で届いたReceiptPhotoDataを、ローカルのDocuments/receiptsへ
    /// 書き出す（RemoteChangeObserver専用。リアルタイム経路）。既に同名ファイルが存在する場合は
    /// 絶対に上書きしない。
    static func materializeIncoming(filename: String, imageData: Data) {
        materialize(filename: filename, imageData: imageData)
    }

    /// 起動のたびに呼ぶダウンロード方向の安全網（修正1）。
    ///
    /// RemoteChangeObserverはNSPersistentStoreRemoteChangeNotificationが実際に発火した
    /// 瞬間にしか動かない。そのため「CloudKitからの取り込みでReceiptPhotoData行は既に
    /// ローカルのCore Dataへ書き込まれたが、アプリが終了する等でその通知をまだ処理できて
    /// いない（かつ、以後そのレコードについて新たな変更が無ければ通知が再発火しない）」
    /// という欠落が起こり得る。この関数は通知の有無に依存せず、Core Data上の実データを
    /// 直接確認して補う。
    ///
    /// - 既存の.jpgファイルは絶対に上書きしない（ReceiptImageHelper.writeIfMissing参照）。
    /// - 既存の収支データ（receiptImagePath含む）には一切触れない（読み取りも行わない。
    ///   ReceiptPhotoData自体のみを見る）。
    /// - idが既に存在する/ファイルが既にある写真は対象外になる（ReceiptPhotoData.idは
    ///   ファイル名そのもののため、再実行しても重複書き出しにはならない）。
    /// - メインスレッドをブロックしないよう、全体をTask.detachedで実行する
    ///   （呼び出し元のKakeibo3App.onAppearは同期的に呼べる）。
    /// - 途中でアプリが終了しても安全：状態を持たず、毎回「ローカルファイルが無いReceiptPhotoData」
    ///   を再計算するだけなので、中断した地点から自然に再開できる。
    /// - CloudKit同期OFF中でも、ローカルのCloud Configurationストア自体は読めるため、
    ///   OFFのまま呼んでも問題ない（ONだった間に既に取り込まれていた分の取りこぼしを補える）。
    static func materializeAllMissingLocalFilesIfNeeded() {
        Task.detached(priority: .utility) {
            await materializeAllMissingLocalFiles()
        }
    }

    /// materializeAllMissingLocalFilesIfNeeded()の実体。internal公開の理由：
    /// @testable経由でTask.detachedの完了タイミングに依存せず、決定的に直接awaitして
    /// 検証できるようにするため（RemoteChangeObserver.processHistorySynchronously(context:)と同じ理由）。
    static func materializeAllMissingLocalFiles() async {
        let context = CoreDataStack.shared.container.newBackgroundContext()

        // まずidだけを軽量に取得し、ローカルファイルが既にあるものは除外する
        // （大量件数でもimageData本体を読み込まずに済むため、メモリ・I/O負荷を抑えられる）。
        let missingIds = await context.perform {
            ReceiptPhotoDataSync.fetchAllIds(context: context).filter { id in
                ReceiptImageHelper.loadData(id) == nil
            }
        }
        guard !missingIds.isEmpty else { return }

        // 本当に無いものだけ、1件ずつimageDataを読み込んで書き出す
        // （全件のimageDataを一度にメモリへ載せない）。
        for id in missingIds {
            let photo = await context.perform {
                ReceiptPhotoDataSync.fetch(id: id, context: context)
            }
            guard let photo else { continue }
            materialize(filename: photo.id, imageData: photo.imageData)
        }
    }

    /// 実際に新規ファイルを書き出した場合のみ、修正2（画面の自動更新）用の通知を発行する。
    /// SwiftUI/Combineの購読側が@Publishedを安全に更新できるよう、メインスレッドで発行する。
    private static func materialize(filename: String, imageData: Data) {
        guard ReceiptImageHelper.writeIfMissing(imageData, filename: filename) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: photoMaterializedNotification, object: nil, userInfo: ["filename": filename]
            )
        }
    }
}
