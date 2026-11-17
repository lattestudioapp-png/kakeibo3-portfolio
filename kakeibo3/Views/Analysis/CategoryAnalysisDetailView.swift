import SwiftUI
import Charts

// MARK: - 詳細画面モード

enum AnalysisDetailMode {
    case expenseCategory
    case incomeCategory
    case paymentMethod
}

// MARK: - 月別集計点（カテゴリ推移グラフ用）

struct CategoryMonthlyPoint: Identifiable {
    let id: Date
    let month: Date
    let amount: Int
}

// MARK: - カテゴリ・支払い方法 分析詳細画面

struct CategoryAnalysisDetailView: View {
    let item: AnalysisCategorySummary
    let mode: AnalysisDetailMode
    let dateRange: AnalysisDateRange
    let comparisonLabel: String

    @Environment(\.dismiss) private var dismiss

    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var allExpenses: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var incomeDataObserver = IncomeDataSync.observer()
    private var allIncomes: [IncomeData] { incomeDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var allCategoriesRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allPaymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var allCategories: [CategoryData] {
        allCategoriesRaw.filter { $0.bookId == currentBookId }
    }
    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var allPaymentMethods: [PaymentMethodSettingData] {
        allPaymentMethodsRaw.filter { $0.bookId == currentBookId }
    }

    // ロック中の口座/支払い方法に紐づく取引を除いたリスト（分析サマリーと集計を一致させる）
    private var visibleExpenses: [ExpenseData] {
        DowngradeLockService.visibleExpenses(
            allExpenses.filter { $0.bookId == currentBookId }, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods
        )
    }
    private var visibleIncomes: [IncomeData] {
        DowngradeLockService.visibleIncomes(
            allIncomes.filter { $0.bookId == currentBookId }, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods
        )
    }

    // スワイプ削除
    @State private var openSwipeItemID: UUID? = nil
    @State private var editingItem: TransactionListItem? = nil

    // カテゴリモード用キャッシュ（onAppear のみ更新）
    @State private var thisMonthTotal: Int = 0
    @State private var thisMonthCount: Int = 0
    @State private var categoryMonthlyPoints: [CategoryMonthlyPoint] = []
    @State private var cachedItems: [TransactionListItem] = []

    // 支払い方法モード用キャッシュ
    @State private var paymentCategoryItems: [AnalysisCategorySummary] = []

    // MARK: - 支払い方法モード（今月リスト）— live computed

    private var filteredExpenses: [ExpenseData] {
        guard mode == .paymentMethod else { return [] }
        return visibleExpenses
            .filter { $0.date >= dateRange.start && $0.date < dateRange.end && $0.paymentMethod == item.categoryName }
            .sorted { $0.date > $1.date }
    }

    private var liveTotal: Int      { filteredExpenses.reduce(0) { $0 + $1.amount } }
    private var liveCount: Int      { filteredExpenses.count }
    private var isPaymentEmpty: Bool { liveCount == 0 }

    // 件数だけでなく、既存項目の編集（写真追加など）も検知できるように
    // TransactionChangeSignature を使う。
    private var dataToken: String {
        TransactionChangeSignature.make(incomeDataList: allIncomes, expenseDataList: allExpenses)
    }

    // MARK: - Body

    var body: some View {
        AnalysisDetailScreenContainer(
            title: item.categoryName,
            onClose: { dismiss() }
        ) {
            VStack(spacing: 20) {
                switch mode {
                case .expenseCategory:
                    categorySummaryCard(label: "今月の支出")
                    if !categoryMonthlyPoints.isEmpty { categoryTrendChartCard(label: "支出推移") }
                    AnalysisItemListCard(
                        items: cachedItems,
                        openItemID: $openSwipeItemID,
                        onTap: { editingItem = $0 },
                        onDelete: handleDelete
                    )

                case .incomeCategory:
                    categorySummaryCard(label: "今月の収入")
                    if !categoryMonthlyPoints.isEmpty { categoryTrendChartCard(label: "収入推移") }
                    AnalysisItemListCard(
                        items: cachedItems,
                        openItemID: $openSwipeItemID,
                        onTap: { editingItem = $0 },
                        onDelete: handleDelete
                    )

                case .paymentMethod:
                    paymentSummaryCard
                    if !paymentCategoryItems.isEmpty { paymentCategoryCard }
                    AnalysisItemListCard(
                        items: cachedItems,
                        openItemID: $openSwipeItemID,
                        onTap: { editingItem = $0 },
                        onDelete: handleDelete
                    )
                }
            }
        }
        .onAppear { buildData() }
        .onChange(of: dataToken) { _, _ in buildData() }
        .onChange(of: selectedBookIdString) { _, _ in buildData() }
        .fullScreenCover(item: $editingItem) { item in
            TransactionHistoryEditView(item: item, onClose: { editingItem = nil })
        }
    }

    // MARK: - カテゴリモード: 今月合計カード

    private func categorySummaryCard(label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.45))
            Text(formatAnalysisAmount(thisMonthTotal))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("\(thisMonthCount)件")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - カテゴリモード: 月別推移グラフカード

