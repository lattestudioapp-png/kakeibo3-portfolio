import SwiftUI

struct RecurringIncomeEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: RecurringIncomeData?

    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()

    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var paymentSettings: [PaymentMethodSettingData] {
        paymentSettingsRaw.filter { $0.bookId == currentBookId }
    }
    private var categoryDataList: [CategoryData] {
        categoryDataListRaw.filter { $0.bookId == currentBookId }
    }

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var memo: String = ""
    @State private var selectedCategoryName: String = ""
    @State private var selectedReceiveType: String = ""
    @State private var selectedReceiveId: UUID? = nil
    @State private var holidayAdjustment: WeekendHolidayAdjustment = .shiftLater
    @State private var dayOfMonth: Int = 1
    @State private var startDate: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    @State private var isShowingStartMonthPicker = false
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var showDeleteConfirm = false
    @State private var isAmountKeyboardPresented = false
    @State private var showsCategoryAdd = false
    @State private var showsReceiveAdd = false
    @State private var receiveIdsBeforeAdd: Set<UUID> = []
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, memo
    }

    // MARK: - 受け取り方法の選択候補

    // ReceiveMethodSettingView と同じ抽出ロジック
    private var receiveCandidates: [AssetPickerEntry] {
        let banks = bankAccounts
            .filter { $0.isActive && $0.showAsReceiveMethod }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { AssetPickerEntry(id: $0.id, name: $0.accountName, assetType: "bankAccount", colorHex: $0.colorHex) }
        let methods = paymentSettings
            .filter { $0.isActive && $0.useForReceive && $0.type != PaymentMethodType.creditCard.rawValue }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map { AssetPickerEntry(id: $0.id, name: $0.methodName, assetType: "paymentMethod", colorHex: $0.colorHex) }
        return banks + methods
    }

    private var selectedReceiveName: String {
        guard let id = selectedReceiveId else { return "未設定" }
        return receiveCandidates.first { $0.id == id }?.name ?? "不明"
    }

    private func newlyAddedReceiveEntry() -> AssetPickerEntry? {
        let currentIds = Set(paymentSettings.map(\.id) + bankAccounts.map(\.id))
        let newIds = currentIds.subtracting(receiveIdsBeforeAdd)
        guard newIds.count == 1, let newId = newIds.first else { return nil }
        return receiveCandidates.first { $0.id == newId }
    }

    // MARK: - カテゴリ（収入）

    private var incomeCategories: [String] {
        categoryDataList.filter { $0.type == "収入" && !$0.isSuspended }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.name }
    }

    // 無料版の上限超過でロック中の項目は編集不可（削除のみ可能）
    private var isLocked: Bool {
        existing?.isLocked ?? false
    }

    private var canSave: Bool {
        !isLocked
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (Int(amountText) ?? 0) > 0
            && !selectedCategoryName.isEmpty
            && selectedReceiveId != nil
    }

    private var holidayAdjustmentLabel: String {
        switch holidayAdjustment {
        case .shiftLater: return "翌営業日"
        case .shiftEarlier: return "前営業日"
        case .none: return "何もしない"
        }
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
            .navigationTitle(existing != nil ? "定期収入を編集" : "定期収入を追加")
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
            .onChange(of: focusedField) { _, newValue in
                // 文字キーボードが出たら電卓キーボードは必ず閉じる（同時表示にしない）
                if newValue != nil { isAmountKeyboardPresented = false }
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
        .fullScreenCover(isPresented: $showsCategoryAdd) {
            CategoryEditView(selectedType: "収入")
        }
        .sheet(isPresented: $showsReceiveAdd) {
            ReceiveMethodSettingView()
        }
        .onChange(of: showsReceiveAdd) { _, isPresented in
            guard !isPresented else { return }
            if let newEntry = newlyAddedReceiveEntry() {
                selectedReceiveId = newEntry.id
                selectedReceiveType = newEntry.assetType
            }
        }
        .alert("「\(existing?.name ?? "")」を削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { delete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この定期収入を削除します。よろしいですか？")
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
            // 名前
            formRow(label: "名前") {
                TextField("例：給料", text: $name)
                    .focused($focusedField, equals: .name)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }

            Divider().padding(.horizontal, 16)

            // 金額
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
                focusedField = nil
                DispatchQueue.main.async { isAmountKeyboardPresented = true }
            }

            Divider().padding(.horizontal, 16)

            // メモ（任意）
            formRow(label: "メモ") {
                TextField("任意", text: $memo)
                    .focused($focusedField, equals: .memo)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }

            Divider().padding(.horizontal, 16)

            // カテゴリ（必須）
            formRow(label: "カテゴリ") {
                Menu {
                    ForEach(incomeCategories, id: \.self) { cat in
                        Button(cat) { selectedCategoryName = cat }
                    }
                    Divider()
                    Button {
                        showsCategoryAdd = true
                    } label: {
                        Label("新しく追加", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedCategoryName.isEmpty ? "未設定" : selectedCategoryName)
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(
                                selectedCategoryName.isEmpty
                                    ? Color.black.opacity(0.35) : AppColors.main
                            )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                selectedCategoryName.isEmpty
                                    ? Color.black.opacity(0.3) : AppColors.main
                            )
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    focusedField = nil
                    isAmountKeyboardPresented = false
                })
            }

            Divider().padding(.horizontal, 16)

            // 受け取り方法（必須）
            formRow(label: "受け取り方法") {
                Menu {
                    ForEach(receiveCandidates) { entry in
                        Button(entry.name) {
                            selectedReceiveId = entry.id
                            selectedReceiveType = entry.assetType
                        }
                    }
                    Divider()
                    Button {
                        receiveIdsBeforeAdd = Set(paymentSettings.map(\.id) + bankAccounts.map(\.id))
                        showsReceiveAdd = true
                    } label: {
                        Label("新しく追加", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedReceiveId == nil ? "未設定" : selectedReceiveName)
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(
                                selectedReceiveId == nil
                                    ? Color.black.opacity(0.35) : AppColors.main
                            )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                selectedReceiveId == nil
                                    ? Color.black.opacity(0.3) : AppColors.main
                            )
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    focusedField = nil
                    isAmountKeyboardPresented = false
                })
            }

            // 金融機関が休業日の場合（受け取り方法が銀行口座の時だけ表示。CreditCardEditViewと同じUIを再利用）
            if selectedReceiveType == "bankAccount" {
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

            // 受け取り日
            formRow(label: "受け取り日") {
                Menu {
                    ForEach(1...31, id: \.self) { day in
                        Button("毎月\(day)日") { dayOfMonth = day }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("毎月\(dayOfMonth)日")
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(AppColors.main)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.main)
                    }
                }
            }

            Divider().padding(.horizontal, 16)

            // 開始月
            formRow(label: "開始月") {
                Button {
                    pickerYear = Calendar.current.component(.year, from: startDate)
                    pickerMonth = Calendar.current.component(.month, from: startDate)
                    isShowingStartMonthPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(formattedStartMonth)
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(AppColors.main)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.main)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
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
            Text("この定期収入を削除")
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
        name = e.name
        amountText = e.amount > 0 ? "\(e.amount)" : ""
        memo = e.memo
        selectedCategoryName = e.categoryName
        selectedReceiveId = e.receiveMethodId
        selectedReceiveType = e.receiveMethodType
        holidayAdjustment = WeekendHolidayAdjustment(rawValue: e.holidayAdjustment) ?? .none
        dayOfMonth = e.dayOfMonth
        startDate = e.startDate
    }

    private func save() {
        guard !isLocked else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let amount = Int(amountText) ?? 0
        guard amount > 0 else { return }

        var recurringIncome: RecurringIncomeData
        if var e = existing {
            e.name = trimmedName
            e.amount = amount
            e.memo = memo
            e.categoryName = selectedCategoryName
            e.receiveMethodType = selectedReceiveType
            e.receiveMethodId = selectedReceiveId
            // 受け取り方法を銀行口座以外へ変更していても値は保持したまま保存する（再度銀行口座を
            // 選んだ時に以前の設定へ復元されるようにするため。データを破壊しない設計）。
            e.holidayAdjustment = holidayAdjustment.rawValue
            e.dayOfMonth = dayOfMonth
            e.startDate = startDate
            e.updatedAt = Date()
            recurringIncome = e
            RecurringIncomeDataSync.update(e)
        } else {
            var item = RecurringIncomeData(
                name: trimmedName,
                amount: amount,
                categoryName: selectedCategoryName,
                receiveMethodType: selectedReceiveType,
                receiveMethodId: selectedReceiveId,
                dayOfMonth: dayOfMonth,
                startDate: startDate,
                memo: memo
            )
            item.bookId = currentBookId
            item.holidayAdjustment = holidayAdjustment.rawValue
            RecurringIncomeDataSync.insert(item)
            recurringIncome = item
        }

        let receiveName = selectedReceiveId == nil ? "" : selectedReceiveName
        if let bookId = recurringIncome.bookId ?? currentBookId {
            RecurringEntryGenerator.generateIncomeEntries(for: recurringIncome, methodName: receiveName, bookId: bookId)
        }
        dismiss()
    }

    private func delete() {
        guard var e = existing else { return }
        e.isActive = false
        RecurringIncomeDataSync.update(e)
        dismiss()
    }
}
