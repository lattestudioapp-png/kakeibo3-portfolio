import SwiftUI

struct CreditCardEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    let existing: PaymentMethodSettingData?

    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()

    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var name: String = ""
    @State private var closingDay: Int = 0
    @State private var withdrawalDay: Int = 0
    @State private var holidayAdjustment: WeekendHolidayAdjustment = .shiftLater
    @State private var selectedBankAccountId: UUID? = nil
    @State private var isAddingBankAccount: Bool = false
    @State private var isDuplicateNameAlertPresented = false
    @State private var colorHex: String = ""

    // アクティブな銀行口座（選択候補）。削除済み(isActive=false)の口座は候補に出さない
    private var pickerBankOptions: [BankAccountData] {
        allBankAccounts
            .filter { $0.isActive }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    // 選択中の銀行口座の表示名（未設定なら旧フィールドにフォールバック）
    private var selectedBankDisplayName: String {
        if let id = selectedBankAccountId,
           let bank = allBankAccounts.first(where: { $0.id == id }) {
            return bank.accountName
        }
        return "未設定"
    }

    // 引き落とし口座がロックされているか（無料版で上限超過によりロックされた場合の警告用）
    private var linkedBankAccount: BankAccountData? {
        guard let id = selectedBankAccountId else { return nil }
        return allBankAccounts.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    withdrawalLockedWarning
                    formCard

                    if existing != nil {
                        deleteButton
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle(existing == nil ? "カードを追加" : "カードを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Color.gray.opacity(0.4) : AppColors.main)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let e = existing {
                name = e.methodName
                closingDay = e.closingDay ?? 0
                withdrawalDay = e.withdrawalDay ?? 0
                holidayAdjustment = e.resolvedHolidayAdjustment
                // 紐付け先の銀行口座が削除済み、または現在帳簿に存在しない場合は未選択にする
                if let linkedId = e.withdrawalBankAccountId,
                   allBankAccounts.contains(where: { $0.id == linkedId && $0.isActive }) {
                    selectedBankAccountId = linkedId
                } else {
                    selectedBankAccountId = nil
                }
                colorHex = e.colorHex ?? MoneyItemColorDefault.nextColorHex(
                    forPaymentMethodType: PaymentMethodType.creditCard.rawValue,
                    bookId: currentBookId ?? UUID()
                )
            } else {
                colorHex = MoneyItemColorDefault.nextColorHex(
                    forPaymentMethodType: PaymentMethodType.creditCard.rawValue,
                    bookId: currentBookId ?? UUID()
                )
            }
        }
        .alert("エラー", isPresented: $isDuplicateNameAlertPresented) {
            Button("OK") {}
        } message: {
            Text(DuplicateNameChecker.errorMessage)
        }
    }

    // MARK: - 引き落とし口座ロック警告

    @ViewBuilder
    private var withdrawalLockedWarning: some View {
        if let bank = linkedBankAccount, bank.isLocked {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("引き落とし口座が利用できません")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.85))
                    Text("このクレジットカードに紐付いている「\(bank.accountName)」がロックされています。\n無料版で利用する口座を変更するか、プレミアムへ再登録してください。")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .padding(16)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            rowContent(label: "カード名") {
                TextField("例：こぶたカード", text: $name)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }

            Divider().padding(.horizontal, 16)

            rowContent(label: "締め日") {
                let label = closingDay == 0 ? "未設定" : (closingDay == 31 ? "月末" : "\(closingDay)日")
                Menu {
                    Button("未設定") { closingDay = 0 }
                    ForEach(1...30, id: \.self) { d in
                        Button("\(d)日") { closingDay = d }
                    }
                    Button("月末") { closingDay = 31 }
                } label: {
                    CardRowValueLabel(text: label, color: closingDay == 0 ? Color.black.opacity(0.35) : AppColors.main)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.horizontal, 16)

            rowContent(label: "引き落とし日") {
                let label = withdrawalDay == 0 ? "未設定" : (withdrawalDay == 31 ? "翌月末" : "翌月\(withdrawalDay)日")
                Menu {
                    Button("未設定") { withdrawalDay = 0 }
                    ForEach(1...30, id: \.self) { d in
                        Button("翌月\(d)日") { withdrawalDay = d }
                    }
                    Button("翌月末") { withdrawalDay = 31 }
                } label: {
                    CardRowValueLabel(text: label, color: withdrawalDay == 0 ? Color.black.opacity(0.35) : AppColors.main)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.horizontal, 16)

            rowContent(label: "金融機関が休業日の場合") {
                Menu {
                    Button("翌営業日") { holidayAdjustment = .shiftLater }
                    Button("前営業日") { holidayAdjustment = .shiftEarlier }
                    Button("何もしない") { holidayAdjustment = .none }
                } label: {
                    CardRowValueLabel(text: holidayAdjustmentLabel, color: AppColors.main)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.horizontal, 16)

            // 引き落とし口座: 登録済み銀行口座から選択
            rowContent(label: "引き落とし口座") {
                if pickerBankOptions.isEmpty {
                    // 銀行口座が0件: タップで銀行口座追加画面へ遷移
                    Button {
                        isAddingBankAccount = true
                    } label: {
                        CardRowValueLabel(text: "未設定", color: Color.black.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $isAddingBankAccount) {
                        BankAccountEditView(existing: nil)
                    }
                } else {
                    let bankLabel = selectedBankAccountId.flatMap { id in
                        pickerBankOptions.first(where: { $0.id == id })?.accountName
                    } ?? "未設定"
                    Menu {
                        Button("未設定") { selectedBankAccountId = nil }
                        ForEach(pickerBankOptions) { bank in
                            Button {
                                selectedBankAccountId = bank.id
                            } label: {
                                if bank.isLocked {
                                    Label(bank.accountName, systemImage: "lock.fill")
                                } else {
                                    Text(bank.accountName)
                                }
                            }
                            .disabled(bank.isLocked)
                        }
                    } label: {
                        CardRowValueLabel(
                            text: bankLabel,
                            color: selectedBankAccountId == nil ? Color.black.opacity(0.35) : AppColors.main
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.horizontal, 16)

            MoneyItemColorRow(colorHex: $colorHex)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1)
        )
    }

    private var holidayAdjustmentLabel: String {
        switch holidayAdjustment {
        case .shiftLater: return "翌営業日"
        case .shiftEarlier: return "前営業日"
        case .none: return "何もしない"
        }
    }

    private func rowContent<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.selectionRowHeight)
    }

    private var deleteButton: some View {
        Button {
            if var e = existing {
                e.isActive = false
                PaymentMethodSettingDataSync.update(e)
                SnapshotUpdateService.handle(.methodTouched(name: e.methodName))
                dismiss()
            }
        } label: {
            Text("このカードを削除")
                .font(AppFonts.button)
                .foregroundStyle(Color.red.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.selectionRowHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if DuplicateNameChecker.isDuplicatePaymentMethodName(
            trimmedName,
            type: PaymentMethodType.creditCard.rawValue,
            bookId: currentBookId,
            excluding: existing?.id
        ) {
            isDuplicateNameAlertPresented = true
            return
        }

        let closingDayOpt: Int? = closingDay > 0 ? closingDay : nil
        let withdrawalDayOpt: Int? = withdrawalDay > 0 ? withdrawalDay : nil

        if var e = existing {
            let oldName = e.methodName

            e.methodName = trimmedName
            e.closingDay = closingDayOpt
            e.withdrawalDay = withdrawalDayOpt
            // 旧Boolフィールドは以後書き込まない（凍結）。新方式のholidayAdjustmentだけを保存する。
            e.holidayAdjustment = holidayAdjustment.rawValue
            e.withdrawalBankAccountId = selectedBankAccountId
            // UUID で管理するようになったため旧フィールドをクリア
            if selectedBankAccountId != nil { e.bankAccount = nil }
            e.colorHex = colorHex
            e.updatedAt = Date()
            PaymentMethodSettingDataSync.update(e)

            if oldName != trimmedName {
                SnapshotUpdateService.handle(.methodTouched(name: oldName))
            }
            SnapshotUpdateService.handle(.methodTouched(name: trimmedName))
        } else {
            var card = PaymentMethodSettingData(
                methodName: trimmedName,
                type: PaymentMethodType.creditCard.rawValue,
                closingDay: closingDayOpt,
                withdrawalDay: withdrawalDayOpt,
                withdrawalBankAccountId: selectedBankAccountId
            )
            card.bookId = currentBookId
            card.holidayAdjustment = holidayAdjustment.rawValue
            card.colorHex = colorHex
            SnapshotUpdateService.handle(.methodTouched(name: trimmedName))
            PaymentMethodSettingDataSync.insert(card)
        }
        dismiss()
    }
}