    private func categoryTrendChartCard(label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.65))

            Chart(categoryMonthlyPoints) { point in
                BarMark(
                    x: .value("月", point.month, unit: .month),
                    y: .value("金額", point.amount)
                )
                .foregroundStyle(item.color.opacity(0.75))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let cal   = Calendar.current
                            let month = cal.component(.month, from: date)
                            let year  = cal.component(.year,  from: date)
                            VStack(spacing: 1) {
                                if month == 1 {
                                    Text("\(year)")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.black.opacity(0.45))
                                }
                                Text("\(month)月")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.black.opacity(0.38))
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(shortAmountLabel(v))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.black.opacity(0.38))
                        }
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - 支払い方法モード: 今月の支出カード

    private var paymentSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今月の支出")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.45))
            Text(isPaymentEmpty ? "0円" : formatAnalysisAmount(liveTotal))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(isPaymentEmpty ? "0件" : "\(liveCount)件")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - 支払い方法モード: カテゴリ別支出グラフカード

    private var paymentCategoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支出グラフ")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.65))
            VStack(spacing: 10) {
                ForEach(paymentCategoryItems) { catItem in
                    paymentCategoryRow(catItem)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    private func paymentCategoryRow(_ catItem: AnalysisCategorySummary) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(catItem.color).frame(width: 10, height: 10)
                Text(catItem.categoryName)
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", catItem.percentage))
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.40))
                    .frame(width: 36, alignment: .trailing)
                Text(formatAnalysisAmount(catItem.totalAmount))
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.06)).frame(height: 4)
                    Capsule().fill(catItem.color.opacity(0.75))
                        .frame(width: geo.size.width * min(catItem.percentage / 100, 1.0), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - 集計処理（表示時に1回だけ実行）

    private func buildData() {
        let cal = Calendar.current
        switch mode {
        case .expenseCategory:
            let matched = visibleExpenses
                .filter { $0.category == item.categoryName }
                .sorted { $0.date > $1.date }
            let inPeriod = matched.filter { $0.date >= dateRange.start && $0.date < dateRange.end }
            thisMonthTotal = inPeriod.reduce(0) { $0 + $1.amount }
            thisMonthCount = inPeriod.count
            cachedItems = matched.map { TransactionListItem.expense(from: $0) }
            categoryMonthlyPoints = buildMonthlyPoints(
                from: matched.map { ($0.date, $0.amount) }, cal: cal
            )

        case .incomeCategory:
            let matched = visibleIncomes
                .filter { $0.category == item.categoryName }
                .sorted { $0.date > $1.date }
            let inPeriod = matched.filter { $0.date >= dateRange.start && $0.date < dateRange.end }
            thisMonthTotal = inPeriod.reduce(0) { $0 + $1.amount }
            thisMonthCount = inPeriod.count
            cachedItems = matched.map { TransactionListItem.income(from: $0) }
            categoryMonthlyPoints = buildMonthlyPoints(
                from: matched.map { ($0.date, $0.amount) }, cal: cal
            )

        case .paymentMethod:
            cachedItems = filteredExpenses.map { TransactionListItem.expense(from: $0) }
            buildPaymentCategoryItems()
        }
    }

    // 過去12ヶ月の月別合計を計算
    private func buildMonthlyPoints(
        from items: [(date: Date, amount: Int)],
        cal: Calendar
    ) -> [CategoryMonthlyPoint] {
        guard let currentMonth = cal.date(from: cal.dateComponents([.year, .month], from: dateRange.start)) else { return [] }

        var months: [Date] = []
        for offset in stride(from: -11, through: 0, by: 1) {
            if let m = cal.date(byAdding: .month, value: offset, to: currentMonth) {
                months.append(m)
            }
        }

        var totals: [Date: Int] = [:]
        for item in items {
            if let monthKey = cal.date(from: cal.dateComponents([.year, .month], from: item.date)),
               months.contains(monthKey) {
                totals[monthKey, default: 0] += item.amount
            }
        }

        return months.map { month in
            CategoryMonthlyPoint(id: month, month: month, amount: totals[month] ?? 0)
        }
    }

    // 支払い方法モード用カテゴリ集計
    private func buildPaymentCategoryItems() {
        let expenses = visibleExpenses
            .filter { $0.date >= dateRange.start && $0.date < dateRange.end && $0.paymentMethod == item.categoryName }
        var totals: [String: Int] = [:]
        for e in expenses { totals[e.category, default: 0] += e.amount }
        let total = totals.values.reduce(0, +)
        guard total > 0 else { paymentCategoryItems = []; return }

        paymentCategoryItems = totals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .compactMap { name, amount in
                let pct = Double(amount) / Double(total) * 100
                guard Int(pct) >= 1 else { return nil }
                return AnalysisCategorySummary(
                    id: name, categoryName: name,
                    color: categoryColor(for: name),
                    totalAmount: amount, percentage: pct,
                    monthOverMonthDiff: nil
                )
            }
    }

    private func categoryColor(for name: String) -> Color {
        if let hex = allCategories.first(where: { $0.name == name && $0.type == "支出" })?.colorHex,
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

    // MARK: - 削除（直接削除・確認なし）

    private func handleDelete(_ listItem: TransactionListItem) {
        openSwipeItemID = nil
        let event: SnapshotEvent
        switch listItem.kind {
        case .expense:
            if let target = allExpenses.first(where: { $0.id == listItem.sourceId }) {
                ExpenseDataSync.delete(id: target.id)
            }
            event = .expenseDeleted(date: listItem.date, bookId: listItem.bookId ?? UUID())
        case .income:
            if let target = allIncomes.first(where: { $0.id == listItem.sourceId }) {
                IncomeDataSync.delete(id: target.id)
            }
            event = .incomeDeleted(date: listItem.date, bookId: listItem.bookId ?? UUID())
        case .transfer:
            event = .transferDeleted(date: listItem.date, bookId: listItem.bookId ?? UUID())
        }
        SnapshotUpdateService.handle(event)
    }

    // MARK: - フォーマット

    private func shortAmountLabel(_ value: Int) -> String {
        let absVal = Swift.abs(value)
        let sign   = value < 0 ? "-" : ""
        if absVal >= 100_000_000 { return "\(sign)\(absVal / 100_000_000)億" }
        if absVal >= 10_000      { return "\(sign)\(absVal / 10_000)万" }
        if absVal >= 1_000       { return "\(sign)\(absVal / 1_000)千" }
        return "\(value)"
    }
}
