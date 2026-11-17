import SwiftUI

// 通常支払い方法・クレジットカード・銀行口座を統合表示するための一時的なラッパー
private enum PaymentItem: Identifiable {
    case regular(PaymentMethodSettingData)
    case creditCard(PaymentMethodSettingData)
    case bank(BankAccountData)

    var id: String {
        switch self {
        case .regular(let m):    return "r_\(m.id)"
        case .creditCard(let c): return "c_\(c.id)"
        case .bank(let b):       return "b_\(b.id)"
        }
    }

    var sortOrder: Int {
        switch self {
        case .regular(let m):    return m.sortOrder
        case .creditCard(let c): return c.sortOrder
        case .bank(let b):       return b.sortOrder
        }
    }

    var createdAt: Date {
        switch self {
        case .regular(let m):    return m.createdAt
        case .creditCard(let c): return c.createdAt
        case .bank(let b):       return b.createdAt
        }
    }
}

struct PaymentMethodSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    // 非アクティブ口座も含めて全件取得（削除後もサブテキストで名前を表示するため）
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    private var allSettings: [PaymentMethodSettingData] {
        allSettingsRaw.filter { $0.bookId == currentBookId }
    }
    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var isShowingTypeSelection = false
    @State private var editingMethod: PaymentMethodSettingData? = nil
    @State private var editingCard: PaymentMethodSettingData? = nil
    @State private var editingBank: BankAccountData? = nil
    // 追加する種類（1つの.sheet(item:)にまとめることで、.sheetの連結数を減らす。
    // 連結数が多いと型メタデータ解決が重くなり、シート遷移アニメーションが引っかかることがある）
    @State private var addingType: PaymentAddType? = nil

    // この画面は「有効な支払い方法の並び替え」専用。ロック中の項目は選択UIを出さず、一覧にも出さない
    // （有効/ロックの選択は各種類の個別設定画面（銀行口座・クレジットカード・その他）で行う）。
    private var allActiveMethods: [PaymentItem] {
        let regulars = allSettings
            .filter { $0.isActive && !$0.isLocked && $0.type != PaymentMethodType.creditCard.rawValue && $0.showInInputPicker }
            .map { PaymentItem.regular($0) }
        let cards = allSettings
            .filter { $0.isActive && !$0.isLocked && $0.type == PaymentMethodType.creditCard.rawValue && $0.showInInputPicker }
            .map { PaymentItem.creditCard($0) }
        let banks = bankAccounts
            .filter { $0.isActive && !$0.isLocked && $0.showAsPaymentMethod }
            .map { PaymentItem.bank($0) }
        return (regulars + cards + banks).sorted {
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
                        if allActiveMethods.isEmpty {
                            Text("支払いが登録されていません")
                                .font(AppFonts.caption)
                                .foregroundStyle(Color.black.opacity(0.35))
                        } else {
                            ForEach(allActiveMethods) { item in
                                unifiedRow(item)
                            }
                            .onMove(perform: moveAllMethods)
                        }

                        Button {
                            isShowingTypeSelection = true
                        } label: {
                            Label("支払いの追加", systemImage: "plus")
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
            .navigationTitle("支払い")
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
            PaymentMethodTypeSelectionView { type in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    addingType = type
                }
            }
        }
        .sheet(item: $addingType) { type in
            switch type {
            case .cash: CashEditView(existing: nil)
            case .creditCard: CreditCardEditView(existing: nil)
            case .electronicMoney: ElectronicMoneyEditView(existing: nil)
            case .debitCard: DebitCardEditView(existing: nil)
            case .bankAccount: BankAccountEditView(existing: nil)
            case .securities: SecuritiesEditView(existing: nil)
            case .crypto: CryptoEditView(existing: nil)
            case .other: PaymentReceiveEditView(existing: nil)
            }
        }
        .sheet(item: $editingMethod) { PaymentReceiveEditView(existing: $0) }
        .sheet(item: $editingCard) { CreditCardEditView(existing: $0) }
        .sheet(item: $editingBank) { BankAccountEditView(existing: $0) }
    }

    // MARK: - 統合行

    private func unifiedRow(_ item: PaymentItem) -> some View {
        Button {
            switch item {
            case .regular(let m):    editingMethod = m
            case .creditCard(let c): editingCard = c
            case .bank(let b):       editingBank = b
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(for: item))
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    if let sub = subtitle(for: item) {
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

    private func displayName(for item: PaymentItem) -> String {
        switch item {
        case .regular(let m):    return m.methodName
        case .creditCard(let c): return c.methodName
        case .bank(let b):       return b.accountName
        }
    }

    private func subtitle(for item: PaymentItem) -> String? {
        switch item {
        case .regular: return nil
        case .creditCard(let c):
            var parts: [String] = []
            if let closing = c.closingDay {
                parts.append("締め日：\(closing == 31 ? "月末" : "\(closing)日")")
            }
            if let withdrawal = c.withdrawalDay {
                parts.append("引き落とし：翌月\(withdrawal == 31 ? "末" : "\(withdrawal)日")")
            }
            let dayLine = parts.joined(separator: "　")
            // 引き落とし口座名（UUID優先、旧文字列フィールドにフォールバック）
            let bankLine = withdrawalBankName(for: c)
            switch (dayLine.isEmpty, bankLine) {
            case (true,  let b?): return b
            case (false, let b?): return dayLine + "\n" + b
            case (_,     nil):    return dayLine.isEmpty ? nil : dayLine
            }
        case .bank: return nil
        }
    }

    // 引き落とし口座名を返す（非アクティブ口座も名前が残るよう allBankAccounts を参照）
    private func withdrawalBankName(for card: PaymentMethodSettingData) -> String? {
        if let id = card.withdrawalBankAccountId,
           let name = allBankAccounts.first(where: { $0.id == id })?.accountName {
            return name
        }
        // 旧フィールド（移行前の文字列）があれば表示
        if let old = card.bankAccount, !old.isEmpty { return old }
        return nil
    }

    // MARK: - 並び替え（3種類統合）

    private func moveAllMethods(from source: IndexSet, to destination: Int) {
        var items = allActiveMethods
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            switch item {
            case .regular(var m):
                m.sortOrder = index
                PaymentMethodSettingDataSync.update(m)
            case .creditCard(var c):
                c.sortOrder = index
                PaymentMethodSettingDataSync.update(c)
            case .bank(var b):
                b.sortOrder = index
                BankAccountDataSync.update(b)
            }
        }
    }
}
