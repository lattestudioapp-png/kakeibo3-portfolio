import SwiftUI
import os

private let fixedExpenseListLogger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "FixedExpenseListView")

struct FixedExpenseListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var fixedExpenseDataObserver = FixedExpenseDataSync.observer()
    private var fixedExpenses: [FixedExpenseData] { fixedExpenseDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var paymentMethods: [PaymentMethodSettingData] {
        paymentMethodsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var isAdding = false
    @State private var editingItem: FixedExpenseData? = nil
    @State private var deleteTarget: FixedExpenseData? = nil

    private var activeExpenses: [FixedExpenseData] {
        fixedExpenses.filter { $0.isActive && $0.bookId == currentBookId }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        // expensesをbody内で1回だけ計算して使い回す
        let expenses = activeExpenses
        let _ = fixedExpenseListLogger.debug("body evaluated: \(expenses.count) expenses")

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(expenses) { item in
                        FixedExpenseRow(
                            item: item,
                            methodName: paymentMethodName(for: item),
                            onTapRow: { editingItem = item }
                        )
                    }

                    if expenses.isEmpty {
                        Text("固定費が登録されていません")
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
            .navigationTitle("固定費")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $isAdding) { FixedExpenseEditView(existing: nil) }
        .sheet(item: $editingItem) { FixedExpenseEditView(existing: $0) }
        .alert("「\(deleteTarget?.name ?? "")」を削除しますか？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("削除", role: .destructive) { delete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この固定費を削除します。よろしいですか？")
        }
    }

    private func delete() {
        guard var target = deleteTarget else { return }
        target.isActive = false
        FixedExpenseDataSync.update(target)
        deleteTarget = nil
    }

    // MARK: - 追加ボタン

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("固定費を追加", systemImage: "plus")
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

    private func paymentMethodName(for item: FixedExpenseData) -> String? {
        guard let id = item.paymentMethodId else { return nil }
        switch item.paymentMethodType {
        case "bankAccount":
            return bankAccounts.first { $0.id == id }?.accountName
        case "paymentMethod":
            return paymentMethods.first { $0.id == id }?.methodName
        default:
            return nil
        }
    }
}

// MARK: - 1行分（専用View。対象項目と必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct FixedExpenseRow: View {
    let item: FixedExpenseData
    let methodName: String?
    let onTapRow: () -> Void

    var body: some View {
        let _ = fixedExpenseListLogger.debug("row evaluated: \(item.name)")

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
                        Text("支払い：\(methodName)")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    }

                    if !item.memo.isEmpty {
                        Text(item.memo)
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                            .lineLimit(1)
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
