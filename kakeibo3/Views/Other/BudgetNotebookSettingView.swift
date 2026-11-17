import SwiftUI
import QuickLook

// MARK: - 家計簿ノート作成画面

struct BudgetNotebookSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var allExpensesRaw: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var incomeDataObserver = IncomeDataSync.observer()
    private var allIncomesRaw: [IncomeData] { incomeDataObserver.items }
    @StateObject private var budgetDataObserver = BudgetDataSync.observer()
    private var allBudgetsRaw: [BudgetData] { budgetDataObserver.items }
    @StateObject private var recurringBudgetDataObserver = RecurringBudgetDataSync.observer()
    private var allRecurringBudgetsRaw: [RecurringBudgetData] { recurringBudgetDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var allCategoriesRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allPaymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    private var allExpenses: [ExpenseData] {
        allExpensesRaw.filter { $0.bookId == currentBookId }
    }
    private var allIncomes: [IncomeData] {
        allIncomesRaw.filter { $0.bookId == currentBookId }
    }
    private var allBudgets: [BudgetData] {
        allBudgetsRaw.filter { $0.bookId == currentBookId }
    }
    private var allRecurringBudgets: [RecurringBudgetData] {
        allRecurringBudgetsRaw.filter { $0.bookId == currentBookId }
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

    // MARK: - 集計範囲（年月のみ）

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var showsMonthPicker = false
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())

    // MARK: - 作成条件

    @State private var pageKinds: Set<NotebookPageKind> = Set(NotebookPageKind.allCases)
    @State private var paperSize: NotebookPaperSize = .a4
    @State private var designStyle: NotebookDesignStyle = .simple
    @State private var reflection = NotebookReflectionText()

    // MARK: - 作成結果

    @State private var isGenerating = false
    @State private var generatedURL: URL? = nil
    @State private var showsPreview = false
    @State private var showsShareSheet = false
    @State private var alertMessage = ""
    @State private var showsAlert = false

    private var visibleExpenses: [ExpenseData] {
        DowngradeLockService.visibleExpenses(allExpenses, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods)
    }

    private var visibleIncomes: [IncomeData] {
        DowngradeLockService.visibleIncomes(allIncomes, bankAccounts: allBankAccounts, paymentMethods: allPaymentMethods)
    }

    private var periodLabel: String {
        "\(selectedYear)年\(selectedMonth)月"
    }

    private var pdfTitle: String { "\(periodLabel) 家計簿ノート" }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.sheetBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        periodSection
                        pageSelectionSection
                        if pageKinds.contains(.reflection) {
                            reflectionInputSection
                        }
                        paperSizeSection
                        designSection
                        actionSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showsMonthPicker) {
            YearMonthPickerView(year: $pickerYear, month: $pickerMonth) {
                selectedYear = pickerYear
                selectedMonth = pickerMonth
            }
        }
        .sheet(isPresented: $showsPreview) {
            if let url = generatedURL {
                NotebookPDFPreviewView(url: url)
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            if let url = generatedURL {
                NotebookShareSheetView(url: url)
            }
        }
        .alert(alertMessage, isPresented: $showsAlert) {
            Button("OK") {}
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppHeaderTitleView(title: "家計簿ノート作成")
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - 期間選択

    private var periodSection: some View {
        sectionCard(header: "集計範囲") {
            Button {
                pickerYear = selectedYear
                pickerMonth = selectedMonth
                showsMonthPicker = true
            } label: {
                periodValueRow(title: "対象年月", value: periodLabel)
            }
            .buttonStyle(.plain)
        }
    }

    private func periodValueRow(title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.8))
            Spacer()
            Text(value)
                .font(AppFonts.body)
                .foregroundStyle(Color.black.opacity(0.5))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.4))
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(Color.white)
        .contentShape(Rectangle())
    }

    // MARK: - 作成するページ

    private var pageSelectionSection: some View {
        sectionCard(header: "作成するページ") {
            ForEach(Array(NotebookPageKind.allCases.enumerated()), id: \.element) { index, kind in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                checkboxRow(title: kind.displayName, isChecked: pageKinds.contains(kind)) {
                    if pageKinds.contains(kind) {
                        pageKinds.remove(kind)
                    } else {
                        pageKinds.insert(kind)
                    }
                }
            }
        }
    }

    private func checkboxRow(title: String, isChecked: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
                    .foregroundStyle(isChecked ? themeManager.mainColor : Color.gray.opacity(0.4))
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 振り返り欄の入力

    private var reflectionInputSection: some View {
        sectionCard(header: "振り返り欄の入力") {
            reflectionField(title: "今月よかったこと", text: $reflection.goodThings)
            Divider().padding(.leading, 20)
            reflectionField(title: "使いすぎたもの", text: $reflection.overspent)
            Divider().padding(.leading, 20)
            reflectionField(title: "来月気をつけること", text: $reflection.nextMonthCaution)
            Divider().padding(.leading, 20)
            reflectionField(title: "自由メモ", text: $reflection.freeMemo)
        }
    }

    private func reflectionField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))
            TextEditor(text: text)
                .font(AppFonts.body)
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .background(AppColors.sheetBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    // MARK: - 用紙サイズ

    private var paperSizeSection: some View {
        sectionCard(header: "用紙サイズ") {
            ForEach(Array(NotebookPaperSize.allCases.enumerated()), id: \.element) { index, size in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                radioRow(title: size.displayName, isSelected: paperSize == size) { paperSize = size }
            }
        }
    }

    // MARK: - デザイン

    private var designSection: some View {
        sectionCard(header: "デザイン") {
            ForEach(Array(NotebookDesignStyle.allCases.enumerated()), id: \.element) { index, style in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                radioRow(title: style.displayName, isSelected: designStyle == style) { designStyle = style }
            }
        }
    }

    private func radioRow(title: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.mainColor)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 作成・印刷・共有

    private var actionSection: some View {
        sectionCard(header: "作成") {
            actionRow(icon: "doc.badge.plus", title: "PDFを作成") { performCreate() }
            Divider().padding(.leading, 20)
            actionRow(icon: "printer", title: "印刷する") { performPrint() }
            Divider().padding(.leading, 20)
            actionRow(icon: "square.and.arrow.up", title: "共有する") { performShare() }
        }
    }

    private func actionRow(icon: String, title: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(themeManager.mainColor)
                    .frame(width: 32)
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(themeManager.mainColor)
                Spacer()
                if isGenerating {
                    ProgressView()
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color.white)
            .contentShape(Rectangle())
            .opacity(isGenerating ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    // MARK: - PDF作成処理

    // 選択月の1日00:00〜翌月1日00:00（排他的上限）
    private var aggregationRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? Date()
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    private func generatePDF() -> URL? {
        let range = aggregationRange
        let notebookData = BudgetNotebookAggregator.build(
            start: range.start, end: range.end,
            budgetYear: selectedYear,
            budgetMonth: selectedMonth,
            allExpenses: visibleExpenses, allIncomes: visibleIncomes,
            allBudgets: allBudgets, allRecurringBudgets: allRecurringBudgets,
            allCategories: allCategories
        )
        let orderedKinds = NotebookPageKind.allCases.filter { pageKinds.contains($0) }
        let accent = designStyle == .themeColor ? themeManager.mainColor : Color.black.opacity(0.55)
        return BudgetNotebookPDFRenderer.makePDF(
            data: notebookData, pageKinds: orderedKinds, paperSize: paperSize,
            accentColor: accent, reflection: reflection, periodLabel: periodLabel, pdfTitle: pdfTitle
        )
    }

    private func performCreate() {
        runGeneration { url in
            generatedURL = url
            showsPreview = true
        }
    }

    private func performPrint() {
        runGeneration { url in
            generatedURL = url
            BudgetNotebookPDFRenderer.presentPrint(url: url, jobName: pdfTitle)
        }
    }

    private func performShare() {
        runGeneration { url in
            generatedURL = url
            showsShareSheet = true
        }
    }

    private func runGeneration(onSuccess: @escaping (URL) -> Void) {
        guard !pageKinds.isEmpty else {
            showAlert("作成するページを1つ以上選択してください")
            return
        }
        guard !isGenerating else { return }
        isGenerating = true
        DispatchQueue.main.async {
            if let url = generatePDF() {
                onSuccess(url)
            } else {
                showAlert("PDFの作成に失敗しました。")
            }
            isGenerating = false
        }
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showsAlert = true
    }

    // MARK: - 共通セクションカード

    private func sectionCard<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.line, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - PDFプレビュー（QuickLook）

private struct NotebookPDFPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - 共有シート

private struct NotebookShareSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
