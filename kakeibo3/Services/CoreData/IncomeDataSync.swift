import CoreData

// MARK: - IncomeData: Core Dataリポジトリ（移行 Phase 1・モデル7/13）
//
// Core DataのCDIncomeDataを唯一の永続化先とする。IncomeData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDIncomeData との
// 変換・CRUDを一手に引き受ける。
enum IncomeDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ income: IncomeData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDIncomeData(context: ctx)
            apply(income, to: cd)
        }
    }

    static func update(_ income: IncomeData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: income.id, context: ctx) else {
                let cd = CDIncomeData(context: ctx)
                apply(income, to: cd)
                return
            }
            apply(income, to: existing)
        }
    }

    // MARK: - 書き込み（成功確認版。ExpenseDataSync.insertChecked/updateCheckedと同じ理由）

    @discardableResult
    static func insertChecked(_ income: IncomeData) -> Bool {
        CoreDataStack.shared.performAndSaveChecked { ctx in
            let cd = CDIncomeData(context: ctx)
            apply(income, to: cd)
        }
    }

    @discardableResult
    static func updateChecked(_ income: IncomeData) -> Bool {
        CoreDataStack.shared.performAndSaveChecked { ctx in
            guard let existing = fetchOne(id: income.id, context: ctx) else {
                let cd = CDIncomeData(context: ctx)
                apply(income, to: cd)
                return
            }
            apply(income, to: existing)
        }
    }

    static func delete(id: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: id, context: ctx) else { return }
            ctx.delete(existing)
        }
    }

    // MARK: - 書き込み（async文脈向け）
    //
    // Task/Task.detached等、既にasync文脈にいる呼び出し元向け。CoreDataStack.performAndSave(_:)
    // async throws -> Tを使うため、cooperativeスレッドプールを塞がずcontextの専用キュー上で
    // 安全に実行する（QARegressionTestFactoryの非同期版シード関数が使う）。

    static func insertAsync(_ income: IncomeData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDIncomeData(context: ctx)
            apply(income, to: cd)
        }
    }

    // MARK: - 読み取り
    //
    // fetchAll/fetch(matching:)/observerは全て「ゴミ箱内は除外」がデフォルト（isInTrash == NO を
    // 必ずAND条件に含める）。ゴミ箱画面だけはfetchTrashed(bookId:)という別の明示的なメソッドを使う。

    private static let excludeTrashPredicate = NSPredicate(format: "isInTrash == NO")

    static func fetchAll(bookId: UUID) -> [IncomeData] {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
        ])
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetchAll() -> [IncomeData] {
        let request = CDIncomeData.fetchRequest()
        request.predicate = excludeTrashPredicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> IncomeData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func fetch(matching predicate: NSPredicate) -> [IncomeData] {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeTrashPredicate])
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDIncomeData, IncomeData> {
        let request = CDIncomeData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        if let bookId {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
            ])
        } else {
            request.predicate = excludeTrashPredicate
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// 任意の絞り込み条件（例：月次の日付範囲＋帳簿）で観測する。大量データを全件読み込む
    /// のを避けたい画面（カレンダーの月次取引一覧など）向け。
    static func observer(matching predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]? = nil) -> CoreDataListObserver<CDIncomeData, IncomeData> {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeTrashPredicate])
        request.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "date", ascending: false)]
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// ゴミ箱画面専用：指定した帳簿の「ゴミ箱に入っている」ぶんだけを取得する。
    static func fetchTrashed(bookId: UUID) -> [IncomeData] {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@ AND isInTrash == YES", bookId as CVarArg)
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDIncomeDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDIncomeDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDIncomeData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDIncomeData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ income: IncomeData, to cd: CDIncomeData) {
        cd.id = income.id
        cd.amount = Int64(income.amount)
        cd.date = income.date
        cd.receiveMethod = income.receiveMethod
        cd.category = income.category
        cd.memo = income.memo
        cd.createdAt = income.createdAt
        cd.bookId = income.bookId
        cd.bankAccountId = income.bankAccountId
        cd.recurringIncomeId = income.recurringIncomeId
        cd.receiptImagePath = income.receiptImagePath
        cd.isTestData = income.isTestData
        cd.isInTrash = income.isInTrash
        cd.trashedAt = income.trashedAt
    }

    private static func map(_ cd: CDIncomeData) -> IncomeData? {
        guard let id = cd.id, let receiveMethod = cd.receiveMethod, let category = cd.category,
              let memo = cd.memo, let date = cd.date, let createdAt = cd.createdAt else { return nil }
        var income = IncomeData(
            id: id, amount: Int(cd.amount), date: date, receiveMethod: receiveMethod,
            category: category, memo: memo, bankAccountId: cd.bankAccountId, createdAt: createdAt
        )
        income.bookId = cd.bookId
        income.recurringIncomeId = cd.recurringIncomeId
        income.receiptImagePath = cd.receiptImagePath
        income.isTestData = cd.isTestData
        income.isInTrash = cd.isInTrash
        income.trashedAt = cd.trashedAt
        return income
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDIncomeData? {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDIncomeData] {
        let request = CDIncomeData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
