import SwiftUI

// MARK: - 電子マネー編集画面（追加・編集共通）

struct ElectronicMoneyEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    let existing: PaymentMethodSettingData?

    // MARK: 基本情報
    @State private var name: String = ""
    @State private var initialBalanceText: String = ""
    @State private var memo: String = ""

    // MARK: 用途
    @State private var useForPayment: Bool = true
    @State private var useForReceive: Bool = true

    // MARK: 資産・分析
    @State private var isAsset: Bool = true

    // MARK: 色
    @State private var colorHex: String = ""

    // MARK: UI 制御
    @State private var isEditingInitialBalance = false
    @State private var isDuplicateNameAlertPresented = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, memo }

    private var titleText: String {
        if let existing { return "\(existing.methodName)を編集" }
        return "電子マネーを追加"
    }

    private var deleteButtonText: String {
        if let existing { return "\(existing.methodName)を削除" }
        return "削除"
    }

    private var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        basicInfoCard
                        usageCard
                        assetAnalysisCard
                        colorCard

                        if existing != nil {
                            deleteButton
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, isEditingInitialBalance ? 340 : 32)
                }
                .background(AppColors.sheetBackground)
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("キャンセル") { dismiss() }
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(isSaveEnabled ? AppColors.main : Color.gray.opacity(0.4))
                            .disabled(!isSaveEnabled)
                    }
                }
                .onChange(of: focusedField) { _, newValue in
                    if newValue != nil { isEditingInitialBalance = false }
                }
                .alert("エラー", isPresented: $isDuplicateNameAlertPresented) {
                    Button("OK") {}
                } message: {
                    Text(DuplicateNameChecker.errorMessage)
                }
            }
            .onAppear { loadExisting() }

            if isEditingInitialBalance {
                SheetAmountKeyboardContainer(
                    amountText: $initialBalanceText,
                    isPresented: $isEditingInitialBalance
                )
            }
        }
        .animation(.easeOut(duration: 0.25), value: isEditingInitialBalance)
    }

    // MARK: - 基本情報

    private var basicInfoCard: some View {
        sectionCard(header: "基本情報") {
            HStack {
                Text("名前")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                TextField("例：こぶたPay", text: $name)
                    .focused($focusedField, equals: .name)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)

            Divider().padding(.horizontal, 16)

            HStack {
                Text("初期残高")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                HStack(spacing: 4) {
                    Text(initialBalanceText.isEmpty ? "0" : initialBalanceText)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(initialBalanceText.isEmpty ? Color.black.opacity(0.35) : Color.black.opacity(0.75))
                    if isEditingInitialBalance {
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
                DispatchQueue.main.async { isEditingInitialBalance = true }
            }

            Divider().padding(.horizontal, 16)

            HStack {
                Text("メモ")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                TextField("任意", text: $memo)
                    .focused($focusedField, equals: .memo)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)
        }
    }

    // MARK: - 用途

    private var usageCard: some View {
        sectionCard(header: "用途") {
            toggleRow("支払いに追加", isOn: $useForPayment)
            Divider().padding(.horizontal, 16)
            toggleRow("受け取りに追加", isOn: $useForReceive)
        }
    }

    // MARK: - 資産・分析

    private var assetAnalysisCard: some View {
        sectionCard(header: "資産") {
            toggleRow("資産に含める", isOn: $isAsset)
        }
    }

    // MARK: - 色

    private var colorCard: some View {
        sectionCard(header: "表示") {
            MoneyItemColorRow(colorHex: $colorHex)
        }
    }

    // MARK: - 共通カード

    private func sectionCard<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
    }

    // MARK: - Row Helpers

    private func toggleRow(_ label: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(AppFonts.rowTitle)
                .foregroundStyle(disabled ? Color.black.opacity(0.3) : Color.black.opacity(0.75))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppColors.main)
                .disabled(disabled)
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.selectionRowHeight)
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button {
            guard var e = existing else { return }
            deleteLinkedIncome(for: &e)
            e.isActive = false
            PaymentMethodSettingDataSync.update(e)
            SnapshotUpdateService.handle(.methodTouched(name: e.methodName))
            dismiss()
        } label: {
            Text(deleteButtonText)
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

    // MARK: - Load Existing

    private func loadExisting() {
        guard let e = existing else {
            colorHex = MoneyItemColorDefault.nextColorHex(
                forPaymentMethodType: PaymentMethodType.electronicMoney.rawValue,
                bookId: currentBookId ?? UUID()
            )
            return
        }
        name                = e.methodName
        initialBalanceText  = e.assetInitialBalance.map { String(Int($0)) } ?? ""
        memo                = e.memo ?? ""
        useForPayment       = e.showInInputPicker
        useForReceive       = e.useForReceive
        isAsset             = e.isAsset
        colorHex            = e.colorHex ?? MoneyItemColorDefault.nextColorHex(
            forPaymentMethodType: PaymentMethodType.electronicMoney.rawValue,
            bookId: currentBookId ?? UUID()
        )
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if DuplicateNameChecker.isDuplicatePaymentMethodName(
            trimmedName,
            type: PaymentMethodType.electronicMoney.rawValue,
            bookId: currentBookId,
            excluding: existing?.id
        ) {
            isDuplicateNameAlertPresented = true
            return
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)

        let balanceInt    = Int(initialBalanceText.trimmingCharacters(in: .whitespaces)) ?? 0
        let balanceDouble: Double? = (isAsset && balanceInt > 0) ? Double(balanceInt) : nil

        ensureInitialBalanceCategory()

        if var e = existing {
            let oldName = e.methodName

            e.methodName          = trimmedName
            e.memo                = trimmedMemo.isEmpty ? nil : trimmedMemo
            e.showInInputPicker   = useForPayment
            e.useForReceive       = useForReceive
            e.isAsset             = isAsset
            e.assetInitialBalance = balanceDouble
            e.colorHex            = colorHex
            e.updatedAt           = Date()
            syncInitialBalanceIncome(for: &e, newName: trimmedName, balanceInt: isAsset ? balanceInt : 0)
            PaymentMethodSettingDataSync.update(e)

            if oldName != trimmedName {
                SnapshotUpdateService.handle(.methodTouched(name: oldName))
            }
            SnapshotUpdateService.handle(.methodTouched(name: trimmedName))
        } else {
            var method = PaymentMethodSettingData(
                methodName: trimmedName,
                type: PaymentMethodType.electronicMoney.rawValue
            )
            method.memo               = trimmedMemo.isEmpty ? nil : trimmedMemo
            method.showInInputPicker  = useForPayment
            method.useForReceive      = useForReceive
            method.isAsset            = isAsset
            method.assetInitialBalance = balanceDouble
            method.colorHex           = colorHex
            method.bookId = currentBookId

            if isAsset && balanceInt > 0 {
                let income = makeInitialBalanceIncome(methodName: trimmedName, amount: balanceInt)
                IncomeDataSync.insert(income)
                method.assetInitialBalanceIncomeId = income.id
                SnapshotUpdateService.handle(.incomeCreated(date: income.date, bookId: income.bookId ?? UUID()))
            }

            PaymentMethodSettingDataSync.insert(method)
            SnapshotUpdateService.handle(.methodTouched(name: trimmedName))
        }

        dismiss()
    }

    // MARK: - 初期残高 IncomeData 同期

    private func syncInitialBalanceIncome(
        for method: inout PaymentMethodSettingData,
        newName: String,
        balanceInt: Int
    ) {
        if let incomeId = method.assetInitialBalanceIncomeId {
            if balanceInt <= 0 {
                if let income = findLinkedIncome(id: incomeId) {
                    let incomeBookId = income.bookId ?? UUID()
                    IncomeDataSync.delete(id: income.id)
                    SnapshotUpdateService.handle(.incomeDeleted(date: income.date, bookId: incomeBookId))
                }
                method.assetInitialBalanceIncomeId = nil
            } else {
                if var income = findLinkedIncome(id: incomeId) {
                    income.amount        = balanceInt
                    income.receiveMethod = newName
                    income.memo          = "\(newName)の初期残高"
                    IncomeDataSync.update(income)
                    SnapshotUpdateService.handle(.incomeUpdated(oldDate: income.date, newDate: income.date, bookId: income.bookId ?? UUID()))
                }
            }
        } else if balanceInt > 0 {
            let income = makeInitialBalanceIncome(methodName: newName, amount: balanceInt)
            IncomeDataSync.insert(income)
            method.assetInitialBalanceIncomeId = income.id
            SnapshotUpdateService.handle(.incomeCreated(date: income.date, bookId: income.bookId ?? UUID()))
        }
    }

    private func deleteLinkedIncome(for method: inout PaymentMethodSettingData) {
        guard let incomeId = method.assetInitialBalanceIncomeId else { return }
        if let income = findLinkedIncome(id: incomeId) {
            let incomeBookId = income.bookId ?? UUID()
            IncomeDataSync.delete(id: income.id)
            SnapshotUpdateService.handle(.incomeDeleted(date: income.date, bookId: incomeBookId))
        }
        method.assetInitialBalanceIncomeId = nil
    }

    private func makeInitialBalanceIncome(methodName: String, amount: Int) -> IncomeData {
        var income = IncomeData(
            amount: amount,
            date: Date(),
            receiveMethod: methodName,
            category: "初期残高",
            memo: "\(methodName)の初期残高"
        )
        // 支払い方法は帳簿ごとに分離されるため、初期残高収入も同じ帳簿に記録する
        income.bookId = currentBookId
        return income
    }

    private func findLinkedIncome(id: UUID) -> IncomeData? {
        IncomeDataSync.fetch(id: id)
    }

    private func ensureInitialBalanceCategory() {
        let bookId = currentBookId
        let existing = bookId.flatMap { id in
            CategoryDataSync.fetchAll(bookId: id).first { $0.name == "初期残高" && $0.type == "収入" }
        }
        guard existing == nil else { return }
        var category = CategoryData(name: "初期残高", colorHex: "#95A5A6", type: "収入", sortOrder: 999)
        category.bookId = bookId
        category.isProtected = true
        CategoryDataSync.insert(category)
    }
}
