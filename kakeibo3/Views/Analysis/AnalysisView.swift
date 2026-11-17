import SwiftUI

struct AnalysisView: View {

    private let analysisSegmentTopPadding: CGFloat = SegmentBarLayout.standard.topPadding
    private let analysisSegmentWidth: CGFloat = 320

    @Binding var analysisJumpTarget: AnalysisJumpTarget?
    let resetTrigger: Int

    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var allExpenseData: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var incomeDataObserver = IncomeDataSync.observer()
    private var allIncomeData: [IncomeData] { incomeDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allPaymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var transferDataObserver = TransferDataSync.observer()
    private var allTransferDataRaw: [TransferData] { transferDataObserver.items }
    // 総資産・資産推移グラフ・カテゴリー/方法別内訳用。行数は月数ぶんなので取引が増えても軽い
    @StateObject private var analysisMonthlySnapshotObserver = AnalysisMonthlySnapshotSync.observer()
    private var allAnalysisMonthlySnapshots: [AnalysisMonthlySnapshot] { analysisMonthlySnapshotObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @StateObject private var vm = AnalysisViewModel()

    // MARK: - 複数帳簿
    //
    // 収入・支出・分析スナップショット・カテゴリー・支払い方法・口座・振替は
    // すべて選択中の帳簿だけに絞り込む（帳簿は「ほぼ別アプリ」として完全分離する）。

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var bookScopedExpenseData: [ExpenseData] {
        allExpenseData.filter { $0.bookId == currentBookId }
    }

    private var bookScopedIncomeData: [IncomeData] {
        allIncomeData.filter { $0.bookId == currentBookId }
    }

    private var bookScopedAnalysisMonthlySnapshots: [AnalysisMonthlySnapshot] {
        allAnalysisMonthlySnapshots.filter { $0.bookId == currentBookId }
    }

    private var categoryDataList: [CategoryData] {
        categoryDataListRaw.filter { $0.bookId == currentBookId }
    }

    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }

    private var allPaymentMethods: [PaymentMethodSettingData] {
        allPaymentMethodsRaw.filter { $0.bookId == currentBookId }
    }

    private var allTransferData: [TransferData] {
        allTransferDataRaw.filter { $0.bookId == currentBookId }
    }

    @State private var selectedSegment: AnalysisSegmentType

    init(analysisJumpTarget: Binding<AnalysisJumpTarget?> = .constant(nil), resetTrigger: Int = 0) {
        self._analysisJumpTarget = analysisJumpTarget
        self.resetTrigger = resetTrigger
        let stored = UserDefaults.standard.string(forKey: "analysisSegmentOrder") ?? ""
        let parsed = stored.split(separator: ",").compactMap { AnalysisSegmentType(rawValue: String($0)) }
        let initial = (parsed.isEmpty ? AnalysisSegmentType.allCases : parsed).first ?? .expense
        self._selectedSegment = State(initialValue: initial)
    }

    @AppStorage("analysisSegmentOrder") private var storedSegmentOrder: String = ""
    @AppStorage(CreditCardAssetReflectionTiming.storageKey)
    private var storedTimingString: String = CreditCardAssetReflectionTiming.defaultValue.rawValue
    @AppStorage(AppColors.themeColorStorageKey)
    private var themeHex: String = AppColors.defaultThemeHex
    @AppStorage(AccountingMonthSettings.startDayStorageKey)
    private var accountingMonthStartDay: Int = AccountingMonthSettings.startDayDefaultValue
    @AppStorage(WeekendHolidayAdjustment.storageKey)
    private var accountingMonthAdjustment: String = WeekendHolidayAdjustment.defaultValue.rawValue
    @AppStorage(AccountingMonthLabelBasis.storageKey)
    private var accountingMonthLabelBasis: String = AccountingMonthLabelBasis.defaultValue.rawValue

    @State private var selectedDate: Date = Date()
    @State private var selectedPeriodType: AnalysisPeriodType = .month
    @State private var customStartDate: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var customEndDate: Date = Date()
    @State private var isShowingCustomPeriodSheet = false
    @State private var isShowingMonthPicker: Bool = false
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var showsMonthOverMonth: Bool = false
    @State private var expenseChartAngle: Double? = nil
    @State private var incomeChartAngle: Double? = nil

    // MARK: - 分析「集計対象」フィルター（支出/収入それぞれ、帳簿ごとに永続化）

    @State private var expenseCategoryFilter: Set<String>? = nil
    @State private var incomeCategoryFilter: Set<String>? = nil
    @State private var isShowingExpenseCategoryFilterSheet = false
    @State private var isShowingIncomeCategoryFilterSheet = false

    var body: some View {
        withCategoryFilterSheets(withChangeHandlersGroup2(withChangeHandlersGroup1(mainContent)))
    }

    private func loadCategoryFilters() {
        guard let bookId = currentBookId else {
            expenseCategoryFilter = nil
            incomeCategoryFilter = nil
            return
        }
        expenseCategoryFilter = AnalysisCategoryFilterSettings.load(bookId: bookId, categoryType: "支出")
        incomeCategoryFilter = AnalysisCategoryFilterSettings.load(bookId: bookId, categoryType: "収入")
    }

    private func filterButtonTitle(for filter: Set<String>?) -> String {
        guard let filter, !filter.isEmpty else { return "集計対象" }
        return "集計対象 \(filter.count)"
    }

    @ViewBuilder
    private func withCategoryFilterSheets<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $isShowingExpenseCategoryFilterSheet) {
                AnalysisCategoryFilterSheetView(
                    categoryType: "支出",
                    categories: categoryDataList.filter { $0.type == "支出" },
                    initialSelection: expenseCategoryFilter
                ) { newSelection in
                    expenseCategoryFilter = newSelection
                    if let bookId = currentBookId {
                        AnalysisCategoryFilterSettings.save(newSelection, bookId: bookId, categoryType: "支出")
                    }
                }
            }
            .sheet(isPresented: $isShowingIncomeCategoryFilterSheet) {
                AnalysisCategoryFilterSheetView(
                    categoryType: "収入",
                    categories: categoryDataList.filter { $0.type == "収入" },
                    initialSelection: incomeCategoryFilter
                ) { newSelection in
                    incomeCategoryFilter = newSelection
                    if let bookId = currentBookId {
                        AnalysisCategoryFilterSettings.save(newSelection, bookId: bookId, categoryType: "収入")
                    }
                }
            }
    }

    private var mainContent: some View {
        AppScreenContainer {
            analysisContent
                .sheet(isPresented: $isShowingCustomPeriodSheet) {
                    CustomPeriodSettingView(
                        initialStartDate: customStartDate,
                        initialEndDate: customEndDate
                    ) { start, end in
                        selectedPeriodType = .custom
                        customStartDate = start
                        customEndDate = end
                    }
                }
                .sheet(isPresented: $isShowingMonthPicker) {
                    // YearMonthPickerViewはラベル年月を選ばせるが、確定時にラベル→anchorへ
                    // 逆引きし、selectedDateにはその会計期間の実際の開始日（actualStartDate）を
                    // 入れる（暦月の1日を入れると、月の開始日設定次第ではrange(containing:)で
                    // 別の会計期間に解決されてしまうため）。
                    YearMonthPickerView(year: $pickerYear, month: $pickerMonth) {
                        let anchor = AccountingMonthCalculator.anchor(forLabelYear: pickerYear, labelMonth: pickerMonth)
                        if let range = AccountingMonthCalculator.range(anchorYear: anchor.year, anchorMonth: anchor.month) {
                            selectedDate = range.actualStartDate
                        }
                    }
                }
        } headerOverlay: {
            SegmentView(selectedType: $selectedSegment, orderedSegments: orderedSegments, width: analysisSegmentWidth)
                .padding(.top, analysisSegmentTopPadding)
                .frame(height: AppLayout.headerHeight, alignment: .top)
        }
        .onAppear {
            loadCategoryFilters()
            if let target = analysisJumpTarget {
                applyJumpTarget(target)
            } else if let first = orderedSegments.first {
                selectedSegment = first
            }
            clearChartAngles()
            rebuildAll()
        }
        .onChange(of: analysisJumpTarget) { _, newTarget in
            if let target = newTarget { applyJumpTarget(target) }
        }
    }

    // MARK: - .onChange 修飾子チェーン対策
    //
    // body に .onChange などの修飾子を大量に直接チェーンすると、1つの巨大なModifiedContent型になり、
    // コンパイラの型推論が現実的な時間で終わらなくなる（OtherView.swiftのwithSheetsGroupNと同じ理由）。
    // 数個ずつグループ化し、各グループの戻り値を`some View`にすることで型の境界を作る。

    @ViewBuilder
    private func withChangeHandlersGroup1<V: View>(_ content: V) -> some View {
        content
            // 期間・データ変更時のみ再計算（グラフ操作・スクロール中は呼ばれない）
            .onChange(of: selectedDate)          { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: selectedPeriodType)    { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: customStartDate)       { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: customEndDate)         { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: expenseVersionKey)     { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: incomeVersionKey)      { _, _ in clearChartAngles(); rebuildAll() }
    }

    @ViewBuilder
    private func withChangeHandlersGroup2<V: View>(_ content: V) -> some View {
        content
            .onChange(of: allTransferData.count)   { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: allBankAccounts.count)   { _, _ in rebuildAll() }
            .onChange(of: allPaymentMethods.count) { _, _ in rebuildAll() }
            .onChange(of: lockVersionKey)          { _, _ in rebuildAll() }
            .onChange(of: storedTimingString)      { _, _ in rebuildAll() }
            .onChange(of: accountingMonthStartDay) { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: accountingMonthAdjustment) { _, _ in clearChartAngles(); rebuildAll() }
            .onChange(of: accountingMonthLabelBasis) { _, _ in rebuildAll() }
            .onChange(of: selectedBookIdString)      { _, _ in loadCategoryFilters(); clearChartAngles(); rebuildAll() }
            .onChange(of: expenseCategoryFilter)     { _, _ in rebuildAll() }
            .onChange(of: incomeCategoryFilter)      { _, _ in rebuildAll() }
            .onChange(of: resetTrigger) { _, _ in
                resetToInitialState()
            }
    }

    // MARK: - 再計算（データ変更・月変更時のみ呼ぶ）

    private func rebuildAll() {
        let creditCards = Set(allPaymentMethods
            .filter { $0.type == PaymentMethodType.creditCard.rawValue }
            .map { $0.methodName })
        let visibleBanks = allBankAccounts.filter { $0.isActive && $0.isAsset && !$0.isLocked }
        let timing = CreditCardAssetReflectionTiming(rawValue: storedTimingString) ?? .usageDate
        // 会計月開始日がデフォルト（1日・調整なし）でなければ、.month/.previousMonthも
        // ライブ集計パスに流す（AnalysisMonthlySnapshotの暦月ショートカットが使えないため）。
        let usesLiveAggregation = accountingMonthStartDay != AccountingMonthSettings.startDayDefaultValue
            || accountingMonthAdjustment != WeekendHolidayAdjustment.defaultValue.rawValue

        vm.rebuildExpenseIncome(
            allExpenses: lockVisibleExpenses,
            allIncomes: lockVisibleIncomes,
            allTransfers: allTransferData,
            categories: categoryDataList,
            paymentMethods: allPaymentMethods,
            bankAccounts: allBankAccounts,
            dateRange: analysisDateRange,
            prevDateRange: prevDateRange,
            periodType: selectedPeriodType,
            monthlySnapshots: bookScopedAnalysisMonthlySnapshots,
            usesLiveAggregation: usesLiveAggregation,
            expenseCategoryFilter: expenseCategoryFilter,
            incomeCategoryFilter: incomeCategoryFilter
        )
        vm.rebuildAsset(
            allIncomes: assetTotalIncomes,
            allExpenses: assetTotalExpenses,
            allTransfers: allTransferData,
            bankAccounts: visibleBanks,
            paymentMethods: allPaymentMethods,
            creditCardNames: creditCards,
            assetReflectionTiming: timing,
            assetDateRange: assetDateRange,
            analysisMonthlySnapshots: bookScopedAnalysisMonthlySnapshots
        )
    }

    // MARK: - ロック中の口座・支払い方法に紐づく取引を分析から除外する
    //
    // クレジットカードは「カード自身」に加えて「紐づく引き落とし口座」のロックも連動して見る。
    // 判定ロジック本体は DowngradeLockService に共通化（カレンダーと同じ基準）。
    // 支出/収入/決済タブの内訳（カテゴリー・方法別）表示はこれだけで判定する。
    // 「資産に含める」「分析に表示」はどちらもここでは使わない
    // （前者は総資産・資産推移・月収支だけの条件、後者は分析>資産の内訳リストの表示/非表示だけの条件）。

    private var lockVisibleExpenses: [ExpenseData] {
        DowngradeLockService.visibleExpenses(bookScopedExpenseData, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods)
    }

    private var lockVisibleIncomes: [IncomeData] {
        DowngradeLockService.visibleIncomes(bookScopedIncomeData, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods)
    }

    // MARK: - 総資産・資産推移・月収支専用のフィルタ（「資産に含める」＝isAssetだけを条件にする）

    private var assetTotalExpenses: [ExpenseData] {
        DowngradeLockService.assetTotalExpenses(bookScopedExpenseData, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods)
    }

    private var assetTotalIncomes: [IncomeData] {
        DowngradeLockService.assetTotalIncomes(bookScopedIncomeData, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods)
    }

    // MARK: - Content Switch（横スワイプでタブ切り替え）

    private var analysisContent: some View {
        TabView(selection: $selectedSegment) {
            ForEach(orderedSegments, id: \.self) { segment in
                analysisContent(for: segment)
                    .tag(segment)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    @ViewBuilder
    private func analysisContent(for segment: AnalysisSegmentType) -> some View {
        switch segment {
        case .expense:
            analysisScrollView(
                summaryTitle: summaryTitle(for: "支出"),
                chartTitle: "支出割合",
                emptyMessage: "データがありません",
                total: vm.expenseTotal,
                count: vm.expenseCount,
                hasPrev: vm.hasPrevExpenseData,
                periodDiff: vm.expensePeriodDiff,
                dailyAvg: vm.expenseDailyAverage,
                items: vm.expenseCategoryItems,
                chartAngle: $expenseChartAngle,
                mode: .expenseCategory,
                filterButtonTitle: filterButtonTitle(for: expenseCategoryFilter),
                onFilterTap: { isShowingExpenseCategoryFilterSheet = true }
            )
        case .income:
            analysisScrollView(
                summaryTitle: summaryTitle(for: "収入"),
                chartTitle: "収入割合",
                emptyMessage: "データがありません",
                total: vm.incomeTotal,
                count: vm.incomeCount,
                hasPrev: vm.hasPrevIncomeData,
                periodDiff: vm.incomePeriodDiff,
                dailyAvg: vm.incomeDailyAverage,
                items: vm.incomeCategoryItems,
                chartAngle: $incomeChartAngle,
                mode: .incomeCategory,
                filterButtonTitle: filterButtonTitle(for: incomeCategoryFilter),
                onFilterTap: { isShowingIncomeCategoryFilterSheet = true }
            )
        case .payment:
            paymentAnalysisView
        case .asset:
            assetAnalysisScrollView
        }
    }

    // MARK: - Period Navigator

    private var periodNavigatorView: some View {
        HStack(spacing: 8) {
            if showsNavigationArrows {
                Button { navigatePrevious() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            if selectedPeriodType == .month || selectedPeriodType == .previousMonth {
                Text(currentPeriodLabelText)
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                    .onTapGesture {
                        if let label = currentPeriodAccountingLabel {
                            pickerYear = label.year
                            pickerMonth = label.month
                        } else {
                            pickerYear  = Calendar.current.component(.year,  from: selectedDate)
                            pickerMonth = Calendar.current.component(.month, from: selectedDate)
                        }
                        isShowingMonthPicker = true
                    }
            } else {
                Text(currentPeriodLabelText)
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
            }

            if showsNavigationArrows {
                Button { navigateNext() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var showsNavigationArrows: Bool {
        switch selectedPeriodType {
        case .month, .previousMonth, .year: return true
        case .allTime, .custom: return false
        }
    }

    private func navigatePrevious() {
        switch selectedPeriodType {
        case .month, .previousMonth: stepAccountingMonth(by: -1)
        case .year:                  selectedDate = Calendar.current.date(byAdding: .year, value: -1, to: selectedDate) ?? selectedDate
        case .allTime, .custom:      break
        }
    }

    private func navigateNext() {
        switch selectedPeriodType {
        case .month, .previousMonth: stepAccountingMonth(by: 1)
        case .year:                  selectedDate = Calendar.current.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
        case .allTime, .custom:      break
        }
    }

    // selectedDateの暦月をそのままanchorとして使うと、月の開始日設定次第では
    // selectedDateが実際に属する会計期間とズレることがあるため、range(containing:)で
    // 現在の会計期間を求めてから±1ヶ月進め、新しいanchorの実際の開始日にジャンプする。
    private func stepAccountingMonth(by offset: Int) {
        guard let currentRange = AccountingMonthCalculator.range(containing: selectedDate) else { return }
        let nextAnchor = AccountingMonthCalculator.adjacentAnchor(
            year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: offset
        )
        guard let nextRange = AccountingMonthCalculator.range(anchorYear: nextAnchor.year, anchorMonth: nextAnchor.month)
        else { return }
        selectedDate = nextRange.actualStartDate
    }

    // .month/.previousMonthの表示用ラベル年月（月の開始日・年月表示設定を反映済み）。
    // selectedDateの暦月をそのままanchorとして使うと、月の開始日設定次第では実際に属する
    // 会計期間とズレることがあるため、range(containing:)で現在の会計期間を求める
    // （ナビゲーションはanchor基準、ラベルは派生値の原則）。
    private var currentPeriodAccountingLabel: (year: Int, month: Int)? {
        guard let currentRange = AccountingMonthCalculator.range(containing: selectedDate) else { return nil }
        switch selectedPeriodType {
        case .month:
            return (currentRange.labelYear, currentRange.labelMonth)
        case .previousMonth:
            let prevAnchor = AccountingMonthCalculator.adjacentAnchor(
                year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: -1
            )
            return AccountingMonthCalculator.range(anchorYear: prevAnchor.year, anchorMonth: prevAnchor.month).map { ($0.labelYear, $0.labelMonth) }
        default:
            return nil
        }
    }

    // 静的 DateFormatter を使用（body 描画のたびに生成しない）
    private var currentPeriodLabelText: String {
        switch selectedPeriodType {
        case .month, .previousMonth:
            guard let label = currentPeriodAccountingLabel else {
                return AnalysisViewModel.monthYearFormatter.string(from: analysisDateRange.start)
            }
            return "\(label.year)年\(label.month)月"
        case .year:
            return AnalysisViewModel.yearFormatter.string(from: analysisDateRange.start)
        case .allTime:
            return "全期間"
        case .custom:
            let fmt = AnalysisViewModel.shortDateFormatter
            return "\(fmt.string(from: customStartDate))〜\(fmt.string(from: customEndDate))"
        }
    }

    // MARK: - Summary Title

    private func summaryTitle(for category: String) -> String {
        if selectedPeriodType == .custom {
            let fmt = AnalysisViewModel.shortDateFormatter
            return "\(fmt.string(from: customStartDate))〜\(fmt.string(from: customEndDate))の\(category)"
        }
        return selectedPeriodType.summaryTitle(for: category)
    }

    // MARK: - Shared Scroll View

    private func analysisScrollView(
        summaryTitle: String,
        chartTitle: String,
        emptyMessage: String,
        total: Int,
        count: Int,
        hasPrev: Bool,
        periodDiff: Int,
        dailyAvg: Int,
        items: [AnalysisCategorySummary],
        chartAngle: Binding<Double?>,
        mode: AnalysisDetailMode,
        filterButtonTitle: String? = nil,
        onFilterTap: (() -> Void)? = nil
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                periodNavigatorView.padding(.bottom, 12)
                periodSelector.padding(.bottom, 16)
                if hasLockedAnalysisData {
                    lockedDataNoticeBanner
                }
                AnalysisSummaryCard(
                    title: summaryTitle,
                    totalAmount: total,
                    itemCount: count,
                    hasPrevMonthData: hasPrev,
                    monthOverMonthDiff: periodDiff,
                    comparisonLabel: selectedPeriodType.comparisonLabel,
                    dailyAverage: dailyAvg,
                    filterButtonTitle: filterButtonTitle,
                    onFilterTap: onFilterTap
                )
                .padding(.bottom, 24)
                AnalysisDonutChartCard(title: chartTitle, items: items, selectedAngle: chartAngle)
                    .padding(.bottom, 24)
                AnalysisCategoryListCard(
                    items: items,
                    showsMonthOverMonth: $showsMonthOverMonth,
                    comparisonLabel: selectedPeriodType.comparisonLabel,
                    emptyMessage: emptyMessage,
                    mode: mode,
                    dateRange: analysisDateRange
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, AppLayout.bottomNavigationHeight + 72)
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        AnalysisPeriodSelectorView(
            selectedPeriod: $selectedPeriodType,
            onCustomTap: { isShowingCustomPeriodSheet = true }
        )
    }

    // MARK: - Date Range（O(1) の計算のみ）

    private var analysisDateRange: AnalysisDateRange {
        AnalysisDateRangeCalculator.current(
            for: selectedPeriodType, referenceDate: selectedDate,
            customStart: customStartDate, customEnd: customEndDate
        )
    }

    private var prevDateRange: AnalysisDateRange {
        AnalysisDateRangeCalculator.previous(
            for: selectedPeriodType, referenceDate: selectedDate,
            customStart: customStartDate, customEnd: customEndDate
        )
    }

    private var assetDateRange: AnalysisDateRange {
        AnalysisDateRangeCalculator.current(for: .month, referenceDate: selectedDate)
    }

    // 資産タブは常に.month相当として扱う。selectedDateの暦月をそのままanchorとして使うと
    // 実際に属する会計期間とズレることがあるため、range(containing:)で求める。
    private var assetPeriodAccountingLabel: (year: Int, month: Int)? {
        AccountingMonthCalculator.range(containing: selectedDate).map { ($0.labelYear, $0.labelMonth) }
    }

    private var assetPeriodLabelText: String {
        guard let label = assetPeriodAccountingLabel else {
            return AnalysisViewModel.monthYearFormatter.string(from: selectedDate)
        }
        return "\(label.year)年\(label.month)月"
    }

    // MARK: - Helpers

    // body 描画のたびに評価されるが、O(N) のため許容範囲。
    // onChange の変化検知にのみ使用し、集計には使わない。
    private var expenseVersionKey: String {
        "\(bookScopedExpenseData.count)-\(bookScopedExpenseData.reduce(0) { $0 + $1.amount })"
    }
    private var incomeVersionKey: String {
        "\(bookScopedIncomeData.count)-\(bookScopedIncomeData.reduce(0) { $0 + $1.amount })"
    }
    // 口座/支払い方法のロック状態、または「資産に含める」（isAsset）が変わった時に
    // 分析を再計算するための検知キー。これらはExpenseData/IncomeData自体を変更しないため、
    // expenseVersionKey/incomeVersionKeyだけでは変化を検知できない。
    private var lockVersionKey: String {
        let bankPart = allBankAccounts.map {
            "\($0.isLocked ? "1" : "0")\($0.isAsset ? "1" : "0")-\($0.colorHex ?? "")"
        }.joined(separator: "|")
        let paymentPart = allPaymentMethods.map {
            "\($0.isLocked ? "1" : "0")\($0.isAsset ? "1" : "0")-\($0.colorHex ?? "")"
        }.joined(separator: "|")
        return bankPart + "|" + paymentPart
    }

    private var orderedSegments: [AnalysisSegmentType] {
        let raw    = storedSegmentOrder.split(separator: ",").map(String.init)
        let parsed = raw.compactMap { AnalysisSegmentType(rawValue: $0) }
        let missing = AnalysisSegmentType.allCases.filter { !parsed.contains($0) }
        return parsed.isEmpty ? AnalysisSegmentType.allCases : parsed + missing
    }

    private func clearChartAngles() {
        expenseChartAngle = nil
        incomeChartAngle  = nil
    }

    // MARK: - タブ再タップ時の初期表示リセット

    private func resetToInitialState() {
        isShowingCustomPeriodSheet = false
        isShowingMonthPicker = false
        selectedDate = Date()
        selectedPeriodType = .month
        selectedSegment = orderedSegments.first ?? .expense
        clearChartAngles()
        rebuildAll()
    }

    private func applyJumpTarget(_ target: AnalysisJumpTarget) {
        selectedSegment    = target.segment
        selectedDate       = target.date
        selectedPeriodType = .month
        analysisJumpTarget = nil
        clearChartAngles()
        rebuildAll()
    }

    // MARK: - Payment View

    private var paymentAnalysisView: some View {
        ScrollView {
            VStack(spacing: 0) {
                periodNavigatorView.padding(.bottom, 12)
                periodSelector.padding(.bottom, 16)
                if hasLockedAnalysisData {
                    lockedDataNoticeBanner
                }
                PaymentAnalysisView(
                    allExpenses: lockVisibleExpenses,
                    items: vm.paymentMethodItems,
                    comparisonLabel: selectedPeriodType.comparisonLabel,
                    dateRange: analysisDateRange,
                    showsCreditCardDue: selectedPeriodType == .month
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, AppLayout.bottomNavigationHeight + 72)
        }
    }

    // MARK: - Asset View

    private var assetPeriodNavigatorView: some View {
        HStack(spacing: 8) {
            Button {
                stepAccountingMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Text(assetPeriodLabelText)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.8))
                .onTapGesture {
                    if let label = assetPeriodAccountingLabel {
                        pickerYear = label.year
                        pickerMonth = label.month
                    } else {
                        pickerYear  = Calendar.current.component(.year,  from: selectedDate)
                        pickerMonth = Calendar.current.component(.month, from: selectedDate)
                    }
                    isShowingMonthPicker = true
                }

            Button {
                stepAccountingMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // ロック中の口座/支払い方法が1件でもあれば、資産分析が一部除外されていることを案内する
    private var hasLockedAnalysisData: Bool {
        allBankAccounts.contains { $0.isActive && $0.isLocked }
            || allPaymentMethods.contains { $0.isActive && $0.isLocked }
    }

    private var lockedDataNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.4))
            Text("一部のプレミアムデータは分析対象外です。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 12)
    }

    private var assetAnalysisScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                assetPeriodNavigatorView.padding(.bottom, 16)
                if hasLockedAnalysisData {
                    lockedDataNoticeBanner
                }
                AssetAnalysisView(
                    totalAssets: vm.totalAssets,
                    periodIncome: vm.periodIncome,
                    periodExpense: vm.periodExpense,
                    bankSummaries: vm.bankSummaries,
                    paymentMethodSummaries: vm.paymentMethodSummaries,
                    dateRange: assetDateRange
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, AppLayout.bottomNavigationHeight + 72)
        }
    }
}
