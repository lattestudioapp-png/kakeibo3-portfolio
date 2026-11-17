import CoreData

// MARK: - ExpenseData: Core Dataリポジトリ（移行 Phase 1・モデル6/13）
//
// Core DataのCDExpenseDataを唯一の永続化先とする。ExpenseData(struct)は
// Views/ViewModels/Servicesが触るドメイン表現で、この enum が CDExpenseData との
// 変換・CRUDを一手に引き受ける。
enum ExpenseDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ expense: ExpenseData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDExpenseData(context: ctx)
            apply(expense, to: cd)
        }
    }

    static func update(_ expense: ExpenseData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: expense.id, context: ctx) else {
                let cd = CDExpenseData(context: ctx)
                apply(expense, to: cd)
                return
            }
            apply(expense, to: existing)
        }
    }

    // MARK: - 書き込み（成功確認版）
    //
    // 支出の新規保存/編集のように「保存が成功したとUIに表示する前に、本当に永続化できたか」を
    // 呼び出し元(TransactionRepository)が確認したい場面向け。既存のinsert/update(戻り値無し)は
    // 他の多数の呼び出し元との互換のためそのまま残す。

    @discardableResult
    static func insertChecked(_ expense: ExpenseData) -> Bool {
        CoreDataStack.shared.performAndSaveChecked { ctx in
            let cd = CDExpenseData(context: ctx)
            apply(expense, to: cd)
        }
    }

    @discardableResult
    static func updateChecked(_ expense: ExpenseData) -> Bool {
        CoreDataStack.shared.performAndSaveChecked { ctx in
            guard let existing = fetchOne(id: expense.id, context: ctx) else {
                let cd = CDExpenseData(context: ctx)
                apply(expense, to: cd)
                return
            }
            apply(expense, to: existing)
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

    static func insertAsync(_ expense: ExpenseData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDExpenseData(context: ctx)
            apply(expense, to: cd)
        }
    }

    // MARK: - 読み取り
    //
    // fetchAll/fetch(matching:)/observerは全て「ゴミ箱内は除外」がデフォルト（isInTrash == NO を
    // 必ずAND条件に含める）。通常一覧・カレンダー・分析・予算集計はこの経路だけを使うため、
    // 呼び出し側を1つずつ直す必要がなく、ここ1箇所で除外が効く。ゴミ箱画面だけはfetchTrashed(bookId:)
    // という別の明示的なメソッドを使う。

    private static let excludeTrashPredicate = NSPredicate(format: "isInTrash == NO")

    static func fetchAll(bookId: UUID) -> [ExpenseData] {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "bookId == %@", bookId as CVarArg), excludeTrashPredicate,
        ])
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetchAll() -> [ExpenseData] {
        let request = CDExpenseData.fetchRequest()
        request.predicate = excludeTrashPredicate
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> ExpenseData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func fetch(matching predicate: NSPredicate) -> [ExpenseData] {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeTrashPredicate])
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDExpenseData, ExpenseData> {
        let request = CDExpenseData.fetchRequest()
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
    static func observer(matching predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]? = nil) -> CoreDataListObserver<CDExpenseData, ExpenseData> {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeTrashPredicate])
        request.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "date", ascending: false)]
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// ゴミ箱画面専用：指定した帳簿の「ゴミ箱に入っている」ぶんだけを取得する。
    static func fetchTrashed(bookId: UUID) -> [ExpenseData] {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@ AND isInTrash == YES", bookId as CVarArg)
        return (try? context.fetch(request)).map { $0.compactMap(map) } ?? []
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDExpenseDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDExpenseDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDExpenseData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDExpenseData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ expense: ExpenseData, to cd: CDExpenseData) {
        cd.id = expense.id
        cd.amount = Int64(expense.amount)
        cd.date = expense.date
        cd.paymentMethod = expense.paymentMethod
        cd.category = expense.category
        cd.memo = expense.memo
        cd.createdAt = expense.createdAt
        cd.bookId = expense.bookId
        cd.bankAccountId = expense.bankAccountId
        cd.fixedExpenseId = expense.fixedExpenseId
        cd.receiptImagePath = expense.receiptImagePath
        cd.isTestData = expense.isTestData
        cd.isInTrash = expense.isInTrash
        cd.trashedAt = expense.trashedAt
    }

    private static func map(_ cd: CDExpenseData) -> ExpenseData? {
        guard let id = cd.id, let paymentMethod = cd.paymentMethod, let category = cd.category,
              let memo = cd.memo, let date = cd.date, let createdAt = cd.createdAt else { return nil }
        var expense = ExpenseData(
            id: id, amount: Int(cd.amount), date: date, paymentMethod: paymentMethod,
            category: category, memo: memo, bankAccountId: cd.bankAccountId, createdAt: createdAt
        )
        expense.bookId = cd.bookId
        expense.fixedExpenseId = cd.fixedExpenseId
        expense.receiptImagePath = cd.receiptImagePath
        expense.isTestData = cd.isTestData
        expense.isInTrash = cd.isInTrash
        expense.trashedAt = cd.trashedAt
        return expense
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDExpenseData? {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDExpenseData] {
        let request = CDExpenseData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }
}
