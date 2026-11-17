import Foundation
import Combine
import SwiftUI

// MARK: - 詳細表示対象

struct AssetDetailTarget: Identifiable {
    enum Kind { case bank, paymentMethod }
    let id: UUID
    let name: String
    let kind: Kind
    /// true = 残高管理あり（残高カード＋推移グラフ表示）
    let hasBalance: Bool
    /// 「今月の支出」を計算する基準月（分析タブで選択中の月）
    let selectedDate: Date
}

// MARK: - 資産詳細ViewModel

final class AssetDetailViewModel: ObservableObject {

    // MARK: - 残高ありタイプ

    @Published private(set) var currentBalance: Int = 0
    /// 全履歴ぶんの日別ポイント（取引が無い日も前日の値を引き継いだ、隙間のない配列）。
    /// 実際の表示粒度・間引きはAssetTrendChartView側のAssetGraphPointReducerが決める。
    @Published private(set) var balanceChartPoints: [AssetChartPoint] = []
    /// 実際に記録が存在する最古の日付（グラフの「全期間」開始日クランプに使う）
    @Published private(set) var balanceChartEarliestDate: Date? = nil
    @Published private(set) var expenseCategoryItems: [AnalysisCategorySummary] = []
    @Published private(set) var incomeCategoryItems: [AnalysisCategorySummary] = []
    @Published private(set) var transactions: [TransactionListItem] = []

    // MARK: - 残高なしタイプ

    /// 選択月の支出合計（残高なしタイプのみ使用）
    @Published private(set) var thisMonthExpense: Int = 0
    /// 選択月のラベル（例: "6月"）
    @Published private(set) var selectedMonthLabel: String = ""

    // MARK: - 共通

    @Published private(set) var isLoaded: Bool = false

    // MARK: - rebuild エントリポイント

    func rebuild(
        target: AssetDetailTarget,
        allBankAccounts: [BankAccountData],
        allIncomes: [IncomeData],
        allExpenses: [ExpenseData],
        allTransfers: [TransferData],
        allCategories: [CategoryData],
        allPaymentMethods: [PaymentMethodSettingData]
    ) {
        let creditCardNames = Set(
            allPaymentMethods
                .filter { $0.type == PaymentMethodType.creditCard.rawValue }
                .map(\.methodName)
        )

        switch target.kind {
        case .bank:
            guard let bank = allBankAccounts.first(where: { $0.id == target.id }) else { return }
            rebuildForBank(
                bank,
                allIncomes: allIncomes, allExpenses: allExpenses,
                allTransfers: allTransfers, allCategories: allCategories,
                creditCardNames: creditCardNames
            )
        case .paymentMethod:
            guard let method = allPaymentMethods.first(where: { $0.id == target.id }) else { return }
            if target.hasBalance {
                rebuildForPaymentMethod(
                    method,
                    allIncomes: allIncomes, allExpenses: allExpenses,
                    allTransfers: allTransfers, allCategories: allCategories
                )
            } else {
                rebuildForPaymentMethodNoBalance(
                    method,
                    allExpenses: allExpenses,
                    allCategories: allCategories,
                    selectedDate: target.selectedDate
                )
            }
        }
        isLoaded = true
    }

    // MARK: - 銀行口座（残高あり）

    private func rebuildForBank(
        _ bank: BankAccountData,
        allIncomes: [IncomeData],
        allExpenses: [ExpenseData],
        allTransfers: [TransferData],
        allCategories: [CategoryData],
        creditCardNames: Set<String>
    ) {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        let matchedIncomes = allIncomes.filter {
            matchesBank($0.bankAccountId, method: $0.receiveMethod, bank: bank)
        }
        let matchedExpenses = allExpenses
            .filter { !creditCardNames.contains($0.paymentMethod) }
            .filter { matchesBank($0.bankAccountId, method: $0.paymentMethod, bank: bank) }
        let transferIn  = allTransfers.filter {
            $0.toType == TransferAccountType.bank.rawValue && $0.toId == bank.id
        }
        let transferOut = allTransfers.filter {
            $0.fromType == TransferAccountType.bank.rawValue && $0.fromId == bank.id
        }

        let initialFromField = (bank.initialBalanceIncomeId == nil) ? Int(bank.initialBalance ?? 0) : 0
        let inc  = matchedIncomes.reduce(0)  { $0 + $1.amount }
        let exp  = matchedExpenses.reduce(0) { $0 + $1.amount }
        let tIn  = transferIn.reduce(0)      { $0 + $1.amount }
        let tOut = transferOut.reduce(0)     { $0 + $1.amount + $1.feeAmount }
        currentBalance = initialFromField + inc - exp + tIn - tOut

        let chart = buildBalanceChart(
            incomes: matchedIncomes, expenses: matchedExpenses,
            transfersIn: transferIn, transfersOut: transferOut,
            today: today, cal: cal,
            initialOffset: initialFromField
        )
        balanceChartPoints = chart.daily
        balanceChartEarliestDate = chart.earliest
        expenseCategoryItems = buildCategoryItems(
            items: matchedExpenses.map { ($0.category, $0.amount) },
            categoryType: "支出", categories: allCategories
        )
        incomeCategoryItems = buildCategoryItems(
            items: matchedIncomes.map { ($0.category, $0.amount) },
            categoryType: "収入", categories: allCategories
        )
        transactions = (
            matchedIncomes.map  { TransactionListItem.income(from: $0) }
            + matchedExpenses.map { TransactionListItem.expense(from: $0) }
            + dedup(transferIn + transferOut).map { TransactionListItem.transfer(from: $0) }
        ).sorted { $0.date > $1.date }

        thisMonthExpense = 0
        selectedMonthLabel = ""
    }

