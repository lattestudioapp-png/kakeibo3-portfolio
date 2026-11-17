import CoreData

// MARK: - AnalysisMonthlySnapshot: Core Dataリポジトリ（移行 Phase 1・Snapshot系）
//
// Core DataのCDAnalysisMonthlySnapshotを唯一の永続化先とする。(yearMonth, bookId) の組が
// 実質的な主キー。カテゴリー別/方法別内訳・日別配列はCore Data上ではBinary属性のため、
// JSONEncoder/Decoderで[AnalysisCategoryAmount]等 ⇔ Data を変換する。
// AnalysisSnapshotManagerが差分更新・全期間再構築の際に直接CD型を操作するため、
// ここでは主にView側（AnalysisView等）が使う読み取り専用API（fetchAll/observer）を提供する。
enum AnalysisMonthlySnapshotSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 読み取り
    //
    // AssetGraphCacheService.rebuildTotalAssetsCache(bookId:maxPoints:)のようなplain async関数を
    // awaitした直後は、呼び出し元がメインスレッドへ戻っている保証が無い（実測で非メインスレッド
    // 再開を確認済み）。そのすぐ後でここのfetchAllが呼ばれるケース（テスト等）があるため、
    // 呼び出し元のスレッドによらず常に正しく動くよう、context.performAndWaitで包んで自己完結させる。

    static func fetchAll(bookId: UUID) -> [AnalysisMonthlySnapshot] {
        let ctx = context
        var result: [AnalysisMonthlySnapshot] = []
        ctx.performAndWait {
            let request = CDAnalysisMonthlySnapshot.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            result = (try? ctx.fetch(request)).map { $0.compactMap(map) } ?? []
        }
        return result
    }

    static func fetchAll() -> [AnalysisMonthlySnapshot] {
        let ctx = context
        var result: [AnalysisMonthlySnapshot] = []
        ctx.performAndWait {
            result = (try? ctx.fetch(CDAnalysisMonthlySnapshot.fetchRequest())).map { $0.compactMap(map) } ?? []
        }
        return result
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDAnalysisMonthlySnapshot, AnalysisMonthlySnapshot> {
        let request = CDAnalysisMonthlySnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "yearMonth", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    // MARK: - 削除

    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            let request = CDAnalysisMonthlySnapshot.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            for existing in (try? ctx.fetch(request)) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDAnalysisMonthlySnapshot.fetchRequest())) ?? -1
    }

    // MARK: - Helpers（AnalysisSnapshotManagerからも使う変換ヘルパー・JSONエンコード/デコード）

    static func map(_ cd: CDAnalysisMonthlySnapshot) -> AnalysisMonthlySnapshot? {
        guard let yearMonth = cd.yearMonth, let updatedAt = cd.updatedAt else { return nil }
        var snapshot = AnalysisMonthlySnapshot(
            yearMonth: yearMonth, bookId: cd.bookId ?? UUID(), year: Int(cd.year), month: Int(cd.month)
        )
        snapshot.bookId = cd.bookId
        snapshot.incomeTotal = Int(cd.incomeTotal)
        snapshot.expenseTotal = Int(cd.expenseTotal)
        snapshot.creditCardExpenseTotal = Int(cd.creditCardExpenseTotal)
        snapshot.transferFeeTotal = Int(cd.transferFeeTotal)
        snapshot.carryoverBalance = Int(cd.carryoverBalance)
        snapshot.updatedAt = updatedAt
        snapshot.displayExpenseTotal = Int(cd.displayExpenseTotal)
        snapshot.displayIncomeTotal = Int(cd.displayIncomeTotal)
        snapshot.expenseCategoryTotals = decode(cd.expenseCategoryTotals)
        snapshot.incomeCategoryTotals = decode(cd.incomeCategoryTotals)
        snapshot.paymentMethodTotals = decode(cd.paymentMethodTotals)
        snapshot.receiveMethodTotals = decode(cd.receiveMethodTotals)
        snapshot.expenseTransactionCount = Int(cd.expenseTransactionCount)
        snapshot.incomeTransactionCount = Int(cd.incomeTransactionCount)
        snapshot.dailyExpenseTotals = decode(cd.dailyExpenseTotals)
        snapshot.dailyIncomeTotals = decode(cd.dailyIncomeTotals)
        snapshot.dailyCreditCardExpenseTotals = decode(cd.dailyCreditCardExpenseTotals)
        snapshot.dailyTransferFeeTotals = decode(cd.dailyTransferFeeTotals)
        return snapshot
    }

    static func decode<T: Decodable>(_ data: Data?) -> [T] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    static func encode<T: Encodable>(_ value: [T]) -> Data? {
        try? JSONEncoder().encode(value)
    }
}
