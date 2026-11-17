import SwiftUI

struct SearchView: View {

    // MARK: - Environment & Query

    @Environment(\.dismiss) private var dismiss

    @StateObject private var incomeDataObserver = IncomeDataSync.observer()
    private var incomeDataList: [IncomeData] { incomeDataObserver.items }
    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var expenseDataList: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var paymentMethods: [PaymentMethodSettingData] {
        paymentMethodsRaw.filter { $0.bookId == currentBookId }
    }

    // ロック中の口座/支払い方法に紐づく取引を除いたリスト（選択中の帳簿ぶんのみ）
    private var visibleIncomeDataList: [IncomeData] {
        DowngradeLockService.visibleIncomes(
            incomeDataList.filter { $0.bookId == currentBookId }, bankAccounts: bankAccounts, paymentMethods: paymentMethods
        )
    }
    private var visibleExpenseDataList: [ExpenseData] {
        DowngradeLockService.visibleExpenses(
            expenseDataList.filter { $0.bookId == currentBookId }, bankAccounts: bankAccounts, paymentMethods: paymentMethods
        )
    }

    // MARK: - ViewModel
    //
    // vmは@StateObjectではなく@Stateで保持する（インスタンスの生存期間はどちらも同じ）。
    // @StateObject/@ObservedObjectでvmを観測すると、キーワード入力のたびに@Publishedが発火して
    // SearchView.body全体が再評価され、そのたびにdataToken（全件ハッシュ）まで再計算されて
    // 重くなってしまう。実際にvmを観測して再描画すべきなのはSearchContentView側だけでよい。
    @State private var vm = SearchViewModel()

    // MARK: - UI ローカル状態

    @State private var showsFilterEditor = false
    @State private var editingItem: TransactionListItem? = nil
    @State private var openItemID: UUID? = nil
    @State private var isDraggingList = false

    // MARK: - データ変更トークン
    //
    // 件数だけでなく、既存項目の編集（写真追加など）も検知できるように
    // TransactionChangeSignature を使う。
    // vmを観測しないSearchView側で保持しているため、検索キーワードの入力では
    // 再評価されず、実際にincome/expenseデータが変わった時だけ計算される。

    private var dataToken: String {
        TransactionChangeSignature.make(
            incomeDataList: incomeDataList.filter { $0.bookId == currentBookId },
            expenseDataList: expenseDataList.filter { $0.bookId == currentBookId }
        )
    }

    // MARK: - Body

    var body: some View {
        SearchContentView(
            vm: vm,
            showsFilterEditor: $showsFilterEditor,
            editingItem: $editingItem,
            openItemID: $openItemID,
            isDraggingList: $isDraggingList,
            onDismiss: { dismiss() },
            onDelete: deleteItem
        )
        .onAppear {
            vm.rebuildAllItems(incomes: visibleIncomeDataList, expenses: visibleExpenseDataList)
        }
        .onChange(of: dataToken) { _, _ in
            vm.rebuildAllItems(incomes: visibleIncomeDataList, expenses: visibleExpenseDataList)
        }
        .onChange(of: selectedBookIdString) { _, _ in
            vm.rebuildAllItems(incomes: visibleIncomeDataList, expenses: visibleExpenseDataList)
        }
        .fullScreenCover(item: $editingItem) { item in
            TransactionHistoryEditView(item: item, onClose: { editingItem = nil })
        }
    }

    // MARK: - 削除
    //
    // 即時完全削除ではなく、ゴミ箱へ移動する（30日後に自動で完全削除される）。

    private static let transactionRepository: TransactionRepository = SwiftDataTransactionRepository()

    private func deleteItem(_ item: TransactionListItem) {
        openItemID = nil
        _ = try? Self.transactionRepository.trashTransaction(
            originalItem: item,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList,
            transferDataList: []
        )
    }
}

// MARK: - 検索結果表示（vmを観測する側）
//
// vmの@Publishedプロパティ（keyword/filteredItemsなど）を実際に観測して再描画するのはこの
// Viewだけにする。SearchView自体はvmを観測しないため、ここが再描画されてもSearchView側の
// dataToken（全件ハッシュ）は再計算されない。

private struct SearchContentView: View {
    @ObservedObject var vm: SearchViewModel

    @Binding var showsFilterEditor: Bool
    @Binding var editingItem: TransactionListItem?
    @Binding var openItemID: UUID?
    @Binding var isDraggingList: Bool

    let onDismiss: () -> Void
    let onDelete: (TransactionListItem) -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        AppScreenContainer {
            VStack(spacing: 0) {
                filterBar
                summarySection
                resultsList
            }
            .background(AppColors.sheetBackground)
        } headerOverlay: {
            headerArea
                .padding(.top, SegmentBarLayout.standard.topPadding)
                .frame(height: AppLayout.headerHeight, alignment: .top)
        }
        .sheet(isPresented: $showsFilterEditor) {
            SearchFilterEditView(vm: vm)
        }
    }

    // MARK: - Header（分析Viewのセグメントタブと同じ高さ・位置）

    private var headerArea: some View {
        HStack(spacing: 12) {
            HeaderCloseButtonView { onDismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            searchBar
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .frame(height: SegmentBarLayout.standard.height)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.35))

            TextField("金額・メモ・カテゴリー", text: $vm.keyword)
                .font(.system(size: 15))
                .foregroundStyle(Color.black.opacity(0.85))
                .focused($isSearchFieldFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: SegmentBarLayout.standard.height)
        .background(Color.white.opacity(0.92))
        .clipShape(Capsule())
    }

    // MARK: - 検索条件ボタン（ヘッダーには置かず、コンテンツ側の右寄せに配置）

    private var filterBar: some View {
        HStack {
            Spacer()
            Button {
                showsFilterEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("検索条件")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppColors.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 集計エリア

    private var summarySection: some View {
        HStack(spacing: 0) {
            summaryColumn(label: "収入", amount: vm.incomeTotal,  color: AppColors.incomeColor)
            summaryColumn(label: "支出", amount: vm.expenseTotal, color: AppColors.expenseColor)
            summaryColumn(label: "合計", amount: vm.balanceTotal, color: netColor)
        }
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.gray.opacity(0.25)).frame(height: 0.7)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.gray.opacity(0.25)).frame(height: 0.7)
        }
    }

    private func summaryColumn(label: String, amount: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.65))
            Text(formattedAmount(amount))
                .font(.system(size: 13, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var netColor: Color {
        if vm.balanceTotal > 0 { return AppColors.incomeColor }
        if vm.balanceTotal < 0 { return AppColors.expenseColor }
        return Color.black.opacity(0.7)
    }

    // MARK: - 検索結果リスト（カレンダーViewと同じ DateGroupedTransactionSection を使う）

    @ViewBuilder
    private var resultsList: some View {
        if vm.filteredItems.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text("検索結果がありません")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                Text("条件を変更してもう一度お試しください")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.3))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.groupedDates, id: \.self) { date in
                        DateGroupedTransactionSection(
                            date: date,
                            items: vm.groupedItems[date] ?? [],
                            openItemID: $openItemID,
                            onTap: { editingItem = $0 },
                            onDelete: onDelete,
                            isDraggingList: isDraggingList
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if abs(value.translation.height) > 10, !isDraggingList {
                            isDraggingList = true
                        }
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isDraggingList = false
                        }
                    }
            )
        }
    }

    // MARK: - Helpers

    private func formattedAmount(_ value: Int) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        let str = n.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return (value < 0 ? "-" : "") + str + "円"
    }
}
