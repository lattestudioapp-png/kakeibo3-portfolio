import Foundation

// MARK: - UUID辞書による参照検証(第2段階)
//
// 第1段階(LegacySnapshotの各配列そのもの)を「そのIDが実在する」プールとして扱い、
// 各EntityのUUID型FKフィールドをそのプールに対して検証する。名前による突合は
// 一切行わない(同名カテゴリー・同名支払い方法が複数帳簿で混線しないようにするため)。
//
// bookIdは「nil」を許容する(旧アプリのBookMigrationServiceが移行後の通常起動時に
// nilなbookIdをメイン帳簿へバックフィルする設計のため、nilは異常ではない)。
// 一方、bookIdが「値を持っているのに、その値が実在するBookDataのどれとも一致しない」
// 場合は帳簿分離が壊れていることを意味するため重大エラーとして扱う。
//
// TransferData.fromId/toIdは、bookIdと違って「後から埋める」既存の仕組みが無いため、
// nilも含めて欠落は重大エラーとして扱う(振替は移動元・移動先が無いと成立しないため)。

struct MigrationReferenceIssue: Equatable {
    enum Severity: Equatable {
        case critical
        case warning
    }

    var severity: Severity
    var entity: String
    var field: String
    var recordId: String
    var danglingValue: String?
    var detail: String
}

enum MigrationReferenceValidator {

    struct Pools {
        var bookIds: Set<UUID> = []
        var bankAccountIds: Set<UUID> = []
        var receiveMethodIds: Set<UUID> = []
        var paymentMethodSettingIds: Set<UUID> = []
        var expenseIds: Set<UUID> = []
        var incomeIds: Set<UUID> = []
        var fixedExpenseIds: Set<UUID> = []
        var recurringIncomeIds: Set<UUID> = []
        var recurringTransferSettingIds: Set<UUID> = []
    }

    static func makePools(from snapshot: LegacySnapshot) -> Pools {
        var pools = Pools()
        pools.bookIds = Set(snapshot.books.map(\.id))
        pools.bankAccountIds = Set(snapshot.bankAccounts.map(\.id))
        pools.receiveMethodIds = Set(snapshot.receiveMethods.map(\.id))
        pools.paymentMethodSettingIds = Set(snapshot.paymentMethodSettings.map(\.id))
        pools.expenseIds = Set(snapshot.expenses.map(\.id))
        pools.incomeIds = Set(snapshot.incomes.map(\.id))
        pools.fixedExpenseIds = Set(snapshot.fixedExpenses.map(\.id))
        pools.recurringIncomeIds = Set(snapshot.recurringIncomes.map(\.id))
        pools.recurringTransferSettingIds = Set(snapshot.recurringTransferSettings.map(\.id))
        return pools
    }

