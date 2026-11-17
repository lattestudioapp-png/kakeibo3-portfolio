import CoreData

// MARK: - DailySnapshot: Core Dataリポジトリ（移行 Phase 1・Snapshot系）
//
// Core DataのCDDailySnapshotを唯一の永続化先とする。(date, bookId) の組が実質的な主キー
// （UUIDのidは持たない。SwiftData時代と同じ設計）。SnapshotManagerが差分更新・全期間再構築の
// 際に直接CD型を操作するため、ここでは主にView側（CalendarMonthGridView等）が使う
// 読み取り専用API（fetchAll/observer）を提供する。
enum DailySnapshotSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [DailySnapshot] {
        let request = CDDailySnapshot.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetchAll() -> [DailySnapshot] {
        (try? context.fetch(CDDailySnapshot.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDDailySnapshot, DailySnapshot> {
        let request = CDDailySnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    // MARK: - 削除

    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            let request = CDDailySnapshot.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            for existing in (try? ctx.fetch(request)) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDDailySnapshot.fetchRequest())) ?? -1
    }

    // MARK: - Helpers（SnapshotManagerからも使う変換ヘルパー）

    static func map(_ cd: CDDailySnapshot) -> DailySnapshot? {
        guard let date = cd.date, let updatedAt = cd.updatedAt else { return nil }
        var snapshot = DailySnapshot(date: date, bookId: cd.bookId ?? UUID())
        snapshot.bookId = cd.bookId
        snapshot.incomeTotal = Int(cd.incomeTotal)
        snapshot.expenseTotal = Int(cd.expenseTotal)
        snapshot.creditCardExpenseTotal = Int(cd.creditCardExpenseTotal)
        snapshot.transferFeeTotal = Int(cd.transferFeeTotal)
        snapshot.transactionCount = Int(cd.transactionCount)
        snapshot.updatedAt = updatedAt
        return snapshot
    }
}
