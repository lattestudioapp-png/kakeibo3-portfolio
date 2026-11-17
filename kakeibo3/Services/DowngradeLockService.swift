import Foundation

// MARK: - ロック判定サービス
//
// 以前は無料版の登録数上限を超えた項目を isLocked = true にしてロックしていたが、
// 現在は登録数の上限そのものを廃止したため、isLocked が true になることはない。
// このサービスは、isLocked を前提にした既存の判定ロジック（カレンダー・分析等の
// 集計処理）が引き続き安全に動くよう、判定関数と unlockAll だけを残している。

struct DowngradeLockService {

    // MARK: - 過去にロックされたデータが残っている場合に備えて、全カテゴリのロックを解除する

    static func unlockAll() {
        for method in PaymentMethodSettingDataSync.fetchAll() where method.isLocked {
            var unlocked = method
            unlocked.isLocked = false
            PaymentMethodSettingDataSync.update(unlocked)
        }

        for account in BankAccountDataSync.fetchAll() where account.isLocked {
            var unlocked = account
            unlocked.isLocked = false
            BankAccountDataSync.update(unlocked)
        }

        for fixedExpense in FixedExpenseDataSync.fetchAll() where fixedExpense.isLocked {
            var unlocked = fixedExpense
            unlocked.isLocked = false
            FixedExpenseDataSync.update(unlocked)
        }

        for recurringIncome in RecurringIncomeDataSync.fetchAll() where recurringIncome.isLocked {
            var unlocked = recurringIncome
            unlocked.isLocked = false
            RecurringIncomeDataSync.update(unlocked)
        }

        for recurringTransfer in RecurringTransferSettingDataSync.fetchAll() where recurringTransfer.isLocked {
            var unlocked = recurringTransfer
            unlocked.isLocked = false
            RecurringTransferSettingDataSync.update(unlocked)
        }
    }

    // MARK: - クレジットカードは、カード自身と引き落とし口座の両方が unlocked な場合のみ利用可能

    static func isCreditCardUsable(_ card: PaymentMethodSettingData, bankAccounts: [BankAccountData]) -> Bool {
        guard !card.isLocked else { return false }
        guard let withdrawalId = card.withdrawalBankAccountId else { return true }
        guard let linkedAccount = bankAccounts.first(where: { $0.id == withdrawalId }) else { return true }
        return !linkedAccount.isLocked
    }

    // MARK: - 取引（履歴・分析）がロック中の支払い/受け取り方法に紐づいているかを判定する
    //
    // 銀行口座は bankAccountId で確実に判定する。カード等は履歴に方法IDを保持していないため
    // 名前一致で判定し、クレジットカードは「カード自身」に加えて「紐づく引き落とし口座」の
    // ロックも連動して見る（isCreditCardUsable と同じ考え方）。

    static func isMethodLocked(
        bankAccountId: UUID?, methodName: String,
        bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> Bool {
        if let id = bankAccountId {
            return bankAccounts.first(where: { $0.id == id })?.isLocked ?? false
        }
        guard !methodName.isEmpty else { return false }
        guard let method = paymentMethods.first(where: { $0.methodName == methodName }) else { return false }
        if method.type == PaymentMethodType.creditCard.rawValue {
            return !isCreditCardUsable(method, bankAccounts: bankAccounts)
        }
        return method.isLocked
    }

    // MARK: - 上記の判定でロック中と判定される取引を除いた配列を返す便利関数
    //
    // カレンダー・予算・分析など、取引データを集計するあらゆる画面から共通で使う。

    static func visibleExpenses(
        _ expenses: [ExpenseData], bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> [ExpenseData] {
        expenses.filter {
            !isMethodLocked(bankAccountId: $0.bankAccountId, methodName: $0.paymentMethod, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        }
    }

    static func visibleIncomes(
        _ incomes: [IncomeData], bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> [IncomeData] {
        incomes.filter {
            !isMethodLocked(bankAccountId: $0.bankAccountId, methodName: $0.receiveMethod, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        }
    }

    // MARK: - 資産集計専用の除外判定
    //
    // 総資産・資産推移・分析>資産の内訳表示は、すべて「資産に含める」(isAsset)だけで
    // 集計対象を決める（ロック中は従来通り除外する）。showInAnalysis/includeInAnalysisという
    // 別フィールドは過去に「分析に表示」という独立設定として存在していたが、UIからも
    // ロジックからも廃止済み（現在はモデルにフィールドが残っているだけで未使用。
    // BackupData/BackupManagerが旧バックアップとの互換のために参照している）。
    // カレンダー・分析>支出・分析>収入・分析>決済はisAssetの影響を受けない
    // （ロック中かどうかだけで判定。DowngradeLockService.visibleExpenses/visibleIncomes参照）。

    static func isExcludedFromAssetTotal(
        bankAccountId: UUID?, methodName: String,
        bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> Bool {
        if let id = bankAccountId {
            guard let bank = bankAccounts.first(where: { $0.id == id }) else { return false }
            return !bank.isAsset || bank.isLocked
        }
        guard !methodName.isEmpty else { return false }
        if isMethodLocked(bankAccountId: nil, methodName: methodName, bankAccounts: bankAccounts, paymentMethods: paymentMethods) {
            return true
        }
        guard let method = paymentMethods.first(where: { $0.methodName == methodName }) else { return false }
        // クレジットカードはisAssetの概念を持たない（編集画面に「資産に含める」トグルが無く、
        // モデルのデフォルトfalseのまま変えようがない）。クレジットカード利用分を資産集計に
        // 含めるかどうかはcreditCardNames + assetReflectionTiming側で別途判定するため、
        // ここでisAssetを理由に除外すると「利用日に反映」モードでも一切計上されなくなってしまう。
        if method.type == PaymentMethodType.creditCard.rawValue {
            return false
        }
        return !method.isAsset
    }

    static func assetTotalExpenses(
        _ expenses: [ExpenseData], bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> [ExpenseData] {
        expenses.filter {
            !isExcludedFromAssetTotal(bankAccountId: $0.bankAccountId, methodName: $0.paymentMethod, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        }
    }

    static func assetTotalIncomes(
        _ incomes: [IncomeData], bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> [IncomeData] {
        incomes.filter {
            !isExcludedFromAssetTotal(bankAccountId: $0.bankAccountId, methodName: $0.receiveMethod, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        }
    }

}