    static func validate(snapshot: LegacySnapshot) -> [MigrationReferenceIssue] {
        let pools = makePools(from: snapshot)
        var issues: [MigrationReferenceIssue] = []

        func checkBookId(_ bookId: UUID?, entity: String, recordId: UUID) {
            guard let bookId else { return } // nilは正常(BookMigrationServiceが後で埋める)
            if !pools.bookIds.contains(bookId) {
                issues.append(MigrationReferenceIssue(
                    severity: .critical, entity: entity, field: "bookId",
                    recordId: recordId.uuidString, danglingValue: bookId.uuidString,
                    detail: "bookIdが実在するBookDataのどれとも一致しない(帳簿分離が壊れる)"
                ))
            }
        }

        func checkOptionalWarning(_ value: UUID?, in pool: Set<UUID>, entity: String, field: String, recordId: UUID) {
            guard let value else { return }
            if !pool.contains(value) {
                issues.append(MigrationReferenceIssue(
                    severity: .warning, entity: entity, field: field,
                    recordId: recordId.uuidString, danglingValue: value.uuidString,
                    detail: "参照先が見つからない(optional。UIの補助情報・廃止済み設定として警告扱い)"
                ))
            }
        }

        // MARK: - CategoryData
        for row in snapshot.categories {
            checkBookId(row.bookId, entity: "CategoryData", recordId: row.id)
        }

        // MARK: - ExpenseData
        for row in snapshot.expenses {
            checkBookId(row.bookId, entity: "ExpenseData", recordId: row.id)
            checkOptionalWarning(row.bankAccountId, in: pools.bankAccountIds, entity: "ExpenseData", field: "bankAccountId", recordId: row.id)
            checkOptionalWarning(row.fixedExpenseId, in: pools.fixedExpenseIds, entity: "ExpenseData", field: "fixedExpenseId", recordId: row.id)
        }

        // MARK: - IncomeData
        for row in snapshot.incomes {
            checkBookId(row.bookId, entity: "IncomeData", recordId: row.id)
            checkOptionalWarning(row.bankAccountId, in: pools.bankAccountIds, entity: "IncomeData", field: "bankAccountId", recordId: row.id)
            checkOptionalWarning(row.recurringIncomeId, in: pools.recurringIncomeIds, entity: "IncomeData", field: "recurringIncomeId", recordId: row.id)
        }

        // MARK: - TransferData(fromId/toId/fromType/toTypeは重大エラー)
        for row in snapshot.transfers {
            checkBookId(row.bookId, entity: "TransferData", recordId: row.id)
            checkOptionalWarning(row.recurringTransferSettingId, in: pools.recurringTransferSettingIds, entity: "TransferData", field: "recurringTransferSettingId", recordId: row.id)

            validateTransferEndpoint(
                type: row.fromType, id: row.fromId, pools: pools,
                entity: "TransferData", field: "fromId", recordId: row.id, issues: &issues
            )
            validateTransferEndpoint(
                type: row.toType, id: row.toId, pools: pools,
                entity: "TransferData", field: "toId", recordId: row.id, issues: &issues
            )
        }

        // MARK: - BankAccountData
        for row in snapshot.bankAccounts {
            checkBookId(row.bookId, entity: "BankAccountData", recordId: row.id)
            checkOptionalWarning(row.initialBalanceIncomeId, in: pools.incomeIds, entity: "BankAccountData", field: "initialBalanceIncomeId", recordId: row.id)
            checkOptionalWarning(row.recurringTransferSettingId, in: pools.recurringTransferSettingIds, entity: "BankAccountData", field: "recurringTransferSettingId", recordId: row.id)
            for settingId in row.recurringTransferSettingIds {
                checkOptionalWarning(settingId, in: pools.recurringTransferSettingIds, entity: "BankAccountData", field: "recurringTransferSettingIds", recordId: row.id)
            }
        }

        // MARK: - ReceiveMethodData
        for row in snapshot.receiveMethods {
            checkBookId(row.bookId, entity: "ReceiveMethodData", recordId: row.id)
        }

        // MARK: - PaymentMethodSettingData
        for row in snapshot.paymentMethodSettings {
            checkBookId(row.bookId, entity: "PaymentMethodSettingData", recordId: row.id)
            checkOptionalWarning(row.withdrawalBankAccountId, in: pools.bankAccountIds, entity: "PaymentMethodSettingData", field: "withdrawalBankAccountId", recordId: row.id)
            checkOptionalWarning(row.assetInitialBalanceIncomeId, in: pools.incomeIds, entity: "PaymentMethodSettingData", field: "assetInitialBalanceIncomeId", recordId: row.id)
            checkOptionalWarning(row.assetInitialBalanceExpenseId, in: pools.expenseIds, entity: "PaymentMethodSettingData", field: "assetInitialBalanceExpenseId", recordId: row.id)
            checkOptionalWarning(row.recurringTransferSettingId, in: pools.recurringTransferSettingIds, entity: "PaymentMethodSettingData", field: "recurringTransferSettingId", recordId: row.id)
            for settingId in row.recurringTransferSettingIds {
                checkOptionalWarning(settingId, in: pools.recurringTransferSettingIds, entity: "PaymentMethodSettingData", field: "recurringTransferSettingIds", recordId: row.id)
            }
        }

        // MARK: - BudgetData / RecurringBudgetData
        for row in snapshot.budgets {
            checkBookId(row.bookId, entity: "BudgetData", recordId: row.id)
        }
        for row in snapshot.recurringBudgets {
            checkBookId(row.bookId, entity: "RecurringBudgetData", recordId: row.id)
        }

        // MARK: - FixedExpenseData
        // paymentMethodType: "bankAccount" | "paymentMethod" | "" (TransferAccountTypeとは別の文字列表現)。
        // 警告扱いのfieldなので、未知のtype文字列は両プールの和集合で寛容に判定する。
        for row in snapshot.fixedExpenses {
            checkBookId(row.bookId, entity: "FixedExpenseData", recordId: row.id)
            let pool: Set<UUID>
            switch row.paymentMethodType {
            case "bankAccount": pool = pools.bankAccountIds
            case "paymentMethod": pool = pools.paymentMethodSettingIds
            default: pool = pools.bankAccountIds.union(pools.paymentMethodSettingIds)
            }
            checkOptionalWarning(row.paymentMethodId, in: pool, entity: "FixedExpenseData", field: "paymentMethodId", recordId: row.id)
        }

        // MARK: - RecurringIncomeData
        // receiveMethodType: "bankAccount" | "receiveMethod" | "" 。"receiveMethod"は歴史的経緯で
        // ReceiveMethodData/PaymentMethodSettingData(useForReceive)のどちらも指しうるため両方を許容する。
        for row in snapshot.recurringIncomes {
            checkBookId(row.bookId, entity: "RecurringIncomeData", recordId: row.id)
            let pool: Set<UUID>
            switch row.receiveMethodType {
            case "bankAccount": pool = pools.bankAccountIds
            case "receiveMethod": pool = pools.receiveMethodIds.union(pools.paymentMethodSettingIds)
            default: pool = pools.bankAccountIds.union(pools.receiveMethodIds).union(pools.paymentMethodSettingIds)
            }
            checkOptionalWarning(row.receiveMethodId, in: pool, entity: "RecurringIncomeData", field: "receiveMethodId", recordId: row.id)
        }

        // MARK: - RecurringTransferSettingData(fromMethodId/toMethodIdはbookIdと違い警告扱い。
        // ユーザー承認済みの分類:このEntityで重大エラーなのはbookIdのみ)
        for row in snapshot.recurringTransferSettings {
            checkBookId(row.bookId, entity: "RecurringTransferSettingData", recordId: row.id)
            let fromPool = pool(for: row.fromType, pools: pools)
            let toPool = pool(for: row.toType, pools: pools)
            checkOptionalWarning(row.fromMethodId, in: fromPool ?? [], entity: "RecurringTransferSettingData", field: "fromMethodId", recordId: row.id)
            checkOptionalWarning(row.toMethodId, in: toPool ?? [], entity: "RecurringTransferSettingData", field: "toMethodId", recordId: row.id)
        }

        // MARK: - 写真参照(optional。ファイル欠落は警告扱い。実ファイル確認はMigrationVerifier側で行う)

        return issues
    }

