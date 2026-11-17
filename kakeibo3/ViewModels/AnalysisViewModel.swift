import SwiftUI
import Combine

// MARK: - 資産推移グラフ1点（日次・1日1点）

struct AssetChartPoint: Identifiable, Equatable {
    let id: Date
    let date: Date
    let assetAmount: Int
}

// MARK: - 分析View用キャッシュViewModel
//
// 分析タブで必要なすべての集計結果を保持する。
// body の描画中・グラフ操作中は再計算せず、
// データ変更・月変更・タブ変更時にのみ rebuild を呼ぶ。

final class AnalysisViewModel: ObservableObject {

    // MARK: - 支出タブ
    @Published private(set) var expenseTotal: Int = 0
    @Published private(set) var expenseCount: Int = 0
    @Published private(set) var hasPrevExpenseData: Bool = false
    @Published private(set) var expensePeriodDiff: Int = 0
    @Published private(set) var expenseDailyAverage: Int = 0
    @Published private(set) var expenseCategoryItems: [AnalysisCategorySummary] = []

    // MARK: - 収入タブ
    @Published private(set) var incomeTotal: Int = 0
    @Published private(set) var incomeCount: Int = 0
    @Published private(set) var hasPrevIncomeData: Bool = false
    @Published private(set) var incomePeriodDiff: Int = 0
    @Published private(set) var incomeDailyAverage: Int = 0
    @Published private(set) var incomeCategoryItems: [AnalysisCategorySummary] = []

    // MARK: - 決済タブ（支払い方法別内訳）
    @Published private(set) var paymentMethodItems: [AnalysisCategorySummary] = []

    // MARK: - 資産タブ
    @Published private(set) var totalAssets: Int = 0
    @Published private(set) var periodIncome: Int = 0
    @Published private(set) var periodExpense: Int = 0
    @Published private(set) var bankSummaries: [BankAccountBalanceSummary] = []
    @Published private(set) var paymentMethodSummaries: [PaymentMethodBalanceSummary] = []

    // MARK: - 静的フォーマッター（毎回生成しない）

