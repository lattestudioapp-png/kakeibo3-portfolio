import SwiftUI

// MARK: - ゴミ箱画面
//
// 現在選択中の帳簿のゴミ箱内データ（支出・収入・振替）だけを表示する。
// 他帳簿のゴミ箱データはここには一切表示されず、この画面での操作でも変化しない。

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    @State private var expenses: [ExpenseData] = []
    @State private var incomes: [IncomeData] = []
    @State private var transfers: [TransferData] = []

    @State private var showsEmptyTrashConfirm = false
    @State private var alertMessage: String?

    private let transactionRepository: TransactionRepository = SwiftDataTransactionRepository()

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: BookDataSync.fetchAll(), selectedIdString: selectedBookIdString)?.id
    }

    private var items: [TransactionListItem] {
        let all: [TransactionListItem] =
            expenses.map(TransactionListItem.expense(from:))
            + incomes.map(TransactionListItem.income(from:))
            + transfers.map(TransactionListItem.transfer(from:))
        return all.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    var body: some View {
        ZStack {
            AppColors.sheetBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView

                noteView

                if items.isEmpty {
                    Spacer()
                    Text("ゴミ箱は空です")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.4))
                    Spacer()
                } else {
                    List {
                        ForEach(items) { item in
                            TrashedTransactionRowView(
                                item: item,
                                onRestore: { restore(item) },
                                onDelete: { permanentlyDelete(item) }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    .listStyle(.plain)
                }
            }

            if showsEmptyTrashConfirm {
                DestructiveConfirmationDialogView(
                    title: "ゴミ箱内のすべてのデータを完全に削除しますか？",
                    message: "この操作は取り消せません。",
                    destructiveLabel: "すべて削除",
                    onCancel: { showsEmptyTrashConfirm = false },
                    onDestructive: {
                        showsEmptyTrashConfirm = false
                        emptyTrash()
                    }
                )
            }
        }
        .onAppear { reload() }
        .alert("エラー", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppHeaderTitleView(title: "ゴミ箱")
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button {
                showsEmptyTrashConfirm = true
            } label: {
                Text("空にする")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(items.isEmpty ? Color.gray.opacity(0.4) : Color.red)
            }
            .disabled(items.isEmpty)
            .frame(width: AppLayout.headerButtonSize * 1.5, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    private var noteView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)
            Text("削除したデータは30日後に完全に削除されます。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    // MARK: - データ読み込み（現在の帳簿のゴミ箱内データだけ）

    private func reload() {
        guard let bookId = currentBookId else {
            expenses = []
            incomes = []
            transfers = []
            return
        }
        expenses = ExpenseDataSync.fetchTrashed(bookId: bookId)
        incomes = IncomeDataSync.fetchTrashed(bookId: bookId)
        transfers = TransferDataSync.fetchTrashed(bookId: bookId)
    }

    // MARK: - アクション

    private func restore(_ item: TransactionListItem) {
        do {
            let restored = try transactionRepository.restoreTransaction(
                originalItem: item, incomeDataList: incomes, expenseDataList: expenses, transferDataList: transfers
            )
            if !restored { alertMessage = "復元に失敗しました。" }
        } catch {
            alertMessage = "復元に失敗しました。"
        }
        reload()
    }

    private func permanentlyDelete(_ item: TransactionListItem) {
        do {
            let deleted = try transactionRepository.permanentlyDeleteTransaction(
                originalItem: item, incomeDataList: incomes, expenseDataList: expenses, transferDataList: transfers
            )
            if !deleted { alertMessage = "完全削除に失敗しました。" }
        } catch {
            alertMessage = "完全削除に失敗しました。"
        }
        reload()
    }

    private func emptyTrash() {
        guard let bookId = currentBookId else { return }
        do {
            _ = try transactionRepository.emptyTrash(
                bookId: bookId, incomeDataList: incomes, expenseDataList: expenses, transferDataList: transfers
            )
        } catch {
            alertMessage = "ゴミ箱を空にできませんでした。"
        }
        reload()
    }
}
