import CoreData

// MARK: - MonthlySnapshot: Core Dataリポジトリ（移行 Phase 1・Snapshot系）
//
// Core DataのCDMonthlySnapshotを唯一の永続化先とする。(yearMonth, bookId) の組が実質的な主キー。
// SnapshotManagerが差分更新・全期間再構築の際に直接CD型を操作するため、ここでは主に
// View側（CalendarMonthGridView等）が使う読み取り専用API（fetchAll/observer）を提供する。
enum MonthlySnapshotSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 読み取り
    //
    // AssetGraphCacheService.rebuildTotalAssetsCache(bookId:maxPoints:)のようなplain async関数を
    // awaitした直後は、呼び出し元がメインスレッドへ戻っている保証が無い（実測で非メインスレッド
    // 再開を確認済み）。そのすぐ後でここのfetchAllが呼ばれるケース（テスト等）があるため、
    // 呼び出し元のスレッドによらず常に正しく動くよう、context.performAndWaitで包んで自己完結させる。

    static func fetchAll(bookId: UUID) -> [MonthlySnapshot] {
        let ctx = context
        var result: [MonthlySnapshot] = []
        ctx.performAndWait {
            let request = CDMonthlySnapshot.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            result = (try? ctx.fetch(request)).map { $0.compactMap(map) } ?? []
        }
        return result
    }

    static func fetchAll() -> [MonthlySnapshot] {
        let ctx = context
        var result: [MonthlySnapshot] = []
        ctx.performAndWait {
            result = (try? ctx.fetch(CDMonthlySnapshot.fetchRequest())).map { $0.compactMap(map) } ?? []
        }
        return result
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDMonthlySnapshot, MonthlySnapshot> {
        let request = CDMonthlySnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "yearMonth", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    // MARK: - 削除

    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            let request = CDMonthlySnapshot.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            for existing in (try? ctx.fetch(request)) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDMonthlySnapshot.fetchRequest())) ?? -1
    }

    // MARK: - Helpers（SnapshotManagerからも使う変換ヘルパー）

    static func map(_ cd: CDMonthlySnapshot) -> MonthlySnapshot? {
        guard let yearMonth = cd.yearMonth, let updatedAt = cd.updatedAt else { return nil }
        var snapshot = MonthlySnapshot(
            yearMonth: yearMonth, bookId: cd.bookId ?? UUID(), year: Int(cd.year), month: Int(cd.month)
        )
        snapshot.bookId = cd.bookId
        snapshot.incomeTotal = Int(cd.incomeTotal)
        snapshot.expenseTotal = Int(cd.expenseTotal)
        snapshot.creditCardExpenseTotal = Int(cd.creditCardExpenseTotal)
        snapshot.transferFeeTotal = Int(cd.transferFeeTotal)
        snapshot.carryoverBalance = Int(cd.carryoverBalance)
        snapshot.rawCarryoverBalance = Int(cd.rawCarryoverBalance)
        snapshot.updatedAt = updatedAt
        return snapshot
    }
}
