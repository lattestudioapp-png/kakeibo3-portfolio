import CoreData

// MARK: - BankAccountData: Core Dataリポジトリ（移行 Phase 1・モデル4/13）
//
// Core DataのCDBankAccountDataを唯一の永続化先とする。BankAccountData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDBankAccountData との
// 変換・CRUDを一手に引き受ける。
enum BankAccountDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ account: BankAccountData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDBankAccountData(context: ctx)
            apply(account, to: cd)
        }
    }

    static func update(_ account: BankAccountData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: account.id, context: ctx) else {
                let cd = CDBankAccountData(context: ctx)
                apply(account, to: cd)
                return
            }
            apply(account, to: existing)
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

    static func insertAsync(_ account: BankAccountData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDBankAccountData(context: ctx)
            apply(account, to: cd)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [BankAccountData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [BankAccountData] {
        (try? context.fetch(CDBankAccountData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> BankAccountData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDBankAccountData, BankAccountData> {
        let request = CDBankAccountData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDBankAccountDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDBankAccountDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDBankAccountData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDBankAccountData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ account: BankAccountData, to cd: CDBankAccountData) {
        cd.id = account.id
        cd.accountName = account.accountName
        cd.initialBalance = account.initialBalance.map { NSNumber(value: $0) }
        cd.memo = account.memo
        cd.isActive = account.isActive
        cd.sortOrder = Int64(account.sortOrder)
        cd.createdAt = account.createdAt
        cd.updatedAt = account.updatedAt
        cd.initialBalanceIncomeId = account.initialBalanceIncomeId
        cd.showAsPaymentMethod = account.showAsPaymentMethod
        cd.showAsReceiveMethod = account.showAsReceiveMethod
        cd.showInAnalysis = account.showInAnalysis
        cd.isAsset = account.isAsset
        cd.recurringTransferSettingId = account.recurringTransferSettingId
        cd.recurringTransferSettingIds = try? JSONEncoder().encode(account.recurringTransferSettingIds)
        cd.isTestData = account.isTestData
        cd.isLocked = account.isLocked
        cd.bookId = account.bookId
        cd.colorHex = account.colorHex
    }

    private static func map(_ cd: CDBankAccountData) -> BankAccountData? {
        guard let id = cd.id, let accountName = cd.accountName,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var account = BankAccountData(
            id: id, accountName: accountName,
            initialBalance: cd.initialBalance?.doubleValue,
            memo: cd.memo, isActive: cd.isActive, sortOrder: Int(cd.sortOrder),
            createdAt: createdAt, updatedAt: updatedAt
        )
        account.initialBalanceIncomeId = cd.initialBalanceIncomeId
        account.showAsPaymentMethod = cd.showAsPaymentMethod
        account.showAsReceiveMethod = cd.showAsReceiveMethod
        account.showInAnalysis = cd.showInAnalysis
        account.isAsset = cd.isAsset
        account.recurringTransferSettingId = cd.recurringTransferSettingId
        account.recurringTransferSettingIds = cd.recurringTransferSettingIds
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        account.isTestData = cd.isTestData
        account.isLocked = cd.isLocked
        account.bookId = cd.bookId
        account.colorHex = cd.colorHex
        return account
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDBankAccountData? {
        let request = CDBankAccountData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDBankAccountData] {
        let request = CDBankAccountData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
