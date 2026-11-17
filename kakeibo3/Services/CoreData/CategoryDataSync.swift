import CoreData

// MARK: - CategoryData: Core Dataリポジトリ（移行 Phase 1・モデル2/13）
//
// Core DataのCDCategoryDataを唯一の永続化先とする。CategoryData(struct)はViews/ViewModels/
// Servicesが触るドメイン表現で、この enum が CDCategoryData との変換・CRUDを一手に引き受ける。
enum CategoryDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ category: CategoryData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDCategoryData(context: ctx)
            apply(category, to: cd)
        }
    }

    /// 永続化が実際に成功したかを呼び出し元へ返す版（ExpenseDataSync.insertCheckedと同じ理由）。
    @discardableResult
    static func insertChecked(_ category: CategoryData) -> Bool {
        CoreDataStack.shared.performAndSaveChecked { ctx in
            let cd = CDCategoryData(context: ctx)
            apply(category, to: cd)
        }
    }

    static func update(_ category: CategoryData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: category.id, context: ctx) else {
                let cd = CDCategoryData(context: ctx)
                apply(category, to: cd)
                return
            }
            apply(category, to: existing)
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

    static func insertAsync(_ category: CategoryData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDCategoryData(context: ctx)
            apply(category, to: cd)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [CategoryData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [CategoryData] {
        (try? context.fetch(CDCategoryData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> CategoryData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDCategoryData, CategoryData> {
        let request = CDCategoryData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDCategoryDataを全削除する
    /// （DataResetService.deleteAllDataが帳簿単位で家計簿データを一括削除するため）。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDCategoryDataを削除する
    /// （BackupManager.applyRestoreは全帳簿の既存データを一括削除してから復元データで
    /// 作り直すため。挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            let request = CDCategoryData.fetchRequest()
            for existing in (try? ctx.fetch(request)) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDCategoryData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ category: CategoryData, to cd: CDCategoryData) {
        cd.id = category.id
        cd.name = category.name
        cd.colorHex = category.colorHex
        cd.type = category.type
        cd.sortOrder = Int64(category.sortOrder)
        cd.createdAt = category.createdAt
        cd.isTestData = category.isTestData
        cd.bookId = category.bookId
        cd.isSuspended = category.isSuspended
        cd.isProtected = category.isProtected
    }

    private static func map(_ cd: CDCategoryData) -> CategoryData? {
        guard let id = cd.id, let name = cd.name, let colorHex = cd.colorHex,
              let type = cd.type, let createdAt = cd.createdAt else { return nil }
        var category = CategoryData(
            id: id, name: name, colorHex: colorHex, type: type,
            sortOrder: Int(cd.sortOrder), createdAt: createdAt
        )
        category.isTestData = cd.isTestData
        category.bookId = cd.bookId
        category.isSuspended = cd.isSuspended
        category.isProtected = cd.isProtected
        return category
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDCategoryData? {
        let request = CDCategoryData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDCategoryData] {
        let request = CDCategoryData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }

}
