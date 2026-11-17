import SwiftUI

struct DebitCardSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allSettings: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var editingMethod: PaymentMethodSettingData? = nil
    @State private var isAdding = false

    private var debitCardMethods: [PaymentMethodSettingData] {
        allSettings
            .filter { $0.type == PaymentMethodType.debitCard.rawValue && $0.isActive && $0.bookId == currentBookId }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        let methods = debitCardMethods

        NavigationStack {
            List {
                Section {
                    if methods.isEmpty {
                        Text("登録されていません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    } else {
                        ForEach(methods) { method in
                            DebitCardRow(
                                method: method,
                                bankAccountName: bankAccountName(for: method),
                                onTapRow: { editingMethod = method }
                            )
                        }
                    }

                    Button {
                        isAdding = true
                    } label: {
                        Label("デビットカードを追加", systemImage: "plus")
                            .font(AppFonts.button)
                            .foregroundStyle(AppColors.main)
                    }
                } header: {
                    Text("登録済みのデビットカード")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("デビットカード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $isAdding) { DebitCardEditView(existing: nil) }
        .sheet(item: $editingMethod) { DebitCardEditView(existing: $0) }
    }

    private func bankAccountName(for method: PaymentMethodSettingData) -> String? {
        guard let id = method.withdrawalBankAccountId else { return nil }
        return allBankAccounts.first(where: { $0.id == id })?.accountName
    }
}

// MARK: - 1行分（専用View。対象項目と必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct DebitCardRow: View {
    let method: PaymentMethodSettingData
    let bankAccountName: String?
    let onTapRow: () -> Void

    var body: some View {
        Button(action: onTapRow) {
            HStack {
                Circle()
                    .fill(ColorHexConverter.color(from: method.colorHex))
                    .frame(width: 10, height: 10)
                if let bankAccountName {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(method.methodName)
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(Color.black.opacity(0.8))
                        Text("支払い口座：\(bankAccountName)")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                } else {
                    Text(method.methodName)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .frame(minHeight: AppLayout.selectionRowHeight)
        }
        .buttonStyle(.plain)
    }
}
