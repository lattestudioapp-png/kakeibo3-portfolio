import CoreData

// MARK: - FixedExpenseData: Core Dataリポジトリ（移行 Phase 1・モデル9/13）
//
// Core DataのCDFixedExpenseDataを唯一の永続化先とする。FixedExpenseData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDFixedExpenseData との
// 変換・CRUDを一手に引き受ける。
enum FixedExpenseDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ fixedExpense: FixedExpenseData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDFixedExpenseData(context: ctx)
            apply(fixedExpense, to: cd)
        }
    }

    static func update(_ fixedExpense: FixedExpenseData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: fixedExpense.id, context: ctx) else {
                let cd = CDFixedExpenseData(context: ctx)
                apply(fixedExpense, to: cd)
                return
            }
            apply(fixedExpense, to: existing)
        }
    }

    static func delete(id: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [FixedExpenseData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [FixedExpenseData] {
        (try? context.fetch(CDFixedExpenseData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> FixedExpenseData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDFixedExpenseData, FixedExpenseData> {
        let request = CDFixedExpenseData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    static func fetch(matching predicate: NSPredicate) -> [FixedExpenseData] {
        let request = CDFixedExpenseData.fetchRequest()
        request.predicate = predicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDFixedExpenseDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDFixedExpenseDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDFixedExpenseData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDFixedExpenseData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ fixedExpense: FixedExpenseData, to cd: CDFixedExpenseData) {
        cd.id = fixedExpense.id
        cd.name = fixedExpense.name
        cd.amount = Int64(fixedExpense.amount)
        cd.categoryName = fixedExpense.categoryName
        cd.paymentMethodType = fixedExpense.paymentMethodType
        cd.paymentMethodId = fixedExpense.paymentMethodId
        cd.dayOfMonth = Int64(fixedExpense.dayOfMonth)
        cd.startDate = fixedExpense.startDate
        cd.memo = fixedExpense.memo
        cd.isActive = fixedExpense.isActive
        cd.createdAt = fixedExpense.createdAt
        cd.updatedAt = fixedExpense.updatedAt
        cd.isTestData = fixedExpense.isTestData
        cd.isLocked = fixedExpense.isLocked
        cd.bookId = fixedExpense.bookId
        cd.holidayAdjustment = fixedExpense.holidayAdjustment
        cd.generatedScheduleMonths = try? JSONEncoder().encode(fixedExpense.generatedScheduleMonths)
    }

    private static func map(_ cd: CDFixedExpenseData) -> FixedExpenseData? {
        guard let id = cd.id, let name = cd.name, let categoryName = cd.categoryName,
              let paymentMethodType = cd.paymentMethodType, let startDate = cd.startDate,
              let memo = cd.memo, let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var fixedExpense = FixedExpenseData(
            id: id, name: name, amount: Int(cd.amount), categoryName: categoryName,
            paymentMethodType: paymentMethodType, paymentMethodId: cd.paymentMethodId,
            dayOfMonth: Int(cd.dayOfMonth), startDate: startDate, memo: memo,
            createdAt: createdAt, updatedAt: updatedAt
        )
        fixedExpense.isActive = cd.isActive
        fixedExpense.isTestData = cd.isTestData
        fixedExpense.isLocked = cd.isLocked
        fixedExpense.bookId = cd.bookId
        fixedExpense.holidayAdjustment = cd.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
        fixedExpense.generatedScheduleMonths = cd.generatedScheduleMonths
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return fixedExpense
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDFixedExpenseData? {
        let request = CDFixedExpenseData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDFixedExpenseData] {
        let request = CDFixedExpenseData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
