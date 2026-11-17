import CoreData
import Foundation

// MARK: - ReceiptPhotoData: レシート写真のCloudKit同期用Core Dataリポジトリ
//
// CDReceiptPhotoDataを唯一の永続化先とする。idはReceiptImageHelperが発行するファイル名
// （UUIDベース、グローバルに一意）そのものを使うため、他の*DataSyncのような
// 「insert/update」の区別を持たず、常に「存在しなければ挿入する」(insertIfMissing)のみを
// 提供する（同じファイル名に対して複数回呼んでも安全＝重複を作らない設計）。

enum ReceiptPhotoTransactionType: String {
    case expense
    case income
    case transfer
}

struct ReceiptPhotoData {
    var id: String
    var transactionType: ReceiptPhotoTransactionType
    var transactionId: UUID
    var bookId: UUID
    var sortOrder: Int
    var imageData: Data
    var createdAt: Date
}

enum ReceiptPhotoDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    /// idが既に存在する場合は何もしない（重複を作らない。再実行安全）。
    static func insertIfMissing(_ photo: ReceiptPhotoData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard fetchOne(id: photo.id, context: ctx) == nil else { return }
            let cd = CDReceiptPhotoData(context: ctx)
            apply(photo, to: cd)
        }
    }

    static func delete(id: String) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    static func deleteAll(ids: [String]) {
        guard !ids.isEmpty else { return }
        CoreDataStack.shared.performAndSave { ctx in
            for id in ids {
                guard let existing = fetchOne(id: id, context: ctx) else { continue }
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 読み取り

    static func exists(id: String) -> Bool {
        fetchOne(id: id, context: context) != nil
    }

    static func fetch(id: String) -> ReceiptPhotoData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func fetchAll(transactionId: UUID) -> [ReceiptPhotoData] {
        let request = CDReceiptPhotoData.fetchRequest()
        request.predicate = NSPredicate(format: "transactionId == %@", transactionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    // MARK: - ダウンロード方向の安全網用（contextを明示指定できる版）
    //
    // ReceiptPhotoSyncService.materializeAllMissingLocalFilesIfNeeded()専用。バックグラウンド
    // contextから呼ぶため、viewContext固定のcontext計算プロパティを経由しない版を用意する。

    /// idのみを軽量に取得する（imageData本体はfault状態のまま触れないため読み込まれない。
    /// 大量件数でもメモリ効率が良い）。
    //
    // 注：resultType = .dictionaryResultTypeは`NSArray element failed to match the Swift
    // Array Element type`という実行時クラッシュを起こしたため使わない（[NSDictionary]から
    // [[String: Any]]への一括キャストがSwift/ObjC境界で安全にブリッジできないケースがある）。
    // 通常のmanagedObjectResultType（既定値）でidだけ触れば、imageDataはfaultのまま
    // ロードされず、同じ目的を安全に達成できる。
    static func fetchAllIds(context ctx: NSManagedObjectContext) -> [String] {
        let request = CDReceiptPhotoData.fetchRequest()
        guard let rows = try? ctx.fetch(request) else { return [] }
        return rows.compactMap(\.id)
    }

    static func fetch(id: String, context ctx: NSManagedObjectContext) -> ReceiptPhotoData? {
        fetchOne(id: id, context: ctx).flatMap(map)
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDReceiptPhotoData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ photo: ReceiptPhotoData, to cd: CDReceiptPhotoData) {
        cd.id = photo.id
        cd.transactionType = photo.transactionType.rawValue
        cd.transactionId = photo.transactionId
        cd.bookId = photo.bookId
        cd.sortOrder = Int64(photo.sortOrder)
        cd.imageData = photo.imageData
        cd.createdAt = photo.createdAt
    }

    private static func map(_ cd: CDReceiptPhotoData) -> ReceiptPhotoData? {
        guard let id = cd.id,
              let transactionTypeRaw = cd.transactionType,
              let transactionType = ReceiptPhotoTransactionType(rawValue: transactionTypeRaw),
              let transactionId = cd.transactionId,
              let bookId = cd.bookId,
              let imageData = cd.imageData,
              let createdAt = cd.createdAt
        else { return nil }
        return ReceiptPhotoData(
            id: id,
            transactionType: transactionType,
            transactionId: transactionId,
            bookId: bookId,
            sortOrder: Int(cd.sortOrder),
            imageData: imageData,
            createdAt: createdAt
        )
    }

    private static func fetchOne(id: String, context ctx: NSManagedObjectContext) -> CDReceiptPhotoData? {
        let request = CDReceiptPhotoData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }
}
