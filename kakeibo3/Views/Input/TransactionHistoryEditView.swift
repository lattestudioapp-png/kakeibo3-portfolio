import SwiftUI
import Combine

// MARK: - 履歴編集画面

struct TransactionHistoryEditView: View {
    let item: TransactionListItem
    let onClose: () -> Void

    // MARK: - SwiftData

    @StateObject private var incomeDataObserver = IncomeDataSync.observer()
    private var incomeDataList: [IncomeData] { incomeDataObserver.items }
    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var expenseDataList: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountSettingsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var receiveMethodDataObserver = ReceiveMethodDataSync.observer()
    private var receiveMethodSettingsRaw: [ReceiveMethodData] { receiveMethodDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    // 編集対象の取引が属する帳簿（無ければ現在選択中の帳簿にフォールバック）で
    // カテゴリー・支払い方法・受け取り方法・銀行口座を絞り込む。
    private var effectiveBookId: UUID? {
        item.bookId ?? BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var categoryDataList: [CategoryData] {
        categoryDataListRaw.filter { $0.bookId == effectiveBookId }
    }
    private var bankAccountSettings: [BankAccountData] {
        bankAccountSettingsRaw.filter { $0.bookId == effectiveBookId }
    }
    private var paymentMethodSettings: [PaymentMethodSettingData] {
        paymentMethodSettingsRaw.filter { $0.bookId == effectiveBookId }
    }
    private var receiveMethodSettings: [ReceiveMethodData] {
        receiveMethodSettingsRaw.filter { $0.bookId == effectiveBookId }
    }

    // MARK: - ViewModel

    @StateObject private var inputViewModel = InputViewModel()
    @StateObject private var editViewModel: TransactionHistoryEditViewModel
    @StateObject private var categoryViewModel = CategoryEditViewModel()

    // MARK: - フォーカス管理

    @FocusState private var focusedField: InputFocusedField?

    // MARK: - Layout

    private let layout = InputFormLayout()

    // MARK: - ページングスワイプ状態

    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingPage = false
    private let swipeCommitThreshold: CGFloat = 80

    // MARK: - 削除アラート

    @State private var isDeleteAlertPresented = false

    // MARK: - 写真選択シート
    //
    // この画面は CalendarView からは通常のオーバーレイ、SearchView / AssetDetailView /
    // CategoryAnalysisDetailView からは fullScreenCover 経由で表示される。
    // MainView レベルの PhotoDialogCoordinator（オーバーレイ）は fullScreenCover の
    // さらに内側に重なると背面に隠れてしまうため、この画面専用に写真メニューの状態を持つ。

    @State private var isPhotoActionSheetPresented = false
    @State private var showsCamera = false
    @State private var showsLibrary = false

    // MARK: - 支払い/受け取り方法設定シート

    @State private var isPaymentSettingPresented = false
    @State private var isReceiveSettingPresented = false

    // 「＋新しく追加」を押した時点の支払い方法/銀行口座IDを控えておき、一覧画面から戻ってきた時に
    // 増えた1件を検出して自動選択するために使う
    @State private var methodIdsBeforeAdd: Set<UUID> = []

    // MARK: - 削除ボタン定数

    private let deleteButtonTextColor = Color.red.opacity(0.70)
    private let deleteButtonHeight: CGFloat = AppLayout.selectionRowHeight
    private let deleteButtonTopPadding: CGFloat = 8
    private let deleteButtonBottomPadding: CGFloat = 24

    // MARK: - 初期化

    init(item: TransactionListItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _editViewModel = StateObject(wrappedValue: TransactionHistoryEditViewModel(item: item))
    }

    // MARK: - ページ状態

    private var selectedPageIndex: Int {
        inputViewModel.selectedType == inputViewModel.expenseSetting.typeName ? 0 : 1
    }

    private func baseOffset(width: CGFloat) -> CGFloat {
        selectedPageIndex == 0 ? 0 : -width
    }

    // MARK: - カテゴリー一覧

    // 使用停止中のカテゴリーは新規選択候補から除外されるが、この取引で現在使われている
    // カテゴリーが使用停止中でも、編集画面では選択中のカテゴリーとして表示し続ける。
    private var expenseCategoryNames: [String] {
        var names = categoryViewModel.categoryNames(
            type: inputViewModel.expenseSetting.typeName,
            categories: categoryDataList
        )
        if item.kind == .expense, !names.contains(item.category) {
            names.append(item.category)
        }
        return names
    }

    private var incomeCategoryNames: [String] {
        var names = categoryViewModel.categoryNames(
            type: inputViewModel.incomeSetting.typeName,
            categories: categoryDataList
        )
        if item.kind == .income, !names.contains(item.category) {
            names.append(item.category)
        }
        return names
    }

    // MARK: - body

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                headerArea
                formContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                deleteButton
            }

            if inputViewModel.isCalculatorKeyboardPresented {
                NormalAmountKeyboardContainer(
                    amountText: $inputViewModel.amountText,
                    isPresented: $inputViewModel.isCalculatorKeyboardPresented
                )
            }

            if isPhotoActionSheetPresented {
                PhotoActionSheetView(
                    isPresented: $isPhotoActionSheetPresented,
                    hasPhoto: !inputViewModel.memoPhotos.isEmpty,
                    onTakePhoto: { showsCamera = true },
                    onSelectLibrary: { showsLibrary = true },
                    onDeletePhoto: { inputViewModel.memoPhotos = [] }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.25), value: inputViewModel.isCalculatorKeyboardPresented)
        .animation(.easeInOut(duration: 0.18), value: isPhotoActionSheetPresented)
        .background(AppColors.background.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            editViewModel.applyItem(to: inputViewModel)
            if let bookId = effectiveBookId ?? BookResolver.mainBookId() {
                categoryViewModel.createDefaultCategoriesIfNeeded(
                    existingCategories: categoryDataList,
                    bookId: bookId
                )
            }
            inputViewModel.fixSelectedCategoryIfNeeded(
                for: inputViewModel.expenseSetting.typeName,
                newCategories: expenseCategoryNames
            )
            inputViewModel.fixSelectedCategoryIfNeeded(
                for: inputViewModel.incomeSetting.typeName,
                newCategories: incomeCategoryNames
            )
            // 編集中の取引が既にロック済みの口座/方法を使っていた場合でも、
            // 履歴データは変更しないという方針上、現在値がロックされているだけでは補正しない
            // （一覧から完全に消えた場合のみ先頭に補正する）
            inputViewModel.fixSelectedExpenseMethodIfNeeded(availableMethods: expenseMethods.map(\.name))
            inputViewModel.fixSelectedIncomeMethodIfNeeded(availableMethods: incomeMethods.map(\.name))
        }
        // 修正2：CloudKitから写真を受信した直後、この画面を閉じて開き直さなくても
        // 表示へ反映されるようにする（ReceiptPhotoSyncService.materializeIncoming /
        // materializeAllMissingLocalFilesIfNeeded が新規ファイルを書き出した時だけ発行される）。
        .onReceive(NotificationCenter.default.publisher(for: ReceiptPhotoSyncService.photoMaterializedNotification)) { note in
            guard let filename = note.userInfo?["filename"] as? String,
                  editViewModel.item.receiptImagePaths.contains(filename)
            else { return }
            editViewModel.reloadPhotos(into: inputViewModel)
        }
        .alert(
            "保存に失敗しました",
            isPresented: Binding(
                get: { editViewModel.lastSaveErrorMessage != nil },
                set: { if !$0 { editViewModel.clearSaveError() } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(editViewModel.lastSaveErrorMessage ?? "")
        }
        .onChange(of: expenseCategoryNames) { _, newCategories in
            inputViewModel.fixSelectedCategoryIfNeeded(
                for: inputViewModel.expenseSetting.typeName,
                newCategories: newCategories
            )
        }
        .onChange(of: incomeCategoryNames) { _, newCategories in
            inputViewModel.fixSelectedCategoryIfNeeded(
                for: inputViewModel.incomeSetting.typeName,
                newCategories: newCategories
            )
        }
        .onChange(of: expenseMethods) { _, newMethods in
            inputViewModel.fixSelectedExpenseMethodIfNeeded(availableMethods: newMethods.map(\.name))
        }
        .onChange(of: incomeMethods) { _, newMethods in
            inputViewModel.fixSelectedIncomeMethodIfNeeded(availableMethods: newMethods.map(\.name))
        }
        .alert(deleteAlertTitle, isPresented: $isDeleteAlertPresented) {
            Button("削除", role: .destructive) {
                deleteSelectedTransaction()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このデータを削除しますか？")
        }
        .fullScreenCover(isPresented: $inputViewModel.isCategoryEditPresented) {
            CategoryEditView(selectedType: inputViewModel.selectedType)
        }
        .sheet(isPresented: $showsCamera) {
            ImagePickerView(sourceType: .camera) { image in
                inputViewModel.addPhoto(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsLibrary) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                inputViewModel.addPhoto(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPaymentSettingPresented) {
            PaymentMethodSettingView()
        }
        .sheet(isPresented: $isReceiveSettingPresented) {
            ReceiveMethodSettingView()
        }
        .onChange(of: isPaymentSettingPresented) { _, isPresented in
            guard !isPresented else { return }
            if let newName = newlyAddedMethodName() {
                inputViewModel.selectedExpenseMethod = newName
            }
        }
        .onChange(of: isReceiveSettingPresented) { _, isPresented in
            guard !isPresented else { return }
            if let newName = newlyAddedMethodName() {
                inputViewModel.selectedIncomeMethod = newName
            }
        }
    }

    // MARK: - フォームコンテンツ

    private var formContent: some View {
        ZStack(alignment: .top) {
            AppColors.background
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    inputViewModel.isCalculatorKeyboardPresented = false
                }

            GeometryReader { geometry in
                let width = geometry.size.width

                HStack(spacing: 0) {
                    inputFormPage(for: inputViewModel.expenseSetting)
                        .frame(width: width)
                    inputFormPage(for: inputViewModel.incomeSetting)
                        .frame(width: width)
                }
                .offset(x: baseOffset(width: width) + dragOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(pageSwipeGesture(width: width))
                .clipped()
            }
        }
    }

    // MARK: - フォームページ（共通コンポーネント使用）

    private func inputFormPage(for setting: TransactionInputSetting) -> some View {
        TransactionFormPageView(
            setting: setting,
            viewModel: inputViewModel,
            expenseCategoryNames: expenseCategoryNames,
            incomeCategoryNames: incomeCategoryNames,
            focusedField: $focusedField,
            isCalculatorKeyboardPresented: $inputViewModel.isCalculatorKeyboardPresented,
            isDraggingPage: isDraggingPage,
            layout: layout,
            overrideExpenseMethods: expenseMethods,
            overrideIncomeMethods: incomeMethods,
            onTapUnsetMethod: {
                methodIdsBeforeAdd = Set(paymentMethodSettings.map(\.id) + bankAccountSettings.map(\.id))
                if setting.typeName == inputViewModel.expenseSetting.typeName {
                    isPaymentSettingPresented = true
                } else {
                    isReceiveSettingPresented = true
                }
            },
            onCameraButtonTap: {
                inputViewModel.isCalculatorKeyboardPresented = false
                focusedField = nil
                isPhotoActionSheetPresented = true
            },
            onSave: {
                inputViewModel.isCalculatorKeyboardPresented = false
                hideKeyboard()
                saveEditedTransaction()
            }
        ) {
            EmptyView()
        }
    }

    // MARK: - ヘッダー（AnalysisDetailScreenContainer と同じ実装）

    private var headerArea: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { onClose() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            TransactionTypeSwitchView(
                selectedType: $inputViewModel.selectedType,
                expenseSetting: inputViewModel.expenseSetting,
                incomeSetting: inputViewModel.incomeSetting,
                onChange: { setting in
                    inputViewModel.isCalculatorKeyboardPresented = false
                    hideKeyboard()
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragOffset = 0
                        inputViewModel.changeInputType(
                            to: setting,
                            categories: categoryNames(for: setting.typeName)
                        )
                    }
                },
                width: AppLayout.transactionTypeSwitchWidth
            )

            Spacer()

            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - ページングスワイプジェスチャー

    private func pageSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical else { return }

                isDraggingPage = true

                if selectedPageIndex == 0 && value.translation.width > 0 {
                    dragOffset = value.translation.width * 0.25
                } else if selectedPageIndex == 1 && value.translation.width < 0 {
                    dragOffset = value.translation.width * 0.25
                } else {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                let translation = value.translation.width

                isDraggingPage = false

                guard horizontal > vertical else {
                    withAnimation(.interactiveSpring()) { dragOffset = 0 }
                    return
                }

                if selectedPageIndex == 0 && translation < -swipeCommitThreshold {
                    inputViewModel.isCalculatorKeyboardPresented = false
                    focusedField = nil
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragOffset = 0
                        inputViewModel.changeInputType(
                            to: inputViewModel.incomeSetting,
                            categories: incomeCategoryNames
                        )
                    }
                } else if selectedPageIndex == 1 && translation > swipeCommitThreshold {
                    inputViewModel.isCalculatorKeyboardPresented = false
                    focusedField = nil
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragOffset = 0
                        inputViewModel.changeInputType(
                            to: inputViewModel.expenseSetting,
                            categories: expenseCategoryNames
                        )
                    }
                } else {
                    withAnimation(.interactiveSpring()) { dragOffset = 0 }
                }
            }
    }

    // MARK: - 削除ボタン

    private var deleteButton: some View {
        Button {
            inputViewModel.isCalculatorKeyboardPresented = false
            hideKeyboard()
            isDeleteAlertPresented = true
        } label: {
            Text(deleteButtonTitle)
                .font(AppFonts.button)
                .foregroundStyle(deleteButtonTextColor)
                .frame(maxWidth: .infinity)
                .frame(height: deleteButtonHeight)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(deleteButtonTextColor.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, layout.saveButtonHorizontalPadding)
        .padding(.top, deleteButtonTopPadding)
        .padding(.bottom, deleteButtonBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private var deleteButtonTitle: String {
        inputViewModel.selectedType == inputViewModel.expenseSetting.typeName
            ? "この支出を削除"
            : "この収入を削除"
    }

    private var deleteAlertTitle: String {
        editViewModel.deleteAlertTitle(
            selectedType: inputViewModel.selectedType,
            expenseTypeName: inputViewModel.expenseSetting.typeName
        )
    }

    // MARK: - 保存 / 削除

    private func saveEditedTransaction() {
        // 以前はここで最後に`?? UUID()`していたため、帳簿が解決できない場合でも
        // 「保存自体は成功するが、どの帳簿からも見えない意味の無いbookIdが付く」という
        // 不具合があった。nilのまま渡し、editViewModel側で明確な失敗として扱う。
        var fallbackBookId = BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
            ?? BookResolver.mainBookId()
        if fallbackBookId == nil {
            BookMigrationService.migrateIfNeeded()
            fallbackBookId = BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
                ?? BookResolver.mainBookId()
        }
        let succeeded = editViewModel.updateTransaction(
            inputViewModel: inputViewModel,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList,
            bankAccountId: resolvedBankAccountId(),
            fallbackBookId: fallbackBookId
        )
        if succeeded { onClose() }
    }

    private func deleteSelectedTransaction() {
        let succeeded = editViewModel.deleteTransaction(
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList
        )
        if succeeded { onClose() }
    }

    // MARK: - カテゴリー取得補助

    private func categoryNames(for type: String) -> [String] {
        type == inputViewModel.expenseSetting.typeName
            ? expenseCategoryNames
            : incomeCategoryNames
    }

    // 支出: PaymentMethodSettingData + BankAccountData（showAsPaymentMethod が ON のみ）を sortOrder 順に統合
    private var expenseMethods: [MethodOption] {
        MethodOptionBuilder.expenseOptions(paymentMethods: paymentMethodSettings, bankAccounts: bankAccountSettings)
    }

    // 収入: PaymentMethodSettingData(useForReceive=true) + BankAccountData(showAsReceiveMethod) を sortOrder 順に統合
    private var incomeMethods: [MethodOption] {
        MethodOptionBuilder.incomeOptions(paymentMethods: paymentMethodSettings, bankAccounts: bankAccountSettings)
    }

    // MARK: - 新しく追加された支払い方法/銀行口座の検出

    private func newlyAddedMethodName() -> String? {
        let currentIds = Set(paymentMethodSettings.map(\.id) + bankAccountSettings.map(\.id))
        let newIds = currentIds.subtracting(methodIdsBeforeAdd)
        guard newIds.count == 1, let newId = newIds.first else { return nil }
        if let bank = bankAccountSettings.first(where: { $0.id == newId }) { return bank.accountName }
        if let method = paymentMethodSettings.first(where: { $0.id == newId }) { return method.methodName }
        return nil
    }

    // MARK: - 銀行口座ID解決

    private func resolvedBankAccountId() -> UUID? {
        let isExpense = inputViewModel.selectedType == inputViewModel.expenseSetting.typeName
        let methodName = isExpense
            ? inputViewModel.selectedExpenseMethod
            : inputViewModel.selectedIncomeMethod
        return bankAccountSettings.first(where: { $0.accountName == methodName && $0.isActive })?.id
    }

    // MARK: - キーボードを閉じる

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
