import CoreData

// MARK: - RecurringIncomeData: Core Dataリポジトリ（移行 Phase 1・モデル10/13）
//
// Core DataのCDRecurringIncomeDataを唯一の永続化先とする。RecurringIncomeData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDRecurringIncomeData との
// 変換・CRUDを一手に引き受ける。
enum RecurringIncomeDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ recurringIncome: RecurringIncomeData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDRecurringIncomeData(context: ctx)
            apply(recurringIncome, to: cd)
        }
    }

    static func update(_ recurringIncome: RecurringIncomeData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: recurringIncome.id, context: ctx) else {
                let cd = CDRecurringIncomeData(context: ctx)
                apply(recurringIncome, to: cd)
                return
            }
            apply(recurringIncome, to: existing)
        }
    }

    static func delete(id: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [RecurringIncomeData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [RecurringIncomeData] {
        (try? context.fetch(CDRecurringIncomeData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> RecurringIncomeData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDRecurringIncomeData, RecurringIncomeData> {
        let request = CDRecurringIncomeData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    static func fetch(matching predicate: NSPredicate) -> [RecurringIncomeData] {
        let request = CDRecurringIncomeData.fetchRequest()
        request.predicate = predicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDRecurringIncomeDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDRecurringIncomeDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDRecurringIncomeData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDRecurringIncomeData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ recurringIncome: RecurringIncomeData, to cd: CDRecurringIncomeData) {
        cd.id = recurringIncome.id
        cd.name = recurringIncome.name
        cd.amount = Int64(recurringIncome.amount)
        cd.categoryName = recurringIncome.categoryName
        cd.receiveMethodType = recurringIncome.receiveMethodType
        cd.receiveMethodId = recurringIncome.receiveMethodId
        cd.dayOfMonth = Int64(recurringIncome.dayOfMonth)
        cd.startDate = recurringIncome.startDate
        cd.memo = recurringIncome.memo
        cd.isActive = recurringIncome.isActive
        cd.createdAt = recurringIncome.createdAt
        cd.updatedAt = recurringIncome.updatedAt
        cd.isTestData = recurringIncome.isTestData
        cd.isLocked = recurringIncome.isLocked
        cd.bookId = recurringIncome.bookId
        cd.holidayAdjustment = recurringIncome.holidayAdjustment
        cd.generatedScheduleMonths = try? JSONEncoder().encode(recurringIncome.generatedScheduleMonths)
    }

    private static func map(_ cd: CDRecurringIncomeData) -> RecurringIncomeData? {
        guard let id = cd.id, let name = cd.name, let categoryName = cd.categoryName,
              let receiveMethodType = cd.receiveMethodType, let startDate = cd.startDate,
              let memo = cd.memo, let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var recurringIncome = RecurringIncomeData(
            id: id, name: name, amount: Int(cd.amount), categoryName: categoryName,
            receiveMethodType: receiveMethodType, receiveMethodId: cd.receiveMethodId,
            dayOfMonth: Int(cd.dayOfMonth), startDate: startDate, memo: memo,
            createdAt: createdAt, updatedAt: updatedAt
        )
        recurringIncome.isActive = cd.isActive
        recurringIncome.isTestData = cd.isTestData
        recurringIncome.isLocked = cd.isLocked
        recurringIncome.bookId = cd.bookId
        recurringIncome.holidayAdjustment = cd.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
        recurringIncome.generatedScheduleMonths = cd.generatedScheduleMonths
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return recurringIncome
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDRecurringIncomeData? {
        let request = CDRecurringIncomeData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDRecurringIncomeData] {
        let request = CDRecurringIncomeData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
