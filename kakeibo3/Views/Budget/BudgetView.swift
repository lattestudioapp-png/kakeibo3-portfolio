import SwiftUI

struct BudgetView: View {

    let resetTrigger: Int

    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var allExpenseData: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var budgetDataObserver = BudgetDataSync.observer()
    private var allBudgetDataRaw: [BudgetData] { budgetDataObserver.items }
    @StateObject private var recurringBudgetDataObserver = RecurringBudgetDataSync.observer()
    private var allRecurringBudgetDataRaw: [RecurringBudgetData] { recurringBudgetDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allPaymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    // MARK: - 複数帳簿
    //
    // 予算・実績・カテゴリー・口座・支払い方法はすべて選択中の帳簿だけに絞り込む
    // （帳簿は「ほぼ別アプリ」として完全分離する）。

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var bookScopedExpenseData: [ExpenseData] {
        allExpenseData.filter { $0.bookId == currentBookId }
    }

    private var allBudgetData: [BudgetData] {
        allBudgetDataRaw.filter { $0.bookId == currentBookId }
    }
    private var allRecurringBudgetData: [RecurringBudgetData] {
        allRecurringBudgetDataRaw.filter { $0.bookId == currentBookId }
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

    @State private var selectedDate: Date = Date()
    @State private var showsBudgetSetting = false
    @State private var isShowingMonthPicker = false
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())

    // body 描画のたびに全支出履歴を再フィルタしないよう、月・データ変更時だけ再計算してキャッシュする
    // （以前はcomputed propertyで、bodyから複数回参照されるたびに全件filterし直していた）。
    @State private var summary = BudgetMonthSummary(
        totalBudgetAmount: 0, totalUsedAmount: 0, categorySummaries: [], unsetCategorySummaries: []
    )

    // selectedDateの暦月をそのままanchorとして使うと、月の開始日設定次第では
    // selectedDateが実際にはその1つ前の会計期間に属してしまうことがある
    // （例：開始日=10日でselectedDate=7/9の場合、7/9は6/10〜7/9の会計期間に属する）。
    // そのためrange(containing:)で「selectedDateが実際に属する会計期間」を検索して求める。
    // ラベル年月（会計月開始日設定・年月表示設定を反映した表示用の年月）はそこから導出する
    // 派生値であり、BudgetData/RecurringBudgetDataのyear/month列もこのラベルと同じ意味で
    // 保存されている。
    private var accountingRange: AccountingMonthRange? {
        AccountingMonthCalculator.range(containing: selectedDate)
    }

    private var selectedYear: Int {
        accountingRange?.labelYear ?? Calendar.current.component(.year, from: selectedDate)
    }

    private var selectedMonthNumber: Int {
        accountingRange?.labelMonth ?? Calendar.current.component(.month, from: selectedDate)
    }

    var body: some View {
        AppScreenContainer {
            budgetContent
                .sheet(isPresented: $showsBudgetSetting) {
                    BudgetSettingView(year: selectedYear, month: selectedMonthNumber)
                }
                .sheet(isPresented: $isShowingMonthPicker) {
                    // YearMonthPickerViewは「ラベル年月」を選ばせるが、内部で保持するselectedDateは
                    // 「表示ページ（暦月）」のanchorのため、確定時にラベル→anchorへ逆引きする
                    // （通常はlabel==anchorだが、年月表示設定や前倒し/後ろ倒し設定次第でズレることがある）。
                    YearMonthPickerView(year: $pickerYear, month: $pickerMonth) {
                        // selectedDateには必ずその会計期間の実際の開始日（actualStartDate）を
                        // 入れる。暦月の1日（day:1）を入れると、月の開始日設定次第では
                        // range(containing:)で別の（1つ前の）会計期間に解決されてしまうため。
                        let anchor = AccountingMonthCalculator.anchor(forLabelYear: pickerYear, labelMonth: pickerMonth)
                        if let range = AccountingMonthCalculator.range(anchorYear: anchor.year, anchorMonth: anchor.month) {
                            selectedDate = range.actualStartDate
                        }
                    }
                }
                .onAppear { rebuildSummary() }
                .onChange(of: selectedDate) { _, _ in rebuildSummary() }
                .onChange(of: expenseVersionKey) { _, _ in rebuildSummary() }
                .onChange(of: budgetVersionKey) { _, _ in rebuildSummary() }
                .onChange(of: recurringBudgetVersionKey) { _, _ in rebuildSummary() }
                .onChange(of: categoryVersionKey) { _, _ in rebuildSummary() }
                .onChange(of: lockVersionKey) { _, _ in rebuildSummary() }
                .onChange(of: selectedBookIdString) { _, _ in rebuildSummary() }
                .onChange(of: resetTrigger) { _, _ in
                    resetToInitialState()
                }
        } headerOverlay: {
            CalendarHeaderView(
                selectedDate: $selectedDate,
                onTitleTap: {
                    pickerYear = selectedYear
                    pickerMonth = selectedMonthNumber
                    isShowingMonthPicker = true
                },
                titleOverride: "\(selectedYear)年\(selectedMonthNumber)月"
            )
        }
    }

    // MARK: - 予算コンテンツ（予算設定済みの場合）

    private var budgetContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                BudgetOverviewCard(summary: summary)
                    .padding(.bottom, 24)
                BudgetCategoryListCard(
                    summary: summary,
                    onSettingTap: { showsBudgetSetting = true }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, AppLayout.bottomNavigationHeight + 72)
        }
    }

    // MARK: - 再計算（月変更・データ変更時のみ呼ぶ）

    private func rebuildSummary() {
        // ロック中の口座/支払い方法に紐づく支出を除いたリスト（選択中の帳簿ぶんのみ）
        let visibleExpenseData = DowngradeLockService.visibleExpenses(
            bookScopedExpenseData, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods
        )
        summary = BudgetSummaryService.buildMonthSummary(
            allExpenses: visibleExpenseData,
            allBudgets: allBudgetData,
            allRecurringBudgets: allRecurringBudgetData,
            allCategories: categoryDataList,
            year: selectedYear,
            month: selectedMonthNumber
        )
    }

    // MARK: - データ変更検知キー（.onChangeの変化検知にのみ使用。集計には使わない）

    private var expenseVersionKey: String {
        "\(bookScopedExpenseData.count)-\(bookScopedExpenseData.reduce(0) { $0 + $1.amount })"
    }

    private var budgetVersionKey: String {
        "\(allBudgetData.count)-\(allBudgetData.reduce(0) { $0 + $1.amount })"
    }

    // isEnabledの切り替えだけでもcount/合計が変わらないため、件数+合計ではなく状態そのものを見る
    // （RecurringBudgetDataは通常カテゴリー数ぶんしかないため、この程度のO(N)は軽い）。
    private var recurringBudgetVersionKey: String {
        allRecurringBudgetData
            .map { "\($0.categoryName)-\($0.amount)-\($0.isEnabled ? 1 : 0)" }
            .joined(separator: "|")
    }

    // カテゴリーの色・並び順の変更もsummary内の表示色に影響するため検知する
    private var categoryVersionKey: String {
        categoryDataList
            .map { "\($0.name)-\($0.colorHex)-\($0.sortOrder)" }
            .joined(separator: "|")
    }

    // 口座/支払い方法のロック状態が変わった時にも再計算する
    // （ExpenseData自体を変更しないため、expenseVersionKeyだけでは変化を検知できない）
    private var lockVersionKey: String {
        let bankPart = allBankAccounts.map { $0.isLocked ? "1" : "0" }.joined()
        let paymentPart = allPaymentMethods.map { $0.isLocked ? "1" : "0" }.joined()
        return bankPart + "|" + paymentPart
    }

    // MARK: - タブ再タップ時の初期表示リセット

    private func resetToInitialState() {
        showsBudgetSetting = false
        isShowingMonthPicker = false
        selectedDate = Date()
        rebuildSummary()
    }
}
