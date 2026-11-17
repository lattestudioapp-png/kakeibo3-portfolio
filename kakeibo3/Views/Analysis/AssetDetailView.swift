import SwiftUI

// MARK: - 資産詳細View（口座 / 支払い方法）

struct AssetDetailView: View {
    let target: AssetDetailTarget

    @Environment(\.dismiss) private var dismiss

    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()

    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var incomeDataObserver = IncomeDataSync.observer()
    private var allIncomes: [IncomeData] { incomeDataObserver.items }
    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var allExpenses: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var transferDataObserver = TransferDataSync.observer()
    private var allTransfersRaw: [TransferData] { transferDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var allCategoriesRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allPaymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var allTransfers: [TransferData] {
        allTransfersRaw.filter { $0.bookId == currentBookId }
    }
    private var allCategories: [CategoryData] {
        allCategoriesRaw.filter { $0.bookId == currentBookId }
    }
    private var allPaymentMethods: [PaymentMethodSettingData] {
        allPaymentMethodsRaw.filter { $0.bookId == currentBookId }
    }

    // vmは@Stateで保持し観測しない（実際に観測して再描画すべきなのはAssetDetailContentView側）。
    // openSwipeItemID（行スワイプ）はAssetDetailContentView側に閉じ込めているため、
    // スワイプのたびにこちらのbody（dataToken＝全履歴ハッシュ計算）が再評価されることはない。
    @State private var vm = AssetDetailViewModel()
    @State private var editingItem: TransactionListItem? = nil

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var bookScopedIncomes: [IncomeData] {
        allIncomes.filter { $0.bookId == currentBookId }
    }

    private var bookScopedExpenses: [ExpenseData] {
        allExpenses.filter { $0.bookId == currentBookId }
    }

    // 件数だけでなく、既存項目の編集（写真追加など）も検知できるように
    // TransactionChangeSignature を使う。
    private var dataToken: String {
        TransactionChangeSignature.make(
            incomeDataList: bookScopedIncomes,
            expenseDataList: bookScopedExpenses,
            transferDataList: allTransfers
        )
    }

    // MARK: - 資産推移グラフ用の選択月レンジ（総資産グラフと同じ AnalysisDateRange を使う）

    private var detailDateRange: AnalysisDateRange {
        AnalysisDateRangeCalculator.current(for: .month, referenceDate: target.selectedDate)
    }

    // MARK: - Body

    var body: some View {
        AssetDetailContentView(
            target: target,
            vm: vm,
            editingItem: $editingItem,
            detailDateRange: detailDateRange,
            onDismiss: { dismiss() },
            onDelete: handleDelete
        )
        .onAppear { rebuild() }
        .onChange(of: dataToken) { _, _ in rebuild() }
        .onChange(of: selectedBookIdString) { _, _ in rebuild() }
        .fullScreenCover(item: $editingItem) { item in
            TransactionHistoryEditView(item: item, onClose: { editingItem = nil })
        }
    }

    private func rebuild() {
        vm.rebuild(
            target: target,
            allBankAccounts: allBankAccounts,
            allIncomes: bookScopedIncomes,
            allExpenses: bookScopedExpenses,
            allTransfers: allTransfers,
            allCategories: allCategories,
            allPaymentMethods: allPaymentMethods
        )
    }

    // MARK: - 削除

    private func handleDelete(_ listItem: TransactionListItem) {
        let event: SnapshotEvent
        switch listItem.kind {
        case .income:
            if let target = allIncomes.first(where: { $0.id == listItem.sourceId }) {
                IncomeDataSync.delete(id: target.id)
            }
            event = .incomeDeleted(date: listItem.date, bookId: listItem.bookId ?? UUID())
        case .expense:
            if let target = allExpenses.first(where: { $0.id == listItem.sourceId }) {
                ExpenseDataSync.delete(id: target.id)
            }
            event = .expenseDeleted(date: listItem.date, bookId: listItem.bookId ?? UUID())
        case .transfer:
            if let target = allTransfers.first(where: { $0.id == listItem.sourceId }) {
                TransferDataSync.delete(id: target.id)
            }
            event = .transferDeleted(date: listItem.date, bookId: listItem.bookId ?? UUID())
        }
        SnapshotUpdateService.handle(event)
    }

}

// MARK: - 資産詳細の中身（vmを観測する側）
//
// vmの@Publishedプロパティと、行スワイプ状態（openSwipeItemID）をここに閉じ込める。
// AssetDetailView自体はvmを観測せず、openSwipeItemIDも持たないため、行をスワイプしても
// AssetDetailView側のdataToken（全履歴ハッシュ）は再計算されない。

private struct AssetDetailContentView: View {
    let target: AssetDetailTarget
    @ObservedObject var vm: AssetDetailViewModel
    @Binding var editingItem: TransactionListItem?
    let detailDateRange: AnalysisDateRange
    let onDismiss: () -> Void
    let onDelete: (TransactionListItem) -> Void

