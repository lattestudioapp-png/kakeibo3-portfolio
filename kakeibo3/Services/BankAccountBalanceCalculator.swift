import Foundation

// MARK: - 支払い方法（資産）残高サマリー

struct PaymentMethodBalanceSummary: Identifiable {
    let id: UUID
    let name: String
    let balance: Int
    let sortOrder: Int
    let isAsset: Bool   // true = 残高管理あり
    let type: PaymentMethodType
    let colorHex: String?
}

// MARK: - 銀行口座残高サマリー

struct BankAccountBalanceSummary: Identifiable {
    let id: UUID             // BankAccountData.id
    let name: String
    let balance: Int         // 指定期間末時点の残高
    let periodIncome: Int    // 期間内の収入
    let periodExpense: Int   // 期間内の支出
    let sortOrder: Int
    let isActive: Bool
    let colorHex: String?
}

// MARK: - 銀行口座残高計算サービス

/// 銀行口座残高の計算を一元管理するサービス。
/// 新形式（bankAccountId）と旧形式（receiveMethod/paymentMethod の文字列一致）を両方サポートする。
struct BankAccountBalanceCalculator {
    let bankAccounts: [BankAccountData]
    let allIncomeData: [IncomeData]
    let allExpenseData: [ExpenseData]
    let allTransferData: [TransferData]
    let creditCardNames: Set<String>
    var assetReflectionTiming: CreditCardAssetReflectionTiming = .withdrawalDate

    // MARK: - 期間サマリー
    //
    // 口座ごとにallIncomeData/allExpenseData/allTransferDataを毎回filterし直す
    // （O(口座数 × 取引件数)）と口座数・取引件数が増えるほど重くなるため、
    // 1回の走査で口座IDごとに集計してから割り当てる（O(口座数 + 取引件数)）。

