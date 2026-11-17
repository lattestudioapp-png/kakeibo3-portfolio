import SwiftUI
import os

private let recurringIncomeListLogger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "RecurringIncomeListView")

struct RecurringIncomeListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var recurringIncomeDataObserver = RecurringIncomeDataSync.observer()
    private var recurringIncomes: [RecurringIncomeData] { recurringIncomeDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var paymentSettings: [PaymentMethodSettingData] {
        paymentSettingsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var isAdding = false
    @State private var editingItem: RecurringIncomeData? = nil
    @State private var deleteTarget: RecurringIncomeData? = nil

    private var activeIncomes: [RecurringIncomeData] {
        recurringIncomes.filter { $0.isActive && $0.bookId == currentBookId }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        // incomesをbody内で1回だけ計算して使い回す
        let incomes = activeIncomes
        let _ = recurringIncomeListLogger.debug("body evaluated: \(incomes.count) incomes")

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(incomes) { item in
                        RecurringIncomeRow(
                            item: item,
                            methodName: receiveMethodName(for: item),
                            onTapRow: { editingItem = item }
                        )
                    }

                    if incomes.isEmpty {
                        Text("定期収入が登録されていません")
                            .font(AppFonts.body)
                            .foregroundStyle(Color.black.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }

                    addButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("定期収入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $isAdding) { RecurringIncomeEditView(existing: nil) }
        .sheet(item: $editingItem) { RecurringIncomeEditView(existing: $0) }
        .alert("「\(deleteTarget?.name ?? "")」を削除しますか？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("削除", role: .destructive) { delete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この定期収入を削除します。よろしいですか？")
        }
    }

    private func delete() {
        guard var target = deleteTarget else { return }
        target.isActive = false
        RecurringIncomeDataSync.update(target)
        deleteTarget = nil
    }

    // MARK: - 追加ボタン

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("定期収入を追加", systemImage: "plus")
                .font(AppFonts.button)
                .foregroundStyle(AppColors.main)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: AppLayout.selectionRowHeight)
                .padding(.horizontal, 20)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ヘルパー

    private func receiveMethodName(for item: RecurringIncomeData) -> String? {
        guard let id = item.receiveMethodId else { return nil }
        switch item.receiveMethodType {
        case "bankAccount":
            return bankAccounts.first { $0.id == id }?.accountName
        case "paymentMethod":
            return paymentSettings.first { $0.id == id }?.methodName
        default:
            return nil
        }
    }
}

// MARK: - 1行分（専用View。対象項目と必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct RecurringIncomeRow: View {
    let item: RecurringIncomeData
    let methodName: String?
    let onTapRow: () -> Void

    var body: some View {
        let _ = recurringIncomeListLogger.debug("row evaluated: \(item.name)")

        Button(action: onTapRow) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(AppFonts.sectionTitle)
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(formattedAmount)
                        .font(AppFonts.body)
                        .foregroundStyle(Color.black.opacity(0.6))

                    Text("毎月\(item.dayOfMonth)日")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.4))

                    if let methodName {
                        Text("受け取り方法：\(methodName)")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.22))
                    .padding(.top, 3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var formattedAmount: String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        return (n.string(from: NSNumber(value: item.amount)) ?? "\(item.amount)") + "円"
    }
}
