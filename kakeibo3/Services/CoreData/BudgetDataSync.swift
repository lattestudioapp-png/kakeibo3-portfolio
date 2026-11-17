import CoreData

// MARK: - BudgetData: Core Dataリポジトリ（移行 Phase 1）
//
// Core DataのCDBudgetDataを唯一の永続化先とする。BudgetData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDBudgetData との
// 変換・CRUDを一手に引き受ける。
enum BudgetDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ budget: BudgetData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDBudgetData(context: ctx)
            apply(budget, to: cd)
        }
    }

    static func update(_ budget: BudgetData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: budget.id, context: ctx) else {
                let cd = CDBudgetData(context: ctx)
                apply(budget, to: cd)
                return
            }
            apply(budget, to: existing)
        }
    }

    static func delete(id: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [BudgetData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [BudgetData] {
        (try? context.fetch(CDBudgetData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> BudgetData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDBudgetData, BudgetData> {
        let request = CDBudgetData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    static func fetch(matching predicate: NSPredicate) -> [BudgetData] {
        let request = CDBudgetData.fetchRequest()
        request.predicate = predicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDBudgetDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDBudgetDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDBudgetData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDBudgetData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ budget: BudgetData, to cd: CDBudgetData) {
        cd.id = budget.id
        cd.year = Int64(budget.year)
        cd.month = Int64(budget.month)
        cd.categoryName = budget.categoryName
        cd.amount = Int64(budget.amount)
        cd.createdAt = budget.createdAt
        cd.updatedAt = budget.updatedAt
        cd.isTestData = budget.isTestData
        cd.bookId = budget.bookId
    }

    private static func map(_ cd: CDBudgetData) -> BudgetData? {
        guard let id = cd.id, let categoryName = cd.categoryName,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var budget = BudgetData(
            id: id, year: Int(cd.year), month: Int(cd.month), categoryName: categoryName,
            amount: Int(cd.amount), createdAt: createdAt, updatedAt: updatedAt
        )
        budget.isTestData = cd.isTestData
        budget.bookId = cd.bookId
        return budget
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDBudgetData? {
        let request = CDBudgetData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDBudgetData] {
        let request = CDBudgetData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
