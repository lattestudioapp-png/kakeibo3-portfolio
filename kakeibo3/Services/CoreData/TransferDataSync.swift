import CoreData

// MARK: - TransferData: Core Dataリポジトリ（移行 Phase 1・モデル8/13）
//
// Core DataのCDTransferDataを唯一の永続化先とする。TransferData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDTransferData との
// 変換・CRUDを一手に引き受ける。
enum TransferDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ transfer: TransferData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDTransferData(context: ctx)
            apply(transfer, to: cd)
        }
    }

    static func update(_ transfer: TransferData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: transfer.id, context: ctx) else {
                let cd = CDTransferData(context: ctx)
                apply(transfer, to: cd)
                return
            }
            apply(transfer, to: existing)
        }
    }

    // MARK: - 書き込み（成功確認版。ExpenseDataSync.insertChecked/updateCheckedと同じ理由）

    @discardableResult
    static func insertChecked(_ transfer: TransferData) -> Bool {
        CoreDataStack.shared.performAndSaveChecked { ctx in
            let cd = CDTransferData(context: ctx)
            apply(transfer, to: cd)
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

    static func insertAsync(_ transfer: TransferData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDTransferData(context: ctx)
            apply(transfer, to: cd)
        }
    }

    // MARK: - 読み取り
    //
    // fetchAll/fetch(matching:)/observerは全て「ゴミ箱内は除外」がデフォルト（isInTrash == NO を
    // 必ずAND条件に含める）。ゴミ箱画面だけはfetchTrashed(bookId:)という別の明示的なメソッドを使う。

    private static let excludeTrashPredicate = NSPredicate(format: "isInTrash == NO")

    static func fetchAll(bookId: UUID) -> [TransferData] {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
        ])
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetchAll() -> [TransferData] {
        let request = CDTransferData.fetchRequest()
        request.predicate = excludeTrashPredicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> TransferData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDTransferData, TransferData> {
        let request = CDTransferData.fetchRequest()
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

    /// 任意の絞り込み条件（例：月次の日付範囲＋帳簿）で観測する。
    static func observer(matching predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]? = nil) -> CoreDataListObserver<CDTransferData, TransferData> {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeTrashPredicate])
        request.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "date", ascending: false)]
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    static func fetch(matching predicate: NSPredicate) -> [TransferData] {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeTrashPredicate])
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// ゴミ箱画面専用：指定した帳簿の「ゴミ箱に入っている」ぶんだけを取得する。
    static func fetchTrashed(bookId: UUID) -> [TransferData] {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@ AND isInTrash == YES", bookId as CVarArg)
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDTransferDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDTransferDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDTransferData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDTransferData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ transfer: TransferData, to cd: CDTransferData) {
        cd.id = transfer.id
        cd.date = transfer.date
        cd.fromType = transfer.fromType
        cd.fromId = transfer.fromId
        cd.fromName = transfer.fromName
        cd.toType = transfer.toType
        cd.toId = transfer.toId
        cd.toName = transfer.toName
        cd.amount = Int64(transfer.amount)
        cd.feeAmount = Int64(transfer.feeAmount)
        cd.memo = transfer.memo
        cd.receiptImagePath = transfer.receiptImagePath
        cd.createdAt = transfer.createdAt
        cd.updatedAt = transfer.updatedAt
        cd.isTestData = transfer.isTestData
        cd.recurringTransferSettingId = transfer.recurringTransferSettingId
        cd.bookId = transfer.bookId
        cd.isInTrash = transfer.isInTrash
        cd.trashedAt = transfer.trashedAt
    }

    private static func map(_ cd: CDTransferData) -> TransferData? {
        guard let id = cd.id, let fromType = cd.fromType, let fromName = cd.fromName,
              let toType = cd.toType, let toName = cd.toName, let memo = cd.memo,
              let date = cd.date, let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var transfer = TransferData(
            id: id, date: date, fromType: fromType, fromId: cd.fromId, fromName: fromName,
            toType: toType, toId: cd.toId, toName: toName, amount: Int(cd.amount),
            feeAmount: Int(cd.feeAmount), memo: memo, receiptImagePath: cd.receiptImagePath,
            createdAt: createdAt, updatedAt: updatedAt
        )
        transfer.isTestData = cd.isTestData
        transfer.recurringTransferSettingId = cd.recurringTransferSettingId
        transfer.bookId = cd.bookId
        transfer.isInTrash = cd.isInTrash
        transfer.trashedAt = cd.trashedAt
        return transfer
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDTransferData? {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDTransferData] {
        let request = CDTransferData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