    // MARK: - 支払い方法（残高あり）

    private func rebuildForPaymentMethod(
        _ method: PaymentMethodSettingData,
        allIncomes: [IncomeData],
        allExpenses: [ExpenseData],
        allTransfers: [TransferData],
        allCategories: [CategoryData]
    ) {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        let matchedIncomes  = allIncomes.filter  { $0.receiveMethod == method.methodName }
        let matchedExpenses = allExpenses.filter { $0.paymentMethod == method.methodName }
        let transferIn  = allTransfers.filter {
            $0.toType == TransferAccountType.paymentMethod.rawValue && $0.toId == method.id
        }
        let transferOut = allTransfers.filter {
            $0.fromType == TransferAccountType.paymentMethod.rawValue && $0.fromId == method.id
        }

        let initialFromField = (method.assetInitialBalanceIncomeId == nil) ? Int(method.assetInitialBalance ?? 0) : 0
        let inc  = matchedIncomes.reduce(0)  { $0 + $1.amount }
        let exp  = matchedExpenses.reduce(0) { $0 + $1.amount }
        let tIn  = transferIn.reduce(0)      { $0 + $1.amount }
        let tOut = transferOut.reduce(0)     { $0 + $1.amount + $1.feeAmount }
        currentBalance = initialFromField + inc - exp + tIn - tOut

        let chart = buildBalanceChart(
            incomes: matchedIncomes, expenses: matchedExpenses,
            transfersIn: transferIn, transfersOut: transferOut,
            today: today, cal: cal,
            initialOffset: initialFromField
        )
        balanceChartPoints = chart.daily
        balanceChartEarliestDate = chart.earliest
        expenseCategoryItems = buildCategoryItems(
            items: matchedExpenses.map { ($0.category, $0.amount) },
            categoryType: "支出", categories: allCategories
        )
        incomeCategoryItems = buildCategoryItems(
            items: matchedIncomes.map { ($0.category, $0.amount) },
            categoryType: "収入", categories: allCategories
        )
        transactions = (
            matchedIncomes.map  { TransactionListItem.income(from: $0) }
            + matchedExpenses.map { TransactionListItem.expense(from: $0) }
            + dedup(transferIn + transferOut).map { TransactionListItem.transfer(from: $0) }
        ).sorted { $0.date > $1.date }

        thisMonthExpense = 0
        selectedMonthLabel = ""
    }

    // MARK: - 支払い方法（残高なし：クレジットカード等）

    private func rebuildForPaymentMethodNoBalance(
        _ method: PaymentMethodSettingData,
        allExpenses: [ExpenseData],
        allCategories: [CategoryData],
        selectedDate: Date
    ) {
        let cal = Calendar.current

        let comps = cal.dateComponents([.year, .month], from: selectedDate)
        let monthStart = cal.date(from: comps) ?? selectedDate
        let monthEnd   = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let matchedExpenses = allExpenses.filter { $0.paymentMethod == method.methodName }

        thisMonthExpense = matchedExpenses
            .filter { $0.date >= monthStart && $0.date < monthEnd }
            .reduce(0) { $0 + $1.amount }

        selectedMonthLabel = "\(cal.component(.month, from: selectedDate))月"

        expenseCategoryItems = buildCategoryItems(
            items: matchedExpenses.map { ($0.category, $0.amount) },
            categoryType: "支出", categories: allCategories
        )

        transactions = matchedExpenses
            .map { TransactionListItem.expense(from: $0) }
            .sorted { $0.date > $1.date }

        currentBalance = 0
        balanceChartPoints = []
        balanceChartEarliestDate = nil
        incomeCategoryItems = []
    }

