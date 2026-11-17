import SwiftUI

struct RecurringTransferEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: RecurringTransferSettingData?

    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()

    private var bankAccounts: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethods: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @State private var fromId: UUID? = nil
    @State private var toId: UUID? = nil
    @State private var holidayAdjustment: WeekendHolidayAdjustment = .shiftLater
    @State private var amountText: String = ""
    @State private var day: Int = 1
    @State private var startDate: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var isShowingStartMonthPicker = false
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var showDeleteConfirm = false
    @State private var isAmountKeyboardPresented = false

    // MARK: - 移動元・移動先の候補（銀行口座 + 支払い方法。受け取り専用は対象外）

    private var candidates: [AssetPickerEntry] {
        let banks = bankAccounts.filter { $0.isActive && $0.bookId == currentBookId }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { AssetPickerEntry(id: $0.id, name: $0.accountName, assetType: TransferAccountType.bank.rawValue, colorHex: $0.colorHex) }
        let methods = paymentMethods.filter { $0.isActive && $0.bookId == currentBookId }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map { AssetPickerEntry(id: $0.id, name: $0.methodName, assetType: TransferAccountType.paymentMethod.rawValue, colorHex: $0.colorHex) }
        return banks + methods
    }

    private func name(for id: UUID?) -> String {
        guard let id else { return "未設定" }
        return candidates.first { $0.id == id }?.name ?? "不明"
    }

    // 移動元・移動先のいずれかが銀行口座の場合のみ「金融機関が休業日の場合」を表示する
    private var isBankAccountInvolved: Bool {
        let fromType = candidates.first { $0.id == fromId }?.assetType
        let toType = candidates.first { $0.id == toId }?.assetType
        return fromType == TransferAccountType.bank.rawValue || toType == TransferAccountType.bank.rawValue
    }

    private var holidayAdjustmentLabel: String {
        switch holidayAdjustment {
        case .shiftLater: return "翌営業日"
        case .shiftEarlier: return "前営業日"
        case .none: return "何もしない"
        }
    }

    // 無料版の上限超過でロック中の項目は編集不可（削除のみ可能）
    private var isLocked: Bool {
        existing?.isLocked ?? false
    }

    private var canSave: Bool {
        !isLocked
            && fromId != nil && toId != nil && fromId != toId
            && (Int(amountText) ?? 0) > 0
    }

    private var formattedStartMonth: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: startDate)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        if isLocked {
                            lockedNotice
                        }
                        formCard
                            .disabled(isLocked)
                            .opacity(isLocked ? 0.5 : 1)
                        if existing != nil {
                            deleteButton.padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .background(AppColors.sheetBackground)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(existing != nil ? "定期振替を編集" : "定期振替を追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("キャンセル") { dismiss() }
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? AppColors.main : Color.gray.opacity(0.4))
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear { loadExisting() }
            .sheet(isPresented: $isShowingStartMonthPicker) {
                YearMonthPickerView(year: $pickerYear, month: $pickerMonth) {
                    var comps = DateComponents()
                    comps.year = pickerYear
                    comps.month = pickerMonth
                    comps.day = 1
                    startDate = Calendar.current.date(from: comps) ?? startDate
                }
            }
            .alert("この定期振替を削除しますか？", isPresented: $showDeleteConfirm) {
                Button("削除", role: .destructive) { delete() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この定期振替を削除します。よろしいですか？")
            }

            if isAmountKeyboardPresented {
                SheetAmountKeyboardContainer(amountText: $amountText, isPresented: $isAmountKeyboardPresented)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isAmountKeyboardPresented)
    }

    // MARK: - フォームカード

    private var formCard: some View {
        VStack(spacing: 0) {
            formRow(label: "移動元") {
                Menu {
                    ForEach(candidates) { entry in
                        Button(entry.name) { fromId = entry.id }
                    }
                } label: {
                    menuLabel(text: fromId == nil ? "未設定" : name(for: fromId), isSet: fromId != nil)
                }
            }

            Divider().padding(.horizontal, 16)

            formRow(label: "移動先") {
                Menu {
                    ForEach(candidates) { entry in
                        Button(entry.name) { toId = entry.id }
                    }
                } label: {
                    menuLabel(text: toId == nil ? "未設定" : name(for: toId), isSet: toId != nil)
                }
            }

            // 金融機関が休業日の場合（移動元/移動先のどちらかが銀行口座の時だけ表示。
            // CreditCardEditView/FixedExpenseEditViewと同じUIを再利用）
            if isBankAccountInvolved {
                Divider().padding(.horizontal, 16)
                formRow(label: "金融機関が休業日の場合") {
                    Menu {
                        Button("翌営業日") { holidayAdjustment = .shiftLater }
                        Button("前営業日") { holidayAdjustment = .shiftEarlier }
                        Button("何もしない") { holidayAdjustment = .none }
                    } label: {
                        CardRowValueLabel(text: holidayAdjustmentLabel, color: AppColors.main)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.horizontal, 16)

            HStack {
                Text("金額")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                HStack(spacing: 4) {
                    Text(amountText.isEmpty ? "0" : amountText)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(amountText.isEmpty ? Color.black.opacity(0.35) : Color.black.opacity(0.75))
                    if isAmountKeyboardPresented {
                        BlinkingCursorView(height: 18)
                    }
                    Text("円")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                isAmountKeyboardPresented = true
            }

            Divider().padding(.horizontal, 16)

            formRow(label: "振替日") {
                Menu {
                    ForEach(1...31, id: \.self) { d in
                        Button(d == 31 ? "月末" : "毎月\(d)日") { day = d }
                    }
                } label: {
                    menuLabel(text: day == 31 ? "月末" : "毎月\(day)日", isSet: true)
                }
            }

            Divider().padding(.horizontal, 16)

            formRow(label: "開始月") {
                Button {
                    pickerYear = Calendar.current.component(.year, from: startDate)
                    pickerMonth = Calendar.current.component(.month, from: startDate)
                    isShowingStartMonthPicker = true
                } label: {
                    menuLabel(text: formattedStartMonth, isSet: true)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    private func menuLabel(text: String, isSet: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(AppFonts.rowTitle)
                .foregroundStyle(isSet ? AppColors.main : Color.black.opacity(0.35))
            Image(systemName: "chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(isSet ? AppColors.main : Color.black.opacity(0.3))
        }
    }

    private func formRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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

    // MARK: - ロック中の案内

    private var lockedNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.gray.opacity(0.6))
                .padding(.top, 2)
            Text("無料版の上限を超えているためロック中です。編集するにはプレミアムへ登録するか、削除してください。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .padding(16)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    // MARK: - 削除ボタン

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Text("この定期振替を削除")
                .font(AppFonts.button)
                .foregroundStyle(Color.red.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.selectionRowHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - アクション

    private func loadExisting() {
        guard let e = existing else { return }
        fromId = e.fromMethodId
        toId = e.toMethodId
        holidayAdjustment = WeekendHolidayAdjustment(rawValue: e.holidayAdjustment) ?? .none
        amountText = e.amount > 0 ? "\(e.amount)" : ""
        day = e.day
        startDate = e.startDate
    }

    private func save() {
        guard !isLocked else { return }
        guard let fId = fromId, let tId = toId, fId != tId else { return }
        let amount = Int(amountText) ?? 0
        guard amount > 0 else { return }
        guard let fromEntry = candidates.first(where: { $0.id == fId }),
              let toEntry = candidates.first(where: { $0.id == tId })
        else { return }

        var setting: RecurringTransferSettingData
        let isNew = existing == nil
        if var e = existing {
            e.fromMethodId   = fId
            e.fromMethodName = fromEntry.name
            e.fromType       = fromEntry.assetType
            e.toMethodId     = tId
            e.toMethodName   = toEntry.name
            e.toType         = toEntry.assetType
            e.amount         = amount
            e.day            = day
            e.startDate      = startDate
            e.updatedAt      = Date()
            // 移動元/移動先を銀行口座以外へ変更していても値は保持したまま保存する（再度銀行口座を
            // 選んだ時に以前の設定へ復元されるようにするため。データを破壊しない設計）。
            e.holidayAdjustment = holidayAdjustment.rawValue
            setting = e
        } else {
            var item = RecurringTransferSettingData(
                fromMethodId: fId, fromMethodName: fromEntry.name, fromType: fromEntry.assetType,
                toMethodId: tId, toMethodName: toEntry.name, toType: toEntry.assetType,
                amount: amount, day: day, startDate: startDate
            )
            item.bookId = currentBookId
            item.holidayAdjustment = holidayAdjustment.rawValue
            setting = item
        }

        if isNew {
            RecurringTransferSettingDataSync.insert(setting)
        } else {
            RecurringTransferSettingDataSync.update(setting)
        }

        RecurringEntryGenerator.syncRecurringTransferLinkage(
            settingId: setting.id,
            fromType: fromEntry.assetType, fromId: fId,
            toType: toEntry.assetType, toId: tId,
            bankAccounts: bankAccounts,
            paymentMethods: paymentMethods
        )
        if let bookId = setting.bookId ?? currentBookId {
            RecurringEntryGenerator.generateTransferEntries(for: setting, bookId: bookId)
        }
        dismiss()
    }

    private func delete() {
        guard var e = existing else { return }
        e.isActive = false
        RecurringTransferSettingDataSync.update(e)
        dismiss()
    }
}
