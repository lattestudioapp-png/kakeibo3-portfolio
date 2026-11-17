import CoreData

// MARK: - RecurringTransferSettingData: Core Dataリポジトリ（移行 Phase 1・モデル11/13）
//
// Core DataのCDRecurringTransferSettingDataを唯一の永続化先とする。
// RecurringTransferSettingData(struct)はViews/ViewModels/Servicesが触るドメイン表現で、
// この enum が CDRecurringTransferSettingData との変換・CRUDを一手に引き受ける。
enum RecurringTransferSettingDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ setting: RecurringTransferSettingData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDRecurringTransferSettingData(context: ctx)
            apply(setting, to: cd)
        }
    }

    static func update(_ setting: RecurringTransferSettingData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: setting.id, context: ctx) else {
                let cd = CDRecurringTransferSettingData(context: ctx)
                apply(setting, to: cd)
                return
            }
            apply(setting, to: existing)
        }
    }

    static func delete(id: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [RecurringTransferSettingData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [RecurringTransferSettingData] {
        (try? context.fetch(CDRecurringTransferSettingData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> RecurringTransferSettingData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDRecurringTransferSettingData, RecurringTransferSettingData> {
        let request = CDRecurringTransferSettingData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    static func fetch(matching predicate: NSPredicate) -> [RecurringTransferSettingData] {
        let request = CDRecurringTransferSettingData.fetchRequest()
        request.predicate = predicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDRecurringTransferSettingDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDRecurringTransferSettingDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDRecurringTransferSettingData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDRecurringTransferSettingData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ setting: RecurringTransferSettingData, to cd: CDRecurringTransferSettingData) {
        cd.id = setting.id
        cd.fromMethodId = setting.fromMethodId
        cd.fromMethodName = setting.fromMethodName
        cd.fromType = setting.fromType
        cd.toMethodId = setting.toMethodId
        cd.toMethodName = setting.toMethodName
        cd.toType = setting.toType
        cd.amount = Int64(setting.amount)
        cd.day = Int64(setting.day)
        cd.startDate = setting.startDate
        cd.isActive = setting.isActive
        cd.createdAt = setting.createdAt
        cd.updatedAt = setting.updatedAt
        cd.isLocked = setting.isLocked
        cd.isTestData = setting.isTestData
        cd.bookId = setting.bookId
        cd.holidayAdjustment = setting.holidayAdjustment
        cd.generatedScheduleMonths = try? JSONEncoder().encode(setting.generatedScheduleMonths)
    }

    private static func map(_ cd: CDRecurringTransferSettingData) -> RecurringTransferSettingData? {
        guard let id = cd.id, let fromMethodId = cd.fromMethodId, let fromMethodName = cd.fromMethodName,
              let fromType = cd.fromType, let toMethodId = cd.toMethodId, let toMethodName = cd.toMethodName,
              let toType = cd.toType, let startDate = cd.startDate,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var setting = RecurringTransferSettingData(
            id: id, fromMethodId: fromMethodId, fromMethodName: fromMethodName, fromType: fromType,
            toMethodId: toMethodId, toMethodName: toMethodName, toType: toType,
            amount: Int(cd.amount), day: Int(cd.day), startDate: startDate,
            createdAt: createdAt, updatedAt: updatedAt
        )
        setting.isActive = cd.isActive
        setting.isLocked = cd.isLocked
        setting.isTestData = cd.isTestData
        setting.bookId = cd.bookId
        setting.holidayAdjustment = cd.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
        setting.generatedScheduleMonths = cd.generatedScheduleMonths
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return setting
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDRecurringTransferSettingData? {
        let request = CDRecurringTransferSettingData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDRecurringTransferSettingData] {
        let request = CDRecurringTransferSettingData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