    func summaries(for dateRange: AnalysisDateRange) -> [BankAccountBalanceSummary] {
        let activeBanks = bankAccounts.filter { $0.isActive }
        guard !activeBanks.isEmpty else { return [] }

        // bankAccountIdが未設定の旧データ用：口座名（および「口座振込：」「出金：」表記）からの逆引き
        var bankByLegacyName: [String: BankAccountData] = [:]
        for bank in activeBanks {
            bankByLegacyName[bank.accountName] = bank
            bankByLegacyName["口座振込：\(bank.accountName)"] = bank
            bankByLegacyName["出金：\(bank.accountName)"] = bank
        }
        let bankById = Dictionary(uniqueKeysWithValues: activeBanks.map { ($0.id, $0) })

        func resolveBank(bankAccountId: UUID?, method: String) -> BankAccountData? {
            if let bid = bankAccountId { return bankById[bid] }
            return bankByLegacyName[method]
        }

        var balanceIncomeByBank: [UUID: Int] = [:]
        var balanceExpenseByBank: [UUID: Int] = [:]
        var balanceTransferInByBank: [UUID: Int] = [:]
        var balanceTransferOutByBank: [UUID: Int] = [:]
        var periodIncomeByBank: [UUID: Int] = [:]
        var periodExpenseByBank: [UUID: Int] = [:]

        for income in allIncomeData {
            guard let bank = resolveBank(bankAccountId: income.bankAccountId, method: income.receiveMethod) else { continue }
            if income.date < dateRange.end {
                balanceIncomeByBank[bank.id, default: 0] += income.amount
            }
            if income.date >= dateRange.start && income.date < dateRange.end {
                periodIncomeByBank[bank.id, default: 0] += income.amount
            }
        }

        for expense in allExpenseData where !creditCardNames.contains(expense.paymentMethod) {
            guard let bank = resolveBank(bankAccountId: expense.bankAccountId, method: expense.paymentMethod) else { continue }
            if expense.date < dateRange.end {
                balanceExpenseByBank[bank.id, default: 0] += expense.amount
            }
            if expense.date >= dateRange.start && expense.date < dateRange.end {
                periodExpenseByBank[bank.id, default: 0] += expense.amount
            }
        }

        for transfer in allTransferData where transfer.date < dateRange.end {
            if transfer.toType == TransferAccountType.bank.rawValue, let toId = transfer.toId {
                balanceTransferInByBank[toId, default: 0] += transfer.amount
            }
            if transfer.fromType == TransferAccountType.bank.rawValue, let fromId = transfer.fromId {
                balanceTransferOutByBank[fromId, default: 0] += transfer.amount + transfer.feeAmount
            }
        }

        return activeBanks
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.createdAt < $1.createdAt
                    : $0.sortOrder < $1.sortOrder
            }
            .map { bank in
                let initialFromField = (bank.initialBalanceIncomeId == nil) ? Int(bank.initialBalance ?? 0) : 0
                let balance = initialFromField
                    + (balanceIncomeByBank[bank.id] ?? 0) - (balanceExpenseByBank[bank.id] ?? 0)
                    + (balanceTransferInByBank[bank.id] ?? 0) - (balanceTransferOutByBank[bank.id] ?? 0)
                return BankAccountBalanceSummary(
                    id: bank.id,
                    name: bank.accountName,
                    balance: balance,
                    periodIncome: periodIncomeByBank[bank.id] ?? 0,
                    periodExpense: periodExpenseByBank[bank.id] ?? 0,
                    sortOrder: bank.sortOrder,
                    isActive: bank.isActive,
                    colorHex: bank.colorHex
                )
            }
    }

    // MARK: - 総資産（全口座合計）

    /// 総資産計算。
    /// - 利用日に反映: クレジットカード支出を利用日に計上（銀行残高への反映はしない）。
    /// - 引き落とし日に反映: クレジットカード支出を除外し、口座別残高と一致させる。
    /// 月次収支（periodBalance）はどちらの設定でもクレジットカードを含める。
    /// - pmInitialOffset: income エントリが未作成の支払い方法初期残高の合計（呼び出し元で計算）
    func totalAssets(upTo endDate: Date, pmInitialOffset: Int = 0) -> Int {
        let income = allIncomeData
            .filter { $0.date < endDate }
            .reduce(0) { $0 + $1.amount }
        let expense: Int
        switch assetReflectionTiming {
        case .usageDate:
            expense = allExpenseData
                .filter { $0.date < endDate }
                .reduce(0) { $0 + $1.amount }
        case .withdrawalDate:
            expense = allExpenseData
                .filter { $0.date < endDate && !creditCardNames.contains($0.paymentMethod) }
                .reduce(0) { $0 + $1.amount }
        }
        let fees = allTransferData
            .filter { $0.date < endDate }
            .reduce(0) { $0 + $1.feeAmount }
        return pmInitialOffset + income - expense - fees
    }

    // MARK: - 月次収支

    func periodBalance(in dateRange: AnalysisDateRange) -> (income: Int, expense: Int) {
        let income = allIncomeData
            .filter { $0.date >= dateRange.start && $0.date < dateRange.end }
            .reduce(0) { $0 + $1.amount }
        let expense = allExpenseData
            .filter { $0.date >= dateRange.start && $0.date < dateRange.end }
            .reduce(0) { $0 + $1.amount }
        let fees = allTransferData
            .filter { $0.date >= dateRange.start && $0.date < dateRange.end }
            .reduce(0) { $0 + $1.feeAmount }
        return (income, expense + fees)
    }

    // MARK: - 日次資産推移（旧: 選択月のみ）

    func dailyAssetPoints(for dateRange: AnalysisDateRange) -> [(date: Date, value: Int)] {
        guard let end = Calendar.current.date(byAdding: .day, value: -1, to: dateRange.end) else { return [] }
        return dailyAssetPoints(from: dateRange.start, to: end)
    }

    // MARK: - 日次資産推移（家計簿開始〜選択月末）

    /// startDate〜endDate（両端含む）の日次資産累計を running sum で効率計算する。
    /// - pmInitialOffset: income エントリが未作成の支払い方法初期残高の合計（呼び出し元で計算）
    func dailyAssetPoints(from startDate: Date, to endDate: Date, pmInitialOffset: Int = 0) -> [(date: Date, value: Int)] {
        let cal = Calendar.current
        var days: [Date] = []
        var current = cal.startOfDay(for: startDate)
        let last    = cal.startOfDay(for: endDate)
        while current <= last {
            days.append(current)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        guard !days.isEmpty else { return [] }

        // ソートは1回だけ（O(n log n)）
        let sortedIncome = allIncomeData.sorted { $0.date < $1.date }
        let chartExpenses = (assetReflectionTiming == .withdrawalDate
            ? allExpenseData.filter { !creditCardNames.contains($0.paymentMethod) }
            : allExpenseData
        ).sorted { $0.date < $1.date }
        let sortedTransfers = allTransferData.sorted { $0.date < $1.date }

        var cumIncome = 0, cumExpense = 0, cumFees = 0
        var iIdx = 0, eIdx = 0, tIdx = 0

        return days.map { day in
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day
            while iIdx < sortedIncome.count   && sortedIncome[iIdx].date   < dayEnd { cumIncome   += sortedIncome[iIdx].amount;      iIdx += 1 }
            while eIdx < chartExpenses.count  && chartExpenses[eIdx].date  < dayEnd { cumExpense  += chartExpenses[eIdx].amount;     eIdx += 1 }
            while tIdx < sortedTransfers.count && sortedTransfers[tIdx].date < dayEnd { cumFees   += sortedTransfers[tIdx].feeAmount; tIdx += 1 }
            return (date: day, value: pmInitialOffset + cumIncome - cumExpense - cumFees)
        }
    }

    // MARK: - 支払い方法（資産）残高
    //
    // summaries(for:)と同様、方法ごとに全件filterし直すのはO(方法数 × 取引件数)になるため、
    // 1回の走査で方法IDごとに集計してから割り当てる。

    func paymentMethodSummaries(for methods: [PaymentMethodSettingData], upTo endDate: Date) -> [PaymentMethodBalanceSummary] {
        guard !methods.isEmpty else { return [] }

        let methodIds = Set(methods.map(\.id))
        // 同名の支払い方法が存在する場合、名前だけでは取引の紐付け先を一意に決められない。
        // Phase 1の重複作成防止で今後は起きなくなるが、既存データ保護のため
        // 決定的に「最も古い(sortOrder→createdAt)方法」を優先し、衝突が起きたことをログに残す。
        let sortedMethods = methods.sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
        var methodByName: [String: PaymentMethodSettingData] = [:]
        for method in sortedMethods {
            if methodByName[method.methodName] != nil {
                TimingDebugLog.write("BankAccountBalanceCalculator: 同名の支払い方法が衝突 name=\(method.methodName)")
                continue
            }
            methodByName[method.methodName] = method
        }

        var incomeByMethod: [UUID: Int] = [:]
        var expenseByMethod: [UUID: Int] = [:]
        var transferInByMethod: [UUID: Int] = [:]
        var transferOutByMethod: [UUID: Int] = [:]

        for income in allIncomeData where income.date < endDate {
            guard let method = methodByName[income.receiveMethod], methodIds.contains(method.id) else { continue }
            incomeByMethod[method.id, default: 0] += income.amount
        }

        for expense in allExpenseData where expense.date < endDate {
            guard let method = methodByName[expense.paymentMethod], methodIds.contains(method.id) else { continue }
            expenseByMethod[method.id, default: 0] += expense.amount
        }

        for transfer in allTransferData where transfer.date < endDate {
            if transfer.toType == TransferAccountType.paymentMethod.rawValue, let toId = transfer.toId {
                transferInByMethod[toId, default: 0] += transfer.amount
            }
            if transfer.fromType == TransferAccountType.paymentMethod.rawValue, let fromId = transfer.fromId {
                transferOutByMethod[fromId, default: 0] += transfer.amount + transfer.feeAmount
            }
        }

        return methods
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map { method in
                // assetInitialBalanceIncomeId/assetInitialBalanceExpenseId がない場合は field から直接加算（二重計上防止）
                let hasLinkedInitialTransaction = method.assetInitialBalanceIncomeId != nil || method.assetInitialBalanceExpenseId != nil
                let initialFromField = hasLinkedInitialTransaction ? 0 : Int(method.assetInitialBalance ?? 0)
                let balance = initialFromField
                    + (incomeByMethod[method.id] ?? 0) - (expenseByMethod[method.id] ?? 0)
                    + (transferInByMethod[method.id] ?? 0) - (transferOutByMethod[method.id] ?? 0)
                return PaymentMethodBalanceSummary(
                    id: method.id,
                    name: method.methodName,
                    balance: balance,
                    sortOrder: method.sortOrder,
                    isAsset: method.isAsset,
                    type: PaymentMethodType(rawValue: method.type) ?? .other,
                    colorHex: method.colorHex
                )
            }
    }
}