    static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy年M月"; return f
    }()
    static let yearFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy年"; return f
    }()
    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy/MM/dd"; return f
    }()
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "d日"; return f
    }()
    static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M/d"; return f
    }()

    // MARK: - 支出・収入・決済タブ再計算

    /// usesLiveAggregation: 会計月開始日設定がデフォルト以外（開始日≠1、または土日祝調整≠なし）の場合true。
    /// この場合、.month/.previousMonthも.customと同じライブ集計パスに流す（AnalysisMonthlySnapshotは
    /// 暦月キャッシュのままのため、会計月境界が暦月とズレる設定ではそのショートカットが使えないため）。
    ///
    /// expenseCategoryFilter/incomeCategoryFilter: 「集計対象」ボタンで選択したカテゴリー名の集合
    /// （nil = 絞り込みなし＝すべて対象）。AnalysisMonthlySnapshotのカテゴリー別内訳には件数が
    /// 保存されていないため、フィルタが有効な間はperiodTypeに関わらず必ずライブ集計パスに流す
    /// （.customと同じ扱い。全履歴を毎回読むが、.customで既に行っている処理と同じなので新規の
    /// 性能懸念ではない）。
    func rebuildExpenseIncome(
        allExpenses: [ExpenseData],
        allIncomes: [IncomeData],
        allTransfers: [TransferData],
        categories: [CategoryData],
        paymentMethods: [PaymentMethodSettingData],
        bankAccounts: [BankAccountData],
        dateRange: AnalysisDateRange,
        prevDateRange: AnalysisDateRange,
        periodType: AnalysisPeriodType,
        monthlySnapshots: [AnalysisMonthlySnapshot],
        usesLiveAggregation: Bool = false,
        expenseCategoryFilter: Set<String>? = nil,
        incomeCategoryFilter: Set<String>? = nil
    ) {
        let hasCategoryFilter = expenseCategoryFilter != nil || incomeCategoryFilter != nil
        if periodType == .custom || hasCategoryFilter
            || (usesLiveAggregation && (periodType == .month || periodType == .previousMonth)) {
            rebuildExpenseIncomeLive(
                allExpenses: allExpenses, allIncomes: allIncomes, allTransfers: allTransfers,
                categories: categories, paymentMethods: paymentMethods, bankAccounts: bankAccounts,
                dateRange: dateRange, prevDateRange: prevDateRange, periodType: periodType,
                expenseCategoryFilter: expenseCategoryFilter, incomeCategoryFilter: incomeCategoryFilter
            )
        } else {
            rebuildExpenseIncomeFromSnapshots(
                dateRange: dateRange, prevDateRange: prevDateRange, periodType: periodType,
                categories: categories, paymentMethods: paymentMethods, bankAccounts: bankAccounts,
                monthlySnapshots: monthlySnapshots
            )
        }
    }

    // MARK: - ライブ集計（カスタム期間専用。月境界に揃わない任意の日付範囲のため、
    // 月単位のAnalysisMonthlySnapshotだけでは正確に再現できない）

    private func rebuildExpenseIncomeLive(
        allExpenses: [ExpenseData],
        allIncomes: [IncomeData],
        allTransfers: [TransferData],
        categories: [CategoryData],
        paymentMethods: [PaymentMethodSettingData],
        bankAccounts: [BankAccountData],
        dateRange: AnalysisDateRange,
        prevDateRange: AnalysisDateRange,
        periodType: AnalysisPeriodType,
        expenseCategoryFilter: Set<String>? = nil,
        incomeCategoryFilter: Set<String>? = nil
    ) {
        let rs = dateRange.start,   re = dateRange.end
        let ps = prevDateRange.start, pe = prevDateRange.end

        // 支出：対象期間を1回だけフィルタ（決済タブの内訳は「集計対象」の影響を受けないため、
        // カテゴリーで絞り込む前の配列を別に保持しておく）
        let periodAllCategories = allExpenses.filter { $0.date >= rs && $0.date < re }
        let prevAllCategories   = allExpenses.filter { $0.date >= ps && $0.date < pe }
        let period = expenseCategoryFilter.map { filter in periodAllCategories.filter { filter.contains($0.category) } } ?? periodAllCategories
        let prev   = expenseCategoryFilter.map { filter in prevAllCategories.filter { filter.contains($0.category) } } ?? prevAllCategories

        // 「手数料」は実カテゴリーではなく振替の疑似カテゴリーのため、集計対象を絞り込んでいる間は含めない
        let hasExpenseFilter = expenseCategoryFilter != nil
        let fees    = hasExpenseFilter ? [] : allTransfers.filter { $0.date >= rs && $0.date < re && $0.feeAmount > 0 }
                                  .map { (category: "手数料", amount: $0.feeAmount) }
        let prevFees = hasExpenseFilter ? [] : allTransfers.filter { $0.date >= ps && $0.date < pe && $0.feeAmount > 0 }
                                   .map { (category: "手数料", amount: $0.feeAmount) }
        let feeSum     = fees.reduce(0)     { $0 + $1.amount }
        let prevFeeSum = prevFees.reduce(0) { $0 + $1.amount }
        let eTotal     = period.reduce(0) { $0 + $1.amount } + feeSum
        let prevETotal = prev.reduce(0)   { $0 + $1.amount } + prevFeeSum

        expenseTotal        = eTotal
        expenseCount        = period.count + fees.count
        hasPrevExpenseData  = !prev.isEmpty || prevFeeSum > 0
        expensePeriodDiff   = eTotal - prevETotal
        expenseDailyAverage = (eTotal > 0 && periodType.showsDailyAverage) ? eTotal / max(1, dateRange.daysInPeriod) : 0
        expenseCategoryItems = buildCategoryItems(
            period: period.map { ($0.category, $0.amount) } + fees,
            prev:   prev.map   { ($0.category, $0.amount) } + prevFees,
            categoryType: "支出", categories: categories
        )

        // 収入：対象期間を1回だけフィルタ
        let periodIAllCategories = allIncomes.filter { $0.date >= rs && $0.date < re }
        let prevIAllCategories   = allIncomes.filter { $0.date >= ps && $0.date < pe }
        let periodI = incomeCategoryFilter.map { filter in periodIAllCategories.filter { filter.contains($0.category) } } ?? periodIAllCategories
        let prevI   = incomeCategoryFilter.map { filter in prevIAllCategories.filter { filter.contains($0.category) } } ?? prevIAllCategories
        let iTotal     = periodI.reduce(0) { $0 + $1.amount }
        let prevITotal = prevI.reduce(0)   { $0 + $1.amount }

        incomeTotal        = iTotal
        incomeCount        = periodI.count
        hasPrevIncomeData  = !prevI.isEmpty
        incomePeriodDiff   = iTotal - prevITotal
        incomeDailyAverage = (iTotal > 0 && periodType.showsDailyAverage) ? iTotal / max(1, dateRange.daysInPeriod) : 0
        incomeCategoryItems = buildCategoryItems(
            period: periodI.map { ($0.category, $0.amount) },
            prev:   prevI.map   { ($0.category, $0.amount) },
            categoryType: "収入", categories: categories
        )

        // 決済タブの内訳は「集計対象」の影響を受けない（期間だけで絞り込んだ全カテゴリーの支出を使う）
        paymentMethodItems = buildMethodItemsLive(
            period: periodAllCategories, prev: prevAllCategories,
            paymentMethods: paymentMethods, bankAccounts: bankAccounts
        )
    }

    // 支払い方法別内訳のライブ集計（旧PaymentAnalysisView.periodByMethod/methodItemsと同じロジック）
    private func buildMethodItemsLive(
        period: [ExpenseData], prev: [ExpenseData],
        paymentMethods: [PaymentMethodSettingData], bankAccounts: [BankAccountData]
    ) -> [AnalysisCategorySummary] {
        var totals: [String: Int] = [:]
        for e in period { totals[e.paymentMethod, default: 0] += e.amount }
        let sorted = totals.sorted { $0.value > $1.value }
        let totalAmount = sorted.reduce(0) { $0 + $1.value }

        var prevTotals: [String: Int] = [:]
        for e in prev { prevTotals[e.paymentMethod, default: 0] += e.amount }

        return sorted.map { pair in
            let pct = totalAmount > 0 ? Double(pair.value) / Double(totalAmount) * 100 : 0
            let diff: Int? = prevTotals[pair.key].map { pair.value - $0 }
            let color = AnalysisSnapshotBreakdownAggregator.methodColor(
                for: pair.key, paymentMethods: paymentMethods, bankAccounts: bankAccounts
            )
            return AnalysisCategorySummary(
                id: pair.key, categoryName: pair.key, color: color,
                totalAmount: pair.value, percentage: pct, monthOverMonthDiff: diff
            )
        }
    }

    // MARK: - Snapshotベースの集計（月/前月/年/全期間。いずれも月境界に揃っているため
    // AnalysisMonthlySnapshotの内訳をそのまま/合算して使える）

    private func rebuildExpenseIncomeFromSnapshots(
        dateRange: AnalysisDateRange,
        prevDateRange: AnalysisDateRange,
        periodType: AnalysisPeriodType,
        categories: [CategoryData],
        paymentMethods: [PaymentMethodSettingData],
        bankAccounts: [BankAccountData],
        monthlySnapshots: [AnalysisMonthlySnapshot]
    ) {
        let current = snapshotsInRange(dateRange, from: monthlySnapshots)
        let previous = snapshotsInRange(prevDateRange, from: monthlySnapshots)

        // 支出/収入タブの見出し合計はdisplayExpenseTotal/displayIncomeTotal（ロック中かどうかだけで判定、
        // 「資産に含める」の影響を受けない）を使う。総資産・資産推移用のexpenseTotal/incomeTotal
        // （isAsset基準）とは集計対象が異なるので混同しないこと。
        let eTotal = current.reduce(0) { $0 + $1.displayExpenseTotal }
        let prevETotal = previous.reduce(0) { $0 + $1.displayExpenseTotal }
        let iTotal = current.reduce(0) { $0 + $1.displayIncomeTotal }
        let prevITotal = previous.reduce(0) { $0 + $1.displayIncomeTotal }

        expenseTotal        = eTotal
        expenseCount        = current.reduce(0) { $0 + $1.expenseTransactionCount }
        hasPrevExpenseData  = !previous.isEmpty && (prevETotal > 0 || previous.contains { !$0.expenseCategoryTotals.isEmpty })
        expensePeriodDiff   = eTotal - prevETotal
        expenseDailyAverage = (eTotal > 0 && periodType.showsDailyAverage) ? eTotal / max(1, dateRange.daysInPeriod) : 0
        expenseCategoryItems = AnalysisSnapshotBreakdownAggregator.categorySummaries(
            current: current, previous: previous,
            pick: { $0.expenseCategoryTotals }, categoryType: "支出", categories: categories
        )

        incomeTotal        = iTotal
        incomeCount        = current.reduce(0) { $0 + $1.incomeTransactionCount }
        hasPrevIncomeData  = !previous.isEmpty && (prevITotal > 0 || previous.contains { !$0.incomeCategoryTotals.isEmpty })
        incomePeriodDiff   = iTotal - prevITotal
        incomeDailyAverage = (iTotal > 0 && periodType.showsDailyAverage) ? iTotal / max(1, dateRange.daysInPeriod) : 0
        incomeCategoryItems = AnalysisSnapshotBreakdownAggregator.categorySummaries(
            current: current, previous: previous,
            pick: { $0.incomeCategoryTotals }, categoryType: "収入", categories: categories
        )

        paymentMethodItems = AnalysisSnapshotBreakdownAggregator.methodSummaries(
            current: current, previous: previous,
            pick: { $0.paymentMethodTotals },
            paymentMethods: paymentMethods, bankAccounts: bankAccounts
        )
    }

    // 指定した日付範囲に含まれる月のAnalysisMonthlySnapshotだけを返す
    // （.month/.previousMonthは1件、.yearは最大12件、.allTimeは全件が該当する）
    private func snapshotsInRange(_ range: AnalysisDateRange, from monthlySnapshots: [AnalysisMonthlySnapshot]) -> [AnalysisMonthlySnapshot] {
        let cal = Calendar.current
        return monthlySnapshots.filter { snap in
            guard let monthStart = cal.date(from: DateComponents(year: snap.year, month: snap.month, day: 1)) else { return false }
            return monthStart >= range.start && monthStart < range.end
        }
    }

    // MARK: - 資産タブ再計算

    func rebuildAsset(
        allIncomes: [IncomeData],
        allExpenses: [ExpenseData],
        allTransfers: [TransferData],
        bankAccounts: [BankAccountData],
        paymentMethods: [PaymentMethodSettingData],
        creditCardNames: Set<String>,
        assetReflectionTiming: CreditCardAssetReflectionTiming,
        assetDateRange: AnalysisDateRange,
        analysisMonthlySnapshots: [AnalysisMonthlySnapshot]
    ) {
        // summaries/paymentMethodSummaries/periodBalance（口座別内訳・期間合計）は
        // 引き続き生データベース。全口座合算の総資産（数値）だけスナップショットベースで計算する
        // （AnalysisSnapshotは口座単位の粒度を持たないため）。
        // 資産推移グラフ本体は AssetGraphCacheData のキャッシュ方式（AssetTrendCacheCardView）に
        // 置き換え済みで、ここでは一切計算しない（「更新」ボタンを押した時だけ再計算される）。
        let calc = BankAccountBalanceCalculator(
            bankAccounts: bankAccounts,
            allIncomeData: allIncomes,
            allExpenseData: allExpenses,
            allTransferData: allTransfers,
            creditCardNames: creditCardNames,
            assetReflectionTiming: assetReflectionTiming
        )
        let snapshotCalc = AssetSnapshotCalculator(
            monthlySnapshots: analysisMonthlySnapshots,
            assetReflectionTiming: assetReflectionTiming
        )

        let bal       = calc.periodBalance(in: assetDateRange)
        periodIncome  = bal.income
        periodExpense = bal.expense
        bankSummaries = calc.summaries(for: assetDateRange)

        // 内訳リスト（支払い方法別残高カード）・PM初期残高オフセットとも「資産に含める」(isAsset)
        // だけで判定する（総資産・資産推移・分析>資産の内訳表示は全て同じisAsset基準に統一）。
        let methodAssets = paymentMethods.filter {
            $0.isAsset && $0.isActive && !$0.isLocked
                && $0.type != PaymentMethodType.creditCard.rawValue
        }
        paymentMethodSummaries = calc.paymentMethodSummaries(for: methodAssets, upTo: assetDateRange.end)

        // PM初期残高オフセット（income/expenseエントリ未作成のものを field から加算）
        let pmInitialOffset = methodAssets
            .filter { $0.assetInitialBalanceIncomeId == nil && $0.assetInitialBalanceExpenseId == nil }
            .reduce(0) { $0 + Int($1.assetInitialBalance ?? 0) }

        // 総資産 = income - expense（CC 反映タイミング考慮）+ PM初期残高オフセット
        totalAssets = snapshotCalc.totalAssets(upTo: assetDateRange.end, pmInitialOffset: pmInitialOffset)
    }

    // MARK: - カテゴリ集計ヘルパー

    private func buildCategoryItems(
        period: [(category: String, amount: Int)],
        prev: [(category: String, amount: Int)],
        categoryType: String,
        categories: [CategoryData]
    ) -> [AnalysisCategorySummary] {
        var totals: [String: Int] = [:]
        for item in period { totals[item.category, default: 0] += item.amount }
        var prevTotals: [String: Int] = [:]
        for item in prev { prevTotals[item.category, default: 0] += item.amount }

        let positives    = totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let displayTotal = positives.reduce(0) { $0 + $1.value }
        guard displayTotal > 0 else { return [] }

        return positives.compactMap { name, amount in
            let pct = Double(amount) / Double(displayTotal) * 100
            guard Int(pct) >= 1 else { return nil }
            return AnalysisCategorySummary(
                id: name, categoryName: name,
                color: categoryColor(for: name, type: categoryType, categories: categories),
                totalAmount: amount, percentage: pct,
                monthOverMonthDiff: prevTotals[name].map { amount - $0 }
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
}
