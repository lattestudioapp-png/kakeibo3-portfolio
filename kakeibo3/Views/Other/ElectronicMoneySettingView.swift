import SwiftUI

struct ElectronicMoneySettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allSettings: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    @State private var editingMethod: PaymentMethodSettingData? = nil
    @State private var isAdding = false

    private var electronicMoneyMethods: [PaymentMethodSettingData] {
        allSettings
            .filter { $0.type == PaymentMethodType.electronicMoney.rawValue && $0.isActive && $0.bookId == currentBookId }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        let methods = electronicMoneyMethods

        NavigationStack {
            List {
                Section {
                    if methods.isEmpty {
                        Text("登録されていません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    } else {
                        ForEach(methods) { method in
                            ElectronicMoneyRow(method: method, onTapRow: { editingMethod = method })
                        }
                    }

                    Button {
                        isAdding = true
                    } label: {
                        Label("電子マネーを追加", systemImage: "plus")
                            .font(AppFonts.button)
                            .foregroundStyle(AppColors.main)
                    }
                } header: {
                    Text("登録済みの電子マネー")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("電子マネー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $isAdding) { ElectronicMoneyEditView(existing: nil) }
        .sheet(item: $editingMethod) { ElectronicMoneyEditView(existing: $0) }
    }
}

// MARK: - 1行分（専用View。対象項目と必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct ElectronicMoneyRow: View {
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