    // MARK: - 残高チャート構築（O(N log N + D) running-sum）
    //
    // 全履歴ぶんの日別ポイントを1つ作る（1日1点、取引が無い日も前日の値を引き継ぐ）。
    // 実際に何点表示するか（日別/週別/月別/年別・間引き）はAssetTrendChartView側の
    // AssetGraphPointReducerが最大表示点数に応じてその都度決める。

    private func buildBalanceChart(
        incomes: [IncomeData],
        expenses: [ExpenseData],
        transfersIn: [TransferData],
        transfersOut: [TransferData],
        today: Date,
        cal: Calendar,
        initialOffset: Int = 0
    ) -> (daily: [AssetChartPoint], earliest: Date?) {
        let allDates = incomes.map(\.date) + expenses.map(\.date)
            + transfersIn.map(\.date) + transfersOut.map(\.date)
        guard let earliest = allDates.min().map({ cal.startOfDay(for: $0) }) else { return ([], nil) }

        var days: [Date] = []
        var cur = earliest
        while cur <= today {
            days.append(cur)
            guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }

        let sortedI  = incomes.sorted      { $0.date < $1.date }
        let sortedE  = expenses.sorted     { $0.date < $1.date }
        let sortedTI = transfersIn.sorted  { $0.date < $1.date }
        let sortedTO = transfersOut.sorted { $0.date < $1.date }

        var cumI = 0, cumE = 0, cumTI = 0, cumTO = 0
        var iIdx = 0, eIdx = 0, tiIdx = 0, toIdx = 0
        var dailyResult: [AssetChartPoint] = []
        dailyResult.reserveCapacity(days.count)

        for day in days {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            while iIdx  < sortedI.count  && sortedI[iIdx].date    < next { cumI  += sortedI[iIdx].amount;                               iIdx  += 1 }
            while eIdx  < sortedE.count  && sortedE[eIdx].date    < next { cumE  += sortedE[eIdx].amount;                               eIdx  += 1 }
            while tiIdx < sortedTI.count && sortedTI[tiIdx].date  < next { cumTI += sortedTI[tiIdx].amount;                             tiIdx += 1 }
            while toIdx < sortedTO.count && sortedTO[toIdx].date  < next { cumTO += sortedTO[toIdx].amount + sortedTO[toIdx].feeAmount; toIdx += 1 }
            dailyResult.append(AssetChartPoint(id: day, date: day, assetAmount: initialOffset + cumI - cumE + cumTI - cumTO))
        }

        return (dailyResult, earliest)
    }

    // MARK: - カテゴリ集計

    private func buildCategoryItems(
        items: [(category: String, amount: Int)],
        categoryType: String,
        categories: [CategoryData]
    ) -> [AnalysisCategorySummary] {
        var totals: [String: Int] = [:]
        for item in items { totals[item.category, default: 0] += item.amount }
        let positives = totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = positives.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }

        return positives.compactMap { name, amount in
            let pct = Double(amount) / Double(total) * 100
            guard Int(pct) >= 1 else { return nil }
            return AnalysisCategorySummary(
                id: name, categoryName: name,
                color: categoryColor(for: name, type: categoryType, categories: categories),
                totalAmount: amount, percentage: pct,
                monthOverMonthDiff: nil
            )
        }
    }

    private func categoryColor(for name: String, type: String, categories: [CategoryData]) -> Color {
        if let hex = categories.first(where: { $0.name == name && $0.type == type })?.colorHex,
           !hex.isEmpty {
            let normalized = CategoryColorPalette.normalize(hex)
            if normalized != "#" && !normalized.isEmpty {
                return ColorHexConverter.color(from: normalized)
            }
        }
        return ColorHexConverter.color(
            from: CategoryColorPalette.colors[abs(name.hashValue) % CategoryColorPalette.colors.count]
        )
    }

    // MARK: - ヘルパー

    private func matchesBank(_ bankAccountId: UUID?, method: String, bank: BankAccountData) -> Bool {
        if let bid = bankAccountId { return bid == bank.id }
        return method == bank.accountName
            || method == "口座振込：\(bank.accountName)"
            || method == "出金：\(bank.accountName)"
    }

    private func dedup(_ transfers: [TransferData]) -> [TransferData] {
        var seen = Set<UUID>()
        return transfers.filter { seen.insert($0.id).inserted }
    }
}
