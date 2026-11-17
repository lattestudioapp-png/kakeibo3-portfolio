import CoreData

// MARK: - BookData（帳簿）: Core Dataリポジトリ（移行 Phase 1・モデル1/8）
//
// Core DataのCDBookDataを唯一の永続化先とする。BookData(struct)はViews/ViewModels/Services
// が触るドメイン表現で、この enum が CDBookData との変換・CRUD を一手に引き受ける。
enum BookDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ book: BookData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDBookData(context: ctx)
            apply(book, to: cd)
        }
    }

    static func update(_ book: BookData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: book.id, context: ctx) else {
                let cd = CDBookData(context: ctx)
                apply(book, to: cd)
                return
            }
            apply(book, to: existing)
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

    static func insertAsync(_ book: BookData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDBookData(context: ctx)
            apply(book, to: cd)
        }
    }

    /// バックアップ復元用：既存のCDBookDataを全削除してからbackupの内容で作り直す。
    static func replaceAll(with items: [BookBackupItem]) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(context: ctx) {
                ctx.delete(existing)
            }
            for item in items {
                let cd = CDBookData(context: ctx)
                cd.id = item.id
                cd.name = item.name
                cd.createdAt = item.createdAt
                cd.sortOrder = Int64(item.sortOrder)
                cd.isArchived = item.isArchived
                cd.isMain = item.isMain
            }
        }
    }

    // MARK: - 読み取り

    static func fetchAll() -> [BookData] {
        let request = CDBookData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return ((try? context.fetch(request)) ?? []).compactMap(map)
    }

    static func fetch(id: UUID) -> BookData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer() -> CoreDataListObserver<CDBookData, BookData> {
        let request = CDBookData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDBookData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ book: BookData, to cd: CDBookData) {
        cd.id = book.id
        cd.name = book.name
        cd.createdAt = book.createdAt
        cd.sortOrder = Int64(book.sortOrder)
        cd.isArchived = book.isArchived
        cd.isMain = book.isMain
    }

    private static func map(_ cd: CDBookData) -> BookData? {
        guard let id = cd.id, let name = cd.name, let createdAt = cd.createdAt else { return nil }
        return BookData(
            id: id, name: name, createdAt: createdAt,
            sortOrder: Int(cd.sortOrder), isArchived: cd.isArchived, isMain: cd.isMain
        )
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDBookData? {
        let request = CDBookData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(context ctx: NSManagedObjectContext) -> [CDBookData] {
        (try? ctx.fetch(CDBookData.fetchRequest())) ?? []
    }
}