    private static func pool(for type: String, pools: Pools) -> Set<UUID>? {
        switch type {
        case TransferAccountType.bank.rawValue: return pools.bankAccountIds
        case TransferAccountType.receive.rawValue: return pools.receiveMethodIds
        case TransferAccountType.paymentMethod.rawValue: return pools.paymentMethodSettingIds
        default: return nil
        }
    }

    private static func validateTransferEndpoint(
        type: String, id: UUID?, pools: Pools,
        entity: String, field: String, recordId: UUID,
        issues: inout [MigrationReferenceIssue]
    ) {
        guard let resolvedPool = pool(for: type, pools: pools) else {
            issues.append(MigrationReferenceIssue(
                severity: .critical, entity: entity, field: field == "fromId" ? "fromType" : "toType",
                recordId: recordId.uuidString, danglingValue: type,
                detail: "fromType/toTypeが既知の値(bank/receive/payment)ではない"
            ))
            return
        }
        guard let id else {
            issues.append(MigrationReferenceIssue(
                severity: .critical, entity: entity, field: field,
                recordId: recordId.uuidString, danglingValue: nil,
                detail: "振替の移動元/移動先IDが欠落している(bookIdと異なり後から埋める仕組みが無い)"
            ))
            return
        }
        guard resolvedPool.contains(id) else {
            issues.append(MigrationReferenceIssue(
                severity: .critical, entity: entity, field: field,
                recordId: recordId.uuidString, danglingValue: id.uuidString,
                detail: "参照先(bank/receive/paymentのいずれか)が実在しない"
            ))
            return
        }
    }
}
