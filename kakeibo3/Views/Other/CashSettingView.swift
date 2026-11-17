import SwiftUI

struct CashSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allSettings: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    @State private var editingCash: PaymentMethodSettingData? = nil
    @State private var isAdding = false

    private var cashMethods: [PaymentMethodSettingData] {
        allSettings
            .filter { $0.type == PaymentMethodType.cash.rawValue && $0.isActive && $0.bookId == currentBookId }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        let methods = cashMethods

        NavigationStack {
            List {
                Section {
                    if methods.isEmpty {
                        Text("登録されていません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    } else {
                        ForEach(methods) { method in
                            CashRow(method: method, onTapRow: { editingCash = method })
                        }
                    }

                    Button {
                        isAdding = true
                    } label: {
                        Label("現金を追加", systemImage: "plus")
                            .font(AppFonts.button)
                            .foregroundStyle(AppColors.main)
                    }
                } header: {
                    Text("登録済みの現金")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("現金")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $isAdding) { CashEditView(existing: nil) }
        .sheet(item: $editingCash) { CashEditView(existing: $0) }
    }
}

// MARK: - 1行分（専用View。対象項目と必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct CashRow: View {
    let method: PaymentMethodSettingData
    let onTapRow: () -> Void

    var body: some View {
        Button(action: onTapRow) {
            HStack {
                Circle()
                    .fill(ColorHexConverter.color(from: method.colorHex))
                    .frame(width: 10, height: 10)
                Text(method.methodName)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
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
