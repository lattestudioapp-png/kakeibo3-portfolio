import CoreData

// MARK: - PaymentMethodSettingData: Core Dataリポジトリ（移行 Phase 1・モデル3/13）
//
// Core DataのCDPaymentMethodSettingDataを唯一の永続化先とする。PaymentMethodSettingData(struct)
// はViews/ViewModels/Servicesが触るドメイン表現で、この enum が CDPaymentMethodSettingData との
// 変換・CRUDを一手に引き受ける。
//
// このモデルには専用のRepositoryが無く、7つの*EditView（現金・電子マネー・暗号資産・
// 証券口座・その他・デビットカード・クレジットカード）＋複数のService層で直接
// 操作しているため、呼び出し箇所もそれぞれのファイルに個別にある。
enum PaymentMethodSettingDataSync {
    private static var context: NSManagedObjectContext {
        CoreDataStack.shared.container.viewContext
    }

    // MARK: - 書き込み

    static func insert(_ method: PaymentMethodSettingData) {
        CoreDataStack.shared.performAndSave { ctx in
            let cd = CDPaymentMethodSettingData(context: ctx)
            apply(method, to: cd)
        }
    }

    static func update(_ method: PaymentMethodSettingData) {
        CoreDataStack.shared.performAndSave { ctx in
            guard let existing = fetchOne(id: method.id, context: ctx) else {
                let cd = CDPaymentMethodSettingData(context: ctx)
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

    static func insertAsync(_ method: PaymentMethodSettingData) async throws {
        try await CoreDataStack.shared.performAndSave { ctx in
            let cd = CDPaymentMethodSettingData(context: ctx)
            apply(method, to: cd)
        }
    }

    // MARK: - 読み取り

    static func fetchAll(bookId: UUID) -> [PaymentMethodSettingData] {
        fetchAll(bookId: bookId, context: context).compactMap(map)
    }

    static func fetchAll() -> [PaymentMethodSettingData] {
        (try? context.fetch(CDPaymentMethodSettingData.fetchRequest())).map { $0.compactMap(map) } ?? []
    }

    static func fetch(id: UUID) -> PaymentMethodSettingData? {
        fetchOne(id: id, context: context).flatMap(map)
    }

    static func observer(bookId: UUID? = nil) -> CoreDataListObserver<CDPaymentMethodSettingData, PaymentMethodSettingData> {
        let request = CDPaymentMethodSettingData.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        if let bookId {
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        }
        return CoreDataListObserver(request: request, context: context, map: map)
    }

    /// 帳簿リセット・帳簿削除用：指定した帳簿ぶんのCDPaymentMethodSettingDataを全削除する。
    static func deleteAll(bookId: UUID) {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in fetchAll(bookId: bookId, context: ctx) {
                ctx.delete(existing)
            }
        }
    }

    /// バックアップ復元用：全帳簿ぶんのCDPaymentMethodSettingDataを削除する
    /// （挿入は復元ループ内でinsert(_:)を個別に呼ぶ想定）。
    static func deleteAll() {
        CoreDataStack.shared.performAndSave { ctx in
            for existing in (try? ctx.fetch(CDPaymentMethodSettingData.fetchRequest())) ?? [] {
                ctx.delete(existing)
            }
        }
    }

    // MARK: - 検証用

    static func count() -> Int {
        (try? context.count(for: CDPaymentMethodSettingData.fetchRequest())) ?? -1
    }

    // MARK: - Helpers

    private static func apply(_ method: PaymentMethodSettingData, to cd: CDPaymentMethodSettingData) {
        cd.id = method.id
        cd.methodName = method.methodName
        cd.type = method.type
        cd.closingDay = method.closingDay.map { NSNumber(value: $0) }
        cd.withdrawalDay = method.withdrawalDay.map { NSNumber(value: $0) }
        cd.adjustPaymentDateToNextBusinessDay = method.adjustPaymentDateToNextBusinessDay
        cd.bankAccount = method.bankAccount
        cd.withdrawalBankAccountId = method.withdrawalBankAccountId
        cd.memo = method.memo
        cd.createdAt = method.createdAt
        cd.updatedAt = method.updatedAt
        cd.sortOrder = Int64(method.sortOrder)
        cd.isActive = method.isActive
        cd.isAsset = method.isAsset
        cd.assetInitialBalance = method.assetInitialBalance.map { NSNumber(value: $0) }
        cd.includeInAnalysis = method.includeInAnalysis
        cd.assetInitialBalanceIncomeId = method.assetInitialBalanceIncomeId
        cd.assetInitialBalanceExpenseId = method.assetInitialBalanceExpenseId
        cd.showInInputPicker = method.showInInputPicker
        cd.useForReceive = method.useForReceive
        cd.showInAnalysis = method.showInAnalysis
        cd.recurringTransferSettingId = method.recurringTransferSettingId
        cd.recurringTransferSettingIds = try? JSONEncoder().encode(method.recurringTransferSettingIds)
        cd.isTestData = method.isTestData
        cd.isLocked = method.isLocked
        cd.bookId = method.bookId
        cd.colorHex = method.colorHex
        cd.holidayAdjustment = method.holidayAdjustment
    }

    private static func map(_ cd: CDPaymentMethodSettingData) -> PaymentMethodSettingData? {
        guard let id = cd.id, let methodName = cd.methodName, let type = cd.type,
              let createdAt = cd.createdAt, let updatedAt = cd.updatedAt else { return nil }
        var method = PaymentMethodSettingData(
            id: id, methodName: methodName, type: type,
            closingDay: cd.closingDay?.intValue, withdrawalDay: cd.withdrawalDay?.intValue,
            adjustPaymentDateToNextBusinessDay: cd.adjustPaymentDateToNextBusinessDay,
            bankAccount: cd.bankAccount, withdrawalBankAccountId: cd.withdrawalBankAccountId,
            createdAt: createdAt, updatedAt: updatedAt, sortOrder: Int(cd.sortOrder)
        )
        method.memo = cd.memo
        method.isActive = cd.isActive
        method.isAsset = cd.isAsset
        method.assetInitialBalance = cd.assetInitialBalance?.doubleValue
        method.includeInAnalysis = cd.includeInAnalysis
        method.assetInitialBalanceIncomeId = cd.assetInitialBalanceIncomeId
        method.assetInitialBalanceExpenseId = cd.assetInitialBalanceExpenseId
        method.showInInputPicker = cd.showInInputPicker
        method.useForReceive = cd.useForReceive
        method.showInAnalysis = cd.showInAnalysis
        method.recurringTransferSettingId = cd.recurringTransferSettingId
        method.recurringTransferSettingIds = cd.recurringTransferSettingIds
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        method.isTestData = cd.isTestData
        method.isLocked = cd.isLocked
        method.bookId = cd.bookId
        method.colorHex = cd.colorHex
        method.holidayAdjustment = cd.holidayAdjustment
        return method
    }

    private static func fetchOne(id: UUID, context ctx: NSManagedObjectContext) -> CDPaymentMethodSettingData? {
        let request = CDPaymentMethodSettingData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private static func fetchAll(bookId: UUID, context ctx: NSManagedObjectContext) -> [CDPaymentMethodSettingData] {
        let request = CDPaymentMethodSettingData.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        return (try? ctx.fetch(request)) ?? []
    }

}