    @State private var openSwipeItemID: UUID? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if target.hasBalance {
                        balanceLayout
                    } else {
                        noBalanceLayout
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { onDismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
    }

    // MARK: - 残高ありレイアウト

    @ViewBuilder
    private var balanceLayout: some View {
        currentBalanceCard
        AssetTrendChartView(
            title: "残高推移",
            dailyPoints: vm.balanceChartPoints,
            firstRecordedDate: vm.balanceChartEarliestDate,
            dateRange: detailDateRange,
            valueName: "残高"
        )
        if !vm.expenseCategoryItems.isEmpty { categoryCard(title: "支出", items: vm.expenseCategoryItems) }
        if !vm.incomeCategoryItems.isEmpty  { categoryCard(title: "収入", items: vm.incomeCategoryItems)  }
        AnalysisItemListCard(
            items: vm.transactions,
            openItemID: $openSwipeItemID,
            onTap: { editingItem = $0 },
            onDelete: deleteItem
        )
    }

    // MARK: - 残高なしレイアウト（クレジットカード等）

    @ViewBuilder
    private var noBalanceLayout: some View {
        thisMonthExpenseCard
        if !vm.expenseCategoryItems.isEmpty { categoryCard(title: "支出", items: vm.expenseCategoryItems) }
        AnalysisItemListCard(
            items: vm.transactions,
            openItemID: $openSwipeItemID,
            onTap: { editingItem = $0 },
            onDelete: deleteItem
        )
    }

    // MARK: - 現在残高カード

    private var currentBalanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("現在残高")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.45))
            Text(formatAnalysisAmount(vm.currentBalance))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(vm.currentBalance >= 0 ? Color.black.opacity(0.82) : AppColors.expenseColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - 今月の支出カード（残高なし用）

    private var thisMonthExpenseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(vm.selectedMonthLabel)の支出")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.45))
            Text(formatAnalysisAmount(vm.thisMonthExpense))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - カテゴリカード（支出 / 収入 共通）

    private func categoryCard(title: String, items: [AnalysisCategorySummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.65))

            VStack(spacing: 10) {
                ForEach(items) { item in
                    categoryRow(item)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    private func categoryRow(_ item: AnalysisCategorySummary) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.categoryName)
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", item.percentage))
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.40))
                    .frame(width: 36, alignment: .trailing)
                Text(formatAnalysisAmount(item.totalAmount))
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.06))
                        .frame(height: 4)
                    Capsule().fill(item.color.opacity(0.75))
                        .frame(width: geo.size.width * min(item.percentage / 100, 1.0), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - 削除（ローカルのスワイプ状態をリセットしてから外側のonDeleteを呼ぶ）

    private func deleteItem(_ item: TransactionListItem) {
        openSwipeItemID = nil
        onDelete(item)
    }
}
