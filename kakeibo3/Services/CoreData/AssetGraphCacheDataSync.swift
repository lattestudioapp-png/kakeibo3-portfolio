import CoreData

// MARK: - AssetGraphCacheData: Core Dataリポジトリ（移行 Phase 1・Snapshot系）
//
// Core DataのCDAssetGraphCacheDataを唯一の永続化先とする。id（"totalAssets_<bookId>"）が主キー。
// pointsはCore Data上ではBinary属性のため、JSONEncoder/Decoderで[AssetGraphCachePoint] ⇔ Data を変換する。
enum AssetGraphCacheDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func upsert(_ cache: AssetGraphCacheData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = fetchOne(id: cache.id, context: ctx) ?? CDAssetGraphCacheData(context: ctx)
            apply(cache, to: cd)
        }
    }

    static func delete(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: AssetGraphCacheData.cacheId(for: bookId), context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    /// 帳簿削除用：bookIdがnilの古いキャッシュ行も含めて、対象帳簿ぶんを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            let request = CDAssetGraphCacheData.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            for existing in (try? ctx.fetch(request)) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    /// マイグレーション用：bookIdがnilの古いキャッシュ行を全削除する。
    static func deleteAllWithNilBookId() {
        CoreDataStack.shared.performAndSave { ctx in
            let request = CDAssetGraphCacheData.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == nil")
            for existing in (try? ctx.fetch(request)) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 読み取り
    //
    // AssetGraphCacheService.rebuildTotalAssetsCache(bookId:maxPoints:)はasync関数で、
    // 内部でTask.detachedを使うため、呼び出し元がawaitから戻った直後に必ずしもメインスレッドへ
    // 戻っているとは限らない（plain asyncはスレッド親和性を保証しない）。以前はここが
    // 「メインスレッドから同期で呼ばれる」という前提のままcontext.fetchを直接呼んでおり、
    // 非メインスレッドから呼ばれた場合にviewContextのスレッド閉じ込め契約に違反し、
    // Core Data内部（NSSet相当の登録オブジェクト管理）を壊してtestAssetGraphCacheRebuildsSuccessfully
    // が低確率でNSInvalidArgumentException（-[__NSCFSet addObject:]: attempt to insert nil）で
    // クラッシュする原因になっていた。呼び出し元のスレッドによらず常に正しく動くよう、
    // context.performAndWaitで包んで自己完結させる。

    static func fetch(bookId: UUID) -> AssetGraphCacheData? {
        let ctx = context
        var result: AssetGraphCacheData?
        ctx.performAndWait {
            result = fetchOne(id: AssetGraphCacheData.cacheId(for: bookId), context: ctx).flatMap(map)
        }
        return result
    }

    static func fetchAll() -> [AssetGraphCacheData] {
        let ctx = context
        var result: [AssetGraphCacheData] = []
        ctx.performAndWait {
            result = (try? ctx.fetch(CDAssetGraphCacheData.fetchRequest())).map { $0.compactMap(map) } ?? []
        }
        return result
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDAssetGraphCacheData, AssetGraphCacheData> {
        let request = CDAssetGraphCacheData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    // MARK: - Helpers

    private static func apply(_ cache: AssetGraphCacheData, to cd: CDAssetGraphCacheData) {
        cd.id = cache.id
        cd.bookId = cache.bookId
        cd.updatedAt = cache.updatedAt
        cd.maxPointsUsed = Int64(cache.maxPointsUsed)
        cd.granularityUsed = cache.granularityUsed
        cd.firstDate = cache.firstDate
        cd.lastDate = cache.lastDate
        cd.points = try? JSONEncoder().encode(cache.points)
    }

    private static func map(_ cd: CDAssetGraphCacheData) -> AssetGraphCacheData? {
        guard let id = cd.id, let bookId = cd.bookId, let updatedAt = cd.updatedAt,
              let granularityUsed = cd.granularityUsed, let firstDate = cd.firstDate, let lastDate = cd.lastDate else { return nil }
        let points: [AssetGraphCachePoint] = cd.points.flatMap { try? JSONDecoder().decode([AssetGraphCachePoint].self, from: $0) } ?? []
        var cache = AssetGraphCacheData(
            bookId: bookId, updatedAt: updatedAt, maxPointsUsed: Int(cd.maxPointsUsed),
            granularityUsed: granularityUsed, firstDate: firstDate, lastDate: lastDate, points: points
        )
        cache.id = id
        return cache
    }

    private static func fetchOne(id: String, context ctx: NSManagedObjectContext) -> CDAssetGraphCacheData? {
        let request = CDAssetGraphCacheData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }
}
