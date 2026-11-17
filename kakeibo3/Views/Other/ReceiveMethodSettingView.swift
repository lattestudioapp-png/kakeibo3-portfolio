import SwiftUI

// 通常受け取り（PaymentMethodSettingData.useForReceive）と銀行口座を統合表示するラッパー
private enum ReceiveMethodItem: Identifiable {
    case other(PaymentMethodSettingData)
    case bank(BankAccountData)

    var id: String {
        switch self {
        case .other(let m): return "o_\(m.id)"
        case .bank(let b):  return "b_\(b.id)"
        }
    }

    var sortOrder: Int {
        switch self {
        case .other(let m): return m.sortOrder
        case .bank(let b):  return b.sortOrder
        }
    }

    var createdAt: Date {
        switch self {
        case .other(let m): return m.createdAt
        case .bank(let b):  return b.createdAt
        }
    }

    var displayName: String {
        switch self {
        case .other(let m): return m.methodName
        case .bank(let b):  return b.accountName
        }
    }
}

struct ReceiveMethodSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    // 受け取りに追加がオンのその他支払い方法（クレカ以外）
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    private var paymentSettings: [PaymentMethodSettingData] {
        paymentSettingsRaw.filter { $0.bookId == currentBookId }
    }
    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var isShowingTypeSelection = false
    @State private var editingOther: PaymentMethodSettingData? = nil
    @State private var editingBank: BankAccountData? = nil
    // 追加する種類（1つの.sheet(item:)にまとめることで、.sheetの連結数を減らす。
    // 連結数が多いと型メタデータ解決が重くなり、シート遷移アニメーションが引っかかることがある）
    @State private var addingType: ReceiveAddType? = nil

    // この画面は「有効な受け取り方法の並び替え」専用。ロック中の項目は選択UIを出さず、一覧にも出さない
    // （有効/ロックの選択は各種類の個別設定画面（銀行口座・その他）で行う）。
    private var allActiveItems: [ReceiveMethodItem] {
        let others = paymentSettings
            .filter { $0.isActive && !$0.isLocked && $0.useForReceive && $0.type != PaymentMethodType.creditCard.rawValue }
            .map { ReceiveMethodItem.other($0) }
        let banks = bankAccounts
            .filter { $0.isActive && !$0.isLocked && $0.showAsReceiveMethod }
            .map { ReceiveMethodItem.bank($0) }
        return (others + banks).sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ReorderHintView()
                    .background(AppColors.sheetBackground)

                List {
                    Section {
                        if allActiveItems.isEmpty {
                            Text("受け取りが登録されていません")
                                .font(AppFonts.caption)
                                .foregroundStyle(Color.black.opacity(0.35))
                        } else {
                            ForEach(allActiveItems) { item in
                                unifiedRow(item)
                            }
                            .onMove(perform: moveAllItems)
                        }

                        Button {
                            isShowingTypeSelection = true
                        } label: {
                            Label("受け取りの追加", systemImage: "plus")
                                .font(AppFonts.button)
                                .foregroundStyle(AppColors.main)
                        }
                        .environment(\.editMode, .constant(.inactive))
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
                .tint(Color.black.opacity(0.45))
                .scrollContentBackground(.hidden)
                .background(AppColors.sheetBackground)
                // .insetGroupedは最初のSectionの上に既定の余白を持つため、
                // 「並び替え ↓」のすぐ下に一覧が来るよう詰める
                .contentMargins(.top, 0, for: .scrollContent)
            }
            .navigationTitle("受け取り")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .onAppear {
            UITableView.appearance().tintColor = UIColor.black.withAlphaComponent(0.45)
        }
        .onDisappear {
            UITableView.appearance().tintColor = nil
        }
        .sheet(isPresented: $isShowingTypeSelection) {
            ReceiveMethodTypeSelectionView { type in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    addingType = type
                }
            }
        }
        .sheet(item: $addingType) { type in
            switch type {
            case .cash: CashEditView(existing: nil)
            case .electronicMoney: ElectronicMoneyEditView(existing: nil)
            case .bankAccount: BankAccountEditView(existing: nil)
            case .securities: SecuritiesEditView(existing: nil)
            case .crypto: CryptoEditView(existing: nil)
            case .other: PaymentReceiveEditView(existing: nil)
            }
        }
        .sheet(item: $editingOther) { PaymentReceiveEditView(existing: $0) }
        .sheet(item: $editingBank) { BankAccountEditView(existing: $0) }
    }

    // MARK: - 統合行

    private func unifiedRow(_ item: ReceiveMethodItem) -> some View {
        Button {
            switch item {
            case .other(let m): editingOther = m
            case .bank(let b):  editingBank = b
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    if case .bank(let b) = item, let sub = bankSubtitle(b) {
                        Text(sub)
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .frame(minHeight: AppLayout.selectionRowHeight)
        }
        .buttonStyle(.plain)
        .environment(\.editMode, .constant(.inactive))
    }

    private func bankSubtitle(_ bank: BankAccountData) -> String? {
        var parts: [String] = []
        if let balance = bank.initialBalance, balance > 0 {
            parts.append("初期残高：\(Int(balance))円")
        }
        if let m = bank.memo, !m.isEmpty {
            parts.append("メモ：\(m)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "　")
    }

    // MARK: - 並び替え（その他・銀行口座統合）

    private func moveAllItems(from source: IndexSet, to destination: Int) {
        var items = allActiveItems
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            switch item {
            case .other(var m):
                m.sortOrder = index
                PaymentMethodSettingDataSync.update(m)
            case .bank(var b):
                b.sortOrder = index
                BankAccountDataSync.update(b)
            }
        }
    }
}
