import SwiftUI

// MARK: - Main View

struct BankAccountEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    let existing: BankAccountData?

    // MARK: 基本情報
    @State private var accountName: String = ""
    @State private var initialBalanceText: String = ""
    @State private var memo: String = ""

    // MARK: 用途
    @State private var addAsPaymentMethod = true
    @State private var addAsReceiveMethod = true

    // MARK: 資産・分析
    @State private var isAsset = true

    // MARK: 色
    @State private var colorHex: String = ""

    // MARK: UI 制御
    @State private var isEditingInitialBalance = false
    @State private var selfId: UUID = UUID()
    @State private var isDuplicateNameAlertPresented = false
    @FocusState private var textFieldFocus: TextFieldFocus?
    private enum TextFieldFocus { case name, memo }

    // MARK: - Computed：保存可否

    private var isSaveEnabled: Bool {
        !accountName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

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
                            deactivateButton
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, isEditingInitialBalance ? 340 : 32)
                }
                .background(AppColors.sheetBackground)
                .navigationTitle(existing == nil ? "銀行口座を追加" : "銀行口座を編集")
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
                .onChange(of: textFieldFocus) { _, newVal in
                    if newVal != nil { isEditingInitialBalance = false }
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
            rowContent(label: "口座名") {
                TextField("例：こぶた銀行", text: $accountName)
                    .focused($textFieldFocus, equals: .name)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }

            Divider().padding(.horizontal, 16)

            rowContent(label: "初期残高") {
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
            .contentShape(Rectangle())
            .onTapGesture {
                textFieldFocus = nil
                DispatchQueue.main.async { isEditingInitialBalance = true }
            }

            Divider().padding(.horizontal, 16)

            rowContent(label: "メモ") {
                TextField("任意", text: $memo)
                    .focused($textFieldFocus, equals: .memo)
                    .multilineTextAlignment(.trailing)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
            }
        }
    }

    // MARK: - 用途

    private var usageCard: some View {
        sectionCard(header: "用途") {
            toggleRow("支払いに追加", isOn: $addAsPaymentMethod)
            Divider().padding(.horizontal, 16)
            toggleRow("受け取りに追加", isOn: $addAsReceiveMethod)
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

    // MARK: - 削除ボタン

    private var deactivateButton: some View {
        Button {
            guard var e = existing else { return }
            deleteAllRecurringTransfers(for: &e)
            deleteLinkedIncome(for: &e)
            e.isActive = false
            BankAccountDataSync.update(e)
            dismiss()
        } label: {
            Text("この口座を削除")
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

    // MARK: - 既存データ読み込み

    private func loadExisting() {
        guard let e = existing else {
            colorHex = MoneyItemColorDefault.nextColorHexForBankAccount(bookId: currentBookId ?? UUID())
            return
        }
        accountName        = e.accountName
        initialBalanceText = e.initialBalance.map { String(Int($0)) } ?? ""
        memo               = e.memo ?? ""
        addAsPaymentMethod = e.showAsPaymentMethod
        addAsReceiveMethod = e.showAsReceiveMethod
        isAsset            = e.isAsset
        colorHex           = e.colorHex ?? MoneyItemColorDefault.nextColorHexForBankAccount(bookId: currentBookId ?? UUID())
    }

    // MARK: - 保存

    private func save() {
        let trimmedName = accountName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if DuplicateNameChecker.isDuplicateBankAccountName(
            trimmedName,
            bookId: currentBookId,
            excluding: existing?.id
        ) {
            isDuplicateNameAlertPresented = true
            return
        }

        let balanceInt    = Int(initialBalanceText.trimmingCharacters(in: .whitespaces)) ?? 0
        let balanceDouble: Double? = balanceInt > 0 ? Double(balanceInt) : nil
        let trimmedMemo   = memo.trimmingCharacters(in: .whitespaces)
        let memoOpt: String? = trimmedMemo.isEmpty ? nil : trimmedMemo

        ensureInitialBalanceCategory()

        if var e = existing {
            // isAssetは過去の全取引の資産集計対象を変えるため、変化したかどうかを記録しておく
            let isAssetChanged = e.isAsset != isAsset

            e.accountName         = trimmedName
            e.initialBalance      = balanceDouble
            e.memo                = memoOpt
            e.showAsPaymentMethod = addAsPaymentMethod
            e.showAsReceiveMethod = addAsReceiveMethod
            e.isAsset             = isAsset
            e.colorHex            = colorHex
            e.updatedAt           = Date()

            if let incomeId = e.initialBalanceIncomeId {
                if balanceInt <= 0 {
                    if let income = findLinkedIncome(id: incomeId) {
                        let incomeDate = income.date
                        let incomeBookId = income.bookId ?? UUID()
                        IncomeDataSync.delete(id: income.id)
                        SnapshotUpdateService.handle(.incomeDeleted(date: incomeDate, bookId: incomeBookId))
                    }
                    e.initialBalanceIncomeId = nil
                } else {
                    if var income = findLinkedIncome(id: incomeId) {
                        income.amount        = balanceInt
                        income.bankAccountId = e.id
                        income.receiveMethod = trimmedName
                        income.memo          = "\(trimmedName)の初期残高"
                        IncomeDataSync.update(income)
                        SnapshotUpdateService.handle(.incomeUpdated(oldDate: income.date, newDate: income.date, bookId: income.bookId ?? UUID()))
                    }
                }
            } else if balanceInt > 0 {
                let income = makeInitialBalanceIncome(for: e, amount: balanceInt)
                e.initialBalanceIncomeId = income.id
                IncomeDataSync.insert(income)
                SnapshotUpdateService.handle(.incomeCreated(date: income.date, bookId: income.bookId ?? UUID()))
            }

            if isAssetChanged {
                SnapshotUpdateService.handle(.fullRebuildRequested)
            }

            BankAccountDataSync.update(e)
        } else {
            var account = BankAccountData(
                id: selfId,
                accountName: trimmedName,
                initialBalance: balanceDouble,
                memo: memoOpt
            )
            account.showAsPaymentMethod = addAsPaymentMethod
            account.showAsReceiveMethod = addAsReceiveMethod
            account.isAsset              = isAsset
            account.colorHex             = colorHex
            account.bookId               = currentBookId

            if balanceInt > 0 {
                let income = makeInitialBalanceIncome(for: account, amount: balanceInt)
                account.initialBalanceIncomeId = income.id
                IncomeDataSync.insert(income)
                SnapshotUpdateService.handle(.incomeCreated(date: income.date, bookId: income.bookId ?? UUID()))
            }

            BankAccountDataSync.insert(account)
        }

        dismiss()
    }

    // MARK: - 定期振替の後片付け（口座削除時、紐づく定期振替も一緒に削除する）

    private func deleteAllRecurringTransfers(for account: inout BankAccountData) {
        var ids = Set(account.recurringTransferSettingIds)
        if let old = account.recurringTransferSettingId { ids.insert(old) }
        for id in ids {
            RecurringTransferSettingDataSync.delete(id: id)
        }
        account.recurringTransferSettingIds = []
        account.recurringTransferSettingId  = nil
    }

    // MARK: - 初期残高 IncomeData ヘルパー

    private func makeInitialBalanceIncome(for bank: BankAccountData, amount: Int) -> IncomeData {
        var income = IncomeData(
            amount: amount,
            date: Date(),
            receiveMethod: bank.accountName,
            category: "初期残高",
            memo: "\(bank.accountName)の初期残高",
            bankAccountId: bank.id
        )
        // 口座は帳簿ごとに分離されるため、初期残高収入も同じ帳簿に記録する
        income.bookId = currentBookId
        return income
    }

    private func findLinkedIncome(id: UUID) -> IncomeData? {
        IncomeDataSync.fetch(id: id)
    }

    // 口座削除時に、自動生成された初期残高のIncomeDataも一緒に削除する
    // （残さないと、口座を消してもカレンダー等の取引一覧に残り続けてしまう）
    private func deleteLinkedIncome(for account: inout BankAccountData) {
        guard let incomeId = account.initialBalanceIncomeId else { return }
        if let income = findLinkedIncome(id: incomeId) {
            let incomeDate = income.date
            let incomeBookId = income.bookId ?? UUID()
            IncomeDataSync.delete(id: income.id)
            SnapshotUpdateService.handle(.incomeDeleted(date: incomeDate, bookId: incomeBookId))
        }
        account.initialBalanceIncomeId = nil
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
