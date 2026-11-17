import CoreData

// MARK: - RecurringBudgetData: Core Dataリポジトリ（移行 Phase 1）
//
// Core DataのCDRecurringBudgetDataを唯一の永続化先とする。RecurringBudgetData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDRecurringBudgetData との
// 変換・CRUDを一手に引き受ける。
enum RecurringBudgetDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ recurringBudget: RecurringBudgetData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDRecurringBudgetData(context: ctx)
            apply(recurringBudget, to: cd)
        }
    }

    static func update(_ recurringBudget: RecurringBudgetData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: recurringBudget.id, context: ctx) else {
                let cd = CDRecurringBudgetData(context: ctx)
                apply(recurringBudget, to: cd)
                return
            }
            apply(recurringBudget, to: existing)
        }
    }

    static func delete(id: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [RecurringBudgetData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [RecurringBudgetData] {
        (try? context.fetch(CDRecurringBudgetData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> RecurringBudgetData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDRecurringBudgetData, RecurringBudgetData> {
        let request = CDRecurringBudgetData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    static func fetch(matching predicate: NSPredicate) -> [RecurringBudgetData] {
        let request = CDRecurringBudgetData.fetchRequest()
        request.predicate = predicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDRecurringBudgetDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDRecurringBudgetDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDRecurringBudgetData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDRecurringBudgetData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ recurringBudget: RecurringBudgetData, to cd: CDRecurringBudgetData) {
        cd.id = recurringBudget.id
        cd.categoryName = recurringBudget.categoryName
        cd.amount = Int64(recurringBudget.amount)
        cd.isEnabled = recurringBudget.isEnabled
        cd.createdAt = recurringBudget.createdAt
        cd.updatedAt = recurringBudget.updatedAt
        cd.bookId = recurringBudget.bookId
    }

    private static func map(_ cd: CDRecurringBudgetData) -> RecurringBudgetData? {
        guard let id = cd.id, let categoryName = cd.categoryName,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var recurringBudget = RecurringBudgetData(
            id: id, categoryName: categoryName, amount: Int(cd.amount), isEnabled: cd.isEnabled,
            createdAt: createdAt, updatedAt: updatedAt
        )
        recurringBudget.bookId = cd.bookId
        return recurringBudget
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDRecurringBudgetData? {
        let request = CDRecurringBudgetData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDRecurringBudgetData] {
        let request = CDRecurringBudgetData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
