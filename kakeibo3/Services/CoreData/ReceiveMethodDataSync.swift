import CoreData

// MARK: - ReceiveMethodData: Core Dataリポジトリ（移行 Phase 1・モデル5/13）
//
// Core DataのCDReceiveMethodDataを唯一の永続化先とする。ReceiveMethodData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDReceiveMethodData との
// 変換・CRUDを一手に引き受ける。
//
// ReceiveMethodDataは現在ではPaymentMethodSettingData(useForReceive=true)へ統合済みで、
// 現行UIの編集画面（OtherReceiveMethodEditView）は到達不能なデッドコードのため未対応。
// 生きている呼び出し箇所は「新規帳簿作成時の現金デフォルト作成」「バックアップ復元」
// 「帳簿リセット時の全削除」の3箇所のみ。
enum ReceiveMethodDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ method: ReceiveMethodData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDReceiveMethodData(context: ctx)
            apply(method, to: cd)
        }
    }

    static func update(_ method: ReceiveMethodData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: method.id, context: ctx) else {
                let cd = CDReceiveMethodData(context: ctx)
                apply(method, to: cd)
                return
            }
            apply(method, to: existing)
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

    static func insertAsync(_ method: ReceiveMethodData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDReceiveMethodData(context: ctx)
            apply(method, to: cd)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [ReceiveMethodData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [ReceiveMethodData] {
        (try? context.fetch(CDReceiveMethodData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> ReceiveMethodData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDReceiveMethodData, ReceiveMethodData> {
        let request = CDReceiveMethodData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDReceiveMethodDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDReceiveMethodDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDReceiveMethodData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDReceiveMethodData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ method: ReceiveMethodData, to cd: CDReceiveMethodData) {
        cd.id = method.id
        cd.methodName = method.methodName
        cd.isActive = method.isActive
        cd.sortOrder = Int64(method.sortOrder)
        cd.createdAt = method.createdAt
        cd.bookId = method.bookId
    }

    private static func map(_ cd: CDReceiveMethodData) -> ReceiveMethodData? {
        guard let id = cd.id, let methodName = cd.methodName, let createdAt = cd.createdAt else { return nil }
        var method = ReceiveMethodData(
            id: id, methodName: methodName, isActive: cd.isActive,
            sortOrder: Int(cd.sortOrder), createdAt: createdAt
        )
        method.bookId = cd.bookId
        return method
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDReceiveMethodData? {
        let request = CDReceiveMethodData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDReceiveMethodData] {
        let request = CDReceiveMethodData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
