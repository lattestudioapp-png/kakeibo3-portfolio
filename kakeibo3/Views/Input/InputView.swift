import SwiftUI
import Combine

// MARK: - 入力画面

struct InputView: View {

    // MARK: - SwiftData

    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountSettingsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var receiveMethodDataObserver = ReceiveMethodDataSync.observer()
    private var receiveMethodSettingsRaw: [ReceiveMethodData] { receiveMethodDataObserver.items }
    @StateObject private var transferDataObserver = TransferDataSync.observer()
    private var allTransfers: [TransferData] { transferDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    // MARK: - 複数帳簿

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBook: BookData? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)
    }

    // カテゴリー・支払い方法・受け取り方法・銀行口座は帳簿ごとに完全分離するため、
    // 現在選択中の帳簿のものだけに絞り込む。
    private var categoryDataList: [CategoryData] {
        categoryDataListRaw.filter { $0.bookId == currentBook?.id }
    }
    private var paymentMethodSettings: [PaymentMethodSettingData] {
        paymentMethodSettingsRaw.filter { $0.bookId == currentBook?.id }
    }
    private var bankAccountSettings: [BankAccountData] {
        bankAccountSettingsRaw.filter { $0.bookId == currentBook?.id }
    }
    private var receiveMethodSettings: [ReceiveMethodData] {
        receiveMethodSettingsRaw.filter { $0.bookId == currentBook?.id }
    }

    // 新規帳簿を含め、選択中の帳簿にまだ何も無ければその帳簿ぶんの初期データを作成する
    // （メイン帳簿の初回起動時と同じ挙動を、帳簿を切り替えるたびに行う）。
    // レガシー移行（現金type補正・ReceiveMethodData統合）は帳簿共通・一度きりのまま。
    private func seedDefaultDataForCurrentBookIfNeeded() {
        if let bookId = currentBook?.id ?? BookResolver.mainBookId() {
            DataInitializerService.createDefaultPaymentMethodsIfNeeded(
                existing: paymentMethodSettings,
                bookId: bookId
            )
            DataInitializerService.createDefaultReceiveMethodsIfNeeded(
                existing: receiveMethodSettings,
                bookId: bookId
            )
            categoryViewModel.createDefaultCategoriesIfNeeded(
                existingCategories: categoryDataList,
                bookId: bookId
            )
            // migrateReceiveMethodsIfNeeded はアプリ全体で一度きりのフラグでガードされているため、
            // 初回移行が済んだ後に新規作成された帳簿には効かず、上の2つがどちらも「現金」を
            // 作ることで支払い・受け取り・振替候補に現金が重複表示されてしまう。
            // フラグに関係なくこの帳簿ぶんだけ即座に再整合させる。
            DataInitializerService.reconcileReceiveMethodsForBook(bookId: bookId)
        }
        DataInitializerService.migrateCashTypeIfNeeded(
            paymentMethods: paymentMethodSettingsRaw
        )
        DataInitializerService.migrateReceiveMethodsIfNeeded(
            receiveMethodSettings: receiveMethodSettingsRaw,
            paymentMethodSettings: paymentMethodSettingsRaw
        )
    }

    // MARK: - EnvironmentObject

    @EnvironmentObject private var photoDialog: PhotoDialogCoordinator

    // MARK: - Binding

    @Binding var selectedTab: AppTab
    @Binding var initialDate: Date
    @Binding var initialType: String
    @Binding var isCalculatorKeyboardPresented: Bool
    let resetTrigger: Int

    // MARK: - ViewModel

    @StateObject private var viewModel = InputViewModel()
    @StateObject private var categoryViewModel = CategoryEditViewModel()

    // MARK: - フォーカス管理

    @FocusState private var focusedField: InputFocusedField?

    // MARK: - Layout

    private let layout = InputFormLayout()

    // MARK: - ページングスワイプ状態

    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingPage = false
    private let swipeCommitThreshold: CGFloat = 80

    // 写真サムネイル一覧（横スクロール）の画面上の矩形。この中で始まったドラッグは
    // ページ切り替えとして扱わない（写真が無いページでは空配列のまま）。
    @State private var photoAreaFrames: [CGRect] = []

    // MARK: - 設定画面シート

    @State private var isPaymentSettingPresented: Bool = false
    @State private var isReceiveSettingPresented: Bool = false
    // 「＋新しく追加」を押した時点の支払い方法/銀行口座IDを控えておき、
    // 一覧画面から戻ってきた時に増えた1件を検出して自動選択するために使う
    @State private var methodIdsBeforeAdd: Set<UUID> = []

    // MARK: - 振替入力状態

    @State private var transferDate: Date = Date()
    @State private var isTransferDatePickerPresented = false
    @State private var transferFromId: UUID? = nil
    @State private var transferToId: UUID? = nil
    @State private var transferAmountText: String = ""
    @State private var transferMemo: String = ""
    @State private var transferMemoPhotos: [MemoPhoto] = []
    @State private var isAddingTransferPhoto = false
    @State private var editingTransfer: TransferData? = nil

    // MARK: - 写真選択シート

    @State private var showsCamera = false
    @State private var showsLibrary = false

    // MARK: - レシート撮影

    @State private var isReceiptScanPresented = false

    // MARK: - カテゴリー一覧

    private var expenseCategoryNames: [String] {
        categoryViewModel.categoryNames(
            type: viewModel.expenseSetting.typeName,
            categories: categoryDataList
        )
    }

    private var incomeCategoryNames: [String] {
        categoryViewModel.categoryNames(
            type: viewModel.incomeSetting.typeName,
            categories: categoryDataList
        )
    }

    // PaymentMethodSettingData（通常・クレカ）と BankAccountData を統合して sortOrder 順。
    // 銀行口座は showAsPaymentMethod が ON のものだけ含める。ロック中は isLocked=true で含める（灰色表示用）。
    private var expenseMethods: [MethodOption] {
        MethodOptionBuilder.expenseOptions(paymentMethods: paymentMethodSettings, bankAccounts: bankAccountSettings)
    }

    // PaymentMethodSettingData(useForReceive=true) と BankAccountData を統合して sortOrder 順に表示。
    // 銀行口座は showAsReceiveMethod が ON のものだけ含める。ロック中は isLocked=true で含める（灰色表示用）。
    private var incomeMethods: [MethodOption] {
        MethodOptionBuilder.incomeOptions(paymentMethods: paymentMethodSettings, bankAccounts: bankAccountSettings)
    }

    // 新規入力時のデフォルト/補正には、ロックされていない候補の名前だけを使う
    private var unlockedExpenseMethodNames: [String] {
        expenseMethods.filter { !$0.isLocked }.map(\.name)
    }
    private var unlockedIncomeMethodNames: [String] {
        incomeMethods.filter { !$0.isLocked }.map(\.name)
    }

    // MARK: - ページ状態（0: 支出 / 1: 収入 / 2: 振替）

    private var selectedPageIndex: Int {
        if viewModel.selectedType == viewModel.expenseSetting.typeName { return 0 }
        if viewModel.selectedType == viewModel.incomeSetting.typeName { return 1 }
        return 2
    }

    private func baseOffset(width: CGFloat) -> CGFloat {
        -width * CGFloat(selectedPageIndex)
    }

    // MARK: - 振替

    private static let transferTypeName = TransactionTypeSwitchView.transferTypeName

    private var isShowingTransfer: Bool {
        viewModel.selectedType == Self.transferTypeName
    }

    // 銀行口座 + 支払い方法（クレカ除く）+ 受け取り方法。振替は帳簿をまたがないため、
    // 選択中の帳簿に属するものだけを候補にする（bankAccountSettings等は既に帳簿で絞り込み済み）。
    private var transferParticipants: [TransferParticipant] {
        TransferParticipantBuilder.build(
            bankAccounts: bankAccountSettings,
            paymentMethods: paymentMethodSettings,
            receiveMethods: receiveMethodSettings
        )
    }

    private var recentTransfers: [TransferData] {
        Array(allTransfers.filter { $0.bookId == currentBook?.id }.prefix(5))
    }

    private func transferParticipant(for id: UUID?) -> TransferParticipant? {
        guard let id else { return nil }
        return transferParticipants.first(where: { $0.id == id })
    }

    private var parsedTransferAmount: Int {
        Int(transferAmountText.filter { $0.isNumber }) ?? 0
    }

    private func switchToTransfer() {
        isCalculatorKeyboardPresented = false
        hideKeyboard()
        focusedField = nil
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = 0
            viewModel.selectedType = Self.transferTypeName
        }
    }

    private func addTransferPhoto(_ image: UIImage) {
        isAddingTransferPhoto = true
        DispatchQueue.global(qos: .userInitiated).async {
            let photo = MemoPhoto.make(from: image)
            DispatchQueue.main.async {
                if let photo { transferMemoPhotos.append(photo) }
                isAddingTransferPhoto = false
            }
        }
    }

    private func saveTransfer() {
        guard let fId = transferFromId, let tId = transferToId, fId != tId,
              parsedTransferAmount > 0,
              let from = transferParticipant(for: fId),
              let to = transferParticipant(for: tId),
              !from.isLocked, !to.isLocked
        else { return }

        // 選択中の帳簿が解決できない場合、InputView.onSaveと同じ理由で一度だけ再試行する。
        var bookId = currentBook?.id ?? BookResolver.mainBookId()
        if bookId == nil {
            BookMigrationService.migrateIfNeeded()
            bookId = currentBook?.id ?? BookResolver.mainBookId()
        }
        guard let resolvedBookId = bookId else {
            viewModel.reportSaveError(TransactionSaveError.noBookAvailable.errorDescription ?? "保存に失敗しました")
            return
        }

        isCalculatorKeyboardPresented = false
        hideKeyboard()
        focusedField = nil

        let resolvedPaths = transferMemoPhotos.compactMap { ReceiptImageHelper.save($0.imageData) }
        var transfer = TransferData(
            date: transferDate,
            fromType: from.type,
            fromId: fId,
            fromName: from.name,
            toType: to.type,
            toId: tId,
            toName: to.name,
            amount: parsedTransferAmount,
            memo: transferMemo.trimmingCharacters(in: .whitespaces),
            receiptImagePath: ReceiptImageHelper.encodePaths(resolvedPaths)
        )
        transfer.bookId = resolvedBookId
        guard TransferDataSync.insertChecked(transfer) else {
            // 永続化に失敗した場合は入力内容を一切消さない（書き込んだ写真ファイルもロールバックする）。
            ReceiptImageHelper.deleteAll(resolvedPaths)
            viewModel.reportSaveError(TransactionSaveError.persistenceFailed.errorDescription ?? "保存に失敗しました")
            return
        }
        ReceiptPhotoSyncService.ensureSynced(
            filenames: resolvedPaths, transactionType: .transfer,
            transactionId: transfer.id, bookId: resolvedBookId
        )
        SnapshotUpdateService.handle(.transferCreated(date: transferDate, bookId: resolvedBookId))

        transferAmountText = ""
        transferMemo = ""
        transferMemoPhotos = []
    }

    // MARK: - body

    var body: some View {
        ZStack {
        NavigationStack {
            AppScreenContainer {
                inputContent
            } headerOverlay: {
                typeSwitchOverlay
                    .frame(height: AppLayout.headerHeight, alignment: .top)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarHidden(true)
            .onAppear {
                seedDefaultDataForCurrentBookIfNeeded()

                // 設定の先頭をデフォルトとして事前に登録してから applyInitialInputIfNeeded を呼ぶ
                if let first = unlockedExpenseMethodNames.first { viewModel.updateDefaultExpenseMethod(first) }
                if let first = unlockedIncomeMethodNames.first  { viewModel.updateDefaultIncomeMethod(first) }

                // 削除等で選択中の方法が一覧から消えた場合、またはロックされた場合は先頭に補正する
                viewModel.fixSelectedExpenseMethodIfNeeded(availableMethods: unlockedExpenseMethodNames)
                viewModel.fixSelectedIncomeMethodIfNeeded(availableMethods: unlockedIncomeMethodNames)

                viewModel.applyInitialInputIfNeeded(
                    initialDate: initialDate,
                    initialType: initialType,
                    expenseCategories: expenseCategoryNames,
                    incomeCategories: incomeCategoryNames
                )

                viewModel.fixSelectedCategoryIfNeeded(
                    for: viewModel.expenseSetting.typeName,
                    newCategories: expenseCategoryNames
                )
                viewModel.fixSelectedCategoryIfNeeded(
                    for: viewModel.incomeSetting.typeName,
                    newCategories: incomeCategoryNames
                )
            }
            .onChange(of: initialDate) { _, newValue in
                viewModel.applyInitialInputIfNeeded(
                    initialDate: newValue,
                    initialType: initialType,
                    expenseCategories: expenseCategoryNames,
                    incomeCategories: incomeCategoryNames
                )
            }
            .onChange(of: initialType) { _, newValue in
                viewModel.applyInitialInputIfNeeded(
                    initialDate: initialDate,
                    initialType: newValue,
                    expenseCategories: expenseCategoryNames,
                    incomeCategories: incomeCategoryNames
                )
            }
            .onChange(of: expenseCategoryNames) { _, newCategories in
                viewModel.fixSelectedCategoryIfNeeded(
                    for: viewModel.expenseSetting.typeName,
                    newCategories: newCategories
                )
            }
            .onChange(of: incomeCategoryNames) { _, newCategories in
                viewModel.fixSelectedCategoryIfNeeded(
                    for: viewModel.incomeSetting.typeName,
                    newCategories: newCategories
                )
            }
            // 支払い/受け取り方法が変化したとき: デフォルト更新 + 選択値が無効/ロックされた場合は補正
            .onChange(of: expenseMethods) { _, newMethods in
                let unlockedNames = newMethods.filter { !$0.isLocked }.map(\.name)
                if let first = unlockedNames.first { viewModel.updateDefaultExpenseMethod(first) }
                viewModel.fixSelectedExpenseMethodIfNeeded(availableMethods: unlockedNames)
            }
            .onChange(of: incomeMethods) { _, newMethods in
                let unlockedNames = newMethods.filter { !$0.isLocked }.map(\.name)
                if let first = unlockedNames.first { viewModel.updateDefaultIncomeMethod(first) }
                viewModel.fixSelectedIncomeMethodIfNeeded(availableMethods: unlockedNames)
            }
            .sheet(isPresented: $isPaymentSettingPresented) {
                PaymentMethodSettingView()
            }
            .sheet(isPresented: $isReceiveSettingPresented) {
                ReceiveMethodSettingView()
            }
            // 支払い一覧/受け取り一覧から「＋新しく追加」経由で戻ってきた時、
            // 新しく増えた1件だけを検出してそのまま選択状態にする
            .onChange(of: isPaymentSettingPresented) { _, isPresented in
                guard !isPresented else { return }
                if let newName = newlyAddedMethodName() {
                    viewModel.selectedExpenseMethod = newName
                }
            }
            .onChange(of: isReceiveSettingPresented) { _, isPresented in
                guard !isPresented else { return }
                if let newName = newlyAddedMethodName() {
                    viewModel.selectedIncomeMethod = newName
                }
            }
            .sheet(item: $editingTransfer) { TransferEditView(existing: $0) }
            .fullScreenCover(isPresented: $viewModel.isCategoryEditPresented) {
                CategoryEditView(selectedType: viewModel.selectedType)
            }
            .fullScreenCover(isPresented: $isReceiptScanPresented) {
                ReceiptScanFlowView()
            }
            .sheet(isPresented: $showsCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    if isShowingTransfer {
                        addTransferPhoto(image)
                    } else {
                        viewModel.addPhoto(image)
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsLibrary) {
                ImagePickerView(sourceType: .photoLibrary) { image in
                    if isShowingTransfer {
                        addTransferPhoto(image)
                    } else {
                        viewModel.addPhoto(image)
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: resetTrigger) { _, _ in
                resetToInitialState()
            }
            .onChange(of: selectedBookIdString) { _, _ in
                seedDefaultDataForCurrentBookIfNeeded()
            }
            .alert(
                "保存に失敗しました",
                isPresented: Binding(
                    get: { viewModel.lastSaveErrorMessage != nil },
                    set: { if !$0 { viewModel.clearSaveError() } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(viewModel.lastSaveErrorMessage ?? "")
            }
        }

        if isCalculatorKeyboardPresented {
            CalculatorKeyboardView(
                amountText: calculatorAmountBinding,
                isPresented: $isCalculatorKeyboardPresented
            )
            .padding(.bottom, layout.calculatorKeyboardBottomPadding)
            .background(alignment: .bottom) {
                Color(UIColor.systemGray6)
                    .frame(height: layout.calculatorKeyboardBottomPadding)
                    .ignoresSafeArea(edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
            .zIndex(100)
        }
        }
        .animation(.easeOut(duration: 0.25), value: isCalculatorKeyboardPresented)
    }

    // MARK: - 入力画面本体

    private var inputContent: some View {
        ZStack(alignment: .top) {
            layout.backgroundColor
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    isCalculatorKeyboardPresented = false
                }

            GeometryReader { geometry in
                let width = geometry.size.width

                HStack(spacing: 0) {
                    inputFormPage(for: viewModel.expenseSetting)
                        .frame(width: width)
                    inputFormPage(for: viewModel.incomeSetting)
                        .frame(width: width)
                    transferFormPage
                        .frame(width: width)
                }
                .offset(x: baseOffset(width: width) + dragOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(pageSwipeGesture(width: width))
                .clipped()
                .onPreferenceChange(PhotoAreaFramePreferenceKey.self) { photoAreaFrames = $0 }
            }
        }
    }

    // MARK: - 計算機キーボードが編集する金額（支出/収入 or 振替）

    private var calculatorAmountBinding: Binding<String> {
        isShowingTransfer ? $transferAmountText : $viewModel.amountText
    }

    // MARK: - フォームページ（振替）

    private var transferFormPage: some View {
        TransferInputPageView(
            date: $transferDate,
            isDatePickerPresented: $isTransferDatePickerPresented,
            fromId: $transferFromId,
            toId: $transferToId,
            amountText: $transferAmountText,
            memo: $transferMemo,
            memoPhotos: $transferMemoPhotos,
            isAddingPhoto: isAddingTransferPhoto,
            participants: transferParticipants,
            recentTransfers: recentTransfers,
            focusedField: $focusedField,
            isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
            layout: layout,
            onCameraButtonTap: {
                isCalculatorKeyboardPresented = false
                focusedField = nil
                photoDialog.show(
                    hasPhoto: !transferMemoPhotos.isEmpty,
                    onTakePhoto: { showsCamera = true },
                    onSelectLibrary: { showsLibrary = true },
                    onDeletePhoto: {
                        transferMemoPhotos = []
                    }
                )
            },
            onSelectHistoryTransfer: { transfer in
                editingTransfer = transfer
            },
            onSave: {
                saveTransfer()
            }
        )
    }

    // MARK: - フォームページ（支出 / 収入で共用）

    private func inputFormPage(for setting: TransactionInputSetting) -> some View {
        return TransactionFormPageView(
            setting: setting,
            viewModel: viewModel,
            expenseCategoryNames: expenseCategoryNames,
            incomeCategoryNames: incomeCategoryNames,
            focusedField: $focusedField,
            isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
            isDraggingPage: isDraggingPage,
            layout: layout,
            overrideExpenseMethods: expenseMethods,
            overrideIncomeMethods: incomeMethods,
            onTapUnsetMethod: {
                methodIdsBeforeAdd = Set(paymentMethodSettings.map(\.id) + bankAccountSettings.map(\.id))
                if setting.typeName == viewModel.expenseSetting.typeName {
                    isPaymentSettingPresented = true
                } else {
                    isReceiveSettingPresented = true
                }
            },
            onCameraButtonTap: {
                isCalculatorKeyboardPresented = false
                focusedField = nil
                photoDialog.show(
                    hasPhoto: !viewModel.memoPhotos.isEmpty,
                    onTakePhoto: { showsCamera = true },
                    onSelectLibrary: { showsLibrary = true },
                    onDeletePhoto: {
                        viewModel.memoPhotos = []
                    }
                )
            },
            onSave: {
                isCalculatorKeyboardPresented = false
                hideKeyboard()
                // 選択中の帳簿が解決できない場合（帳簿が1件も無い・CloudKit初回同期待ち等）、
                // ここで一度だけBookMigrationService.migrateIfNeeded()を再試行する
                // （アプリ起動時に一度だけ呼ばれて.waitAndRetryだった場合、ユーザーが入力に
                // かけた時間ぶんCloudKit同期が進んでいる可能性があるため、無駄にならない）。
                // それでも解決できない場合はnilのままsaveNewTransactionへ渡し、
                // 「保存できていない」ことを明確にユーザーへ伝える（無言で何もしないのを防ぐ）。
                var bookId = currentBook?.id ?? BookResolver.mainBookId()
                if bookId == nil {
                    BookMigrationService.migrateIfNeeded()
                    bookId = currentBook?.id ?? BookResolver.mainBookId()
                }
                viewModel.saveNewTransaction(
                    expenseCategories: expenseCategoryNames,
                    bankAccountId: resolvedBankAccountId(),
                    bookId: bookId
                )
            }
        ) {
            Color.clear
                .frame(height: layout.bottomNavigationSpacerHeight)
        }
    }

    // MARK: - ページングスワイプジェスチャー

    // 写真サムネイル一覧上で始まったドラッグかどうかを判定する
    // （.globalで開始位置を見るため、画面サイズやページ位置に関わらず正しく判定できる）
    private func isDragStartingInPhotoArea(_ startLocation: CGPoint) -> Bool {
        photoAreaFrames.contains { $0.contains(startLocation) }
    }

    private func pageSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                guard !isDragStartingInPhotoArea(value.startLocation) else { return }

                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical else { return }

                isDraggingPage = true

                if selectedPageIndex == 0 && value.translation.width > 0 {
                    dragOffset = value.translation.width * 0.25
                } else if selectedPageIndex == 2 && value.translation.width < 0 {
                    dragOffset = value.translation.width * 0.25
                } else {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                guard !isDragStartingInPhotoArea(value.startLocation) else { return }

                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                let translation = value.translation.width

                isDraggingPage = false

                guard horizontal > vertical else {
                    withAnimation(.interactiveSpring()) { dragOffset = 0 }
                    return
                }

                if translation < -swipeCommitThreshold && selectedPageIndex < 2 {
                    movePage(to: selectedPageIndex + 1)
                } else if translation > swipeCommitThreshold && selectedPageIndex > 0 {
                    movePage(to: selectedPageIndex - 1)
                } else {
                    withAnimation(.interactiveSpring()) { dragOffset = 0 }
                }
            }
    }

    private func movePage(to index: Int) {
        isCalculatorKeyboardPresented = false
        focusedField = nil
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = 0
            switch index {
            case 0:
                viewModel.changeInputType(to: viewModel.expenseSetting, categories: expenseCategoryNames)
            case 1:
                viewModel.changeInputType(to: viewModel.incomeSetting, categories: incomeCategoryNames)
            default:
                viewModel.selectedType = Self.transferTypeName
            }
        }
    }

    // MARK: - ヘッダー：支出 / 収入切り替えバー

    private var typeSwitchOverlay: some View {
        TransactionTypeSwitchView(
            selectedType: $viewModel.selectedType,
            expenseSetting: viewModel.expenseSetting,
            incomeSetting: viewModel.incomeSetting,
            onChange: { setting in
                isCalculatorKeyboardPresented = false
                hideKeyboard()
                withAnimation(.easeOut(duration: 0.22)) {
                    dragOffset = 0
                    viewModel.changeInputType(
                        to: setting,
                        categories: categoryNames(for: setting.typeName)
                    )
                }
            },
            showsTransfer: true,
            onTransferSelect: { switchToTransfer() },
            showsReceipt: FeatureFlags.isReceiptFeatureEnabled,
            onReceiptSelect: { isReceiptScanPresented = true },
            width: FeatureFlags.isReceiptFeatureEnabled
                ? AppLayout.transactionTypeSwitchWidthWithReceipt
                : AppLayout.transactionTypeSwitchWidth + 40
        )
        .padding(.top, SegmentBarLayout.standard.topPadding)
    }

    // MARK: - タブ再タップ時の初期表示リセット

    private func resetToInitialState() {
        isCalculatorKeyboardPresented = false
        focusedField = nil
        dragOffset = 0
        isDraggingPage = false
        isPaymentSettingPresented = false
        isReceiveSettingPresented = false
        showsCamera = false
        showsLibrary = false
        isReceiptScanPresented = false
        viewModel.isCategoryEditPresented = false
        viewModel.selectedType = viewModel.expenseSetting.typeName
        editingTransfer = nil
        transferDate = Date()
        transferFromId = nil
        transferToId = nil
        transferAmountText = ""
        transferMemo = ""
        transferMemoPhotos = []
        viewModel.resetToInitialState()
    }

    // MARK: - キーボードを閉じる処理

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    // MARK: - 新しく追加された支払い方法/銀行口座の検出
    //
    // methodIdsBeforeAdd（「＋新しく追加」を押した時点のID集合）と比較して、
    // 新しく増えたIDが1件だけならその名前を返す。0件・複数件（削除も同時に起きた等）なら nil。

    private func newlyAddedMethodName() -> String? {
        let currentIds = Set(paymentMethodSettings.map(\.id) + bankAccountSettings.map(\.id))
        let newIds = currentIds.subtracting(methodIdsBeforeAdd)
        guard newIds.count == 1, let newId = newIds.first else { return nil }
        if let bank = bankAccountSettings.first(where: { $0.id == newId }) { return bank.accountName }
        if let method = paymentMethodSettings.first(where: { $0.id == newId }) { return method.methodName }
        return nil
    }

    // MARK: - カテゴリー取得補助

    private func categoryNames(for type: String) -> [String] {
        if type == viewModel.expenseSetting.typeName {
            return expenseCategoryNames
        } else {
            return incomeCategoryNames
        }
    }

    // MARK: - 銀行口座ID解決

    private func resolvedBankAccountId() -> UUID? {
        let methodName = viewModel.selectedType == viewModel.expenseSetting.typeName
            ? viewModel.selectedExpenseMethod
            : viewModel.selectedIncomeMethod
        return bankAccountSettings.first(where: { $0.accountName == methodName && $0.isActive })?.id
    }
}
