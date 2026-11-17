import SwiftUI

// MARK: - レシート撮影〜保存フローのルート（fullScreenCoverとしてInputViewから開く）
//
// CategoryEditViewと同じ流儀で、必要なCore Dataクエリを自前で持つ自己完結ビュー。

struct ReceiptScanFlowView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataList: [CategoryData] { categoryDataObserver.items }
    @StateObject private var paymentMethodDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodDataList: [PaymentMethodSettingData] { paymentMethodDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountDataList: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    @StateObject private var viewModel = ReceiptScanViewModel()

    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var saveErrorMessage: String?
    @State private var showsSaveSuccessAlert = false
    @State private var savedItemCount = 0

    private let expenseTypeName = ExpenseInputSetting().typeName

    private var currentBook: BookData? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)
    }

    private var bookScopedCategories: [CategoryData] {
        categoryDataList.filter { $0.bookId == currentBook?.id }
    }

    private var expenseCategoryNames: [String] {
        SwiftDataCategoryRepository().categoryNames(type: expenseTypeName, categories: bookScopedCategories)
    }

    private var bookScopedPaymentMethods: [PaymentMethodSettingData] {
        paymentMethodDataList.filter { $0.bookId == currentBook?.id }
    }

    private var bookScopedBankAccounts: [BankAccountData] {
        bankAccountDataList.filter { $0.bookId == currentBook?.id }
    }

    private var expenseMethodNames: [String] {
        MethodOptionBuilder.expenseOptions(
            paymentMethods: bookScopedPaymentMethods,
            bankAccounts: bookScopedBankAccounts
        )
        .filter { !$0.isLocked }
        .map(\.name)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
        }
        .sheet(isPresented: $showsCamera) {
            DocumentCameraView(
                onScanned: { image in
                    showsCamera = false
                    viewModel.imageCaptured(image)
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsLibrary) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                showsLibrary = false
                viewModel.imageCaptured(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isEditingHeader) {
            if let draft = viewModel.draft {
                ReceiptHeaderEditSheet(
                    date: draft.date,
                    storeName: draft.storeName,
                    paymentMethod: draft.paymentMethod,
                    availableMethodNames: expenseMethodNames,
                    onSave: { date, storeName, method in
                        viewModel.draft?.date = date
                        viewModel.draft?.storeName = storeName.isEmpty ? nil : storeName
                        viewModel.draft?.paymentMethod = method
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.editingItemId != nil },
            set: { isPresented in if !isPresented { viewModel.editingItemId = nil } }
        )) {
            if let itemId = viewModel.editingItemId,
               let item = viewModel.draft?.items.first(where: { $0.id == itemId }) {
                ReceiptItemEditSheet(
                    item: item,
                    availableCategories: expenseCategoryNames,
                    onSave: { name, amount, category in
                        guard let index = viewModel.draft?.items.firstIndex(where: { $0.id == itemId }) else { return }
                        viewModel.draft?.items[index].productName = name
                        viewModel.draft?.items[index].amount = amount
                        viewModel.draft?.items[index].category = category
                    }
                )
            }
        }
        .alert("保存しました", isPresented: $showsSaveSuccessAlert) {
            Button("閉じる") { dismiss() }
        } message: {
            Text("\(savedItemCount)件の支出を保存しました。")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .capture:
            ReceiptCaptureChoiceView(
                onTakePhoto: { showsCamera = true },
                onSelectLibrary: { showsLibrary = true }
            )
        case .preview(let image):
            ReceiptCapturePreviewView(
                image: image,
                onRetake: { viewModel.retake() },
                onRecognize: {
                    viewModel.startRecognition(image: image, expenseCategoryNames: expenseCategoryNames)
                }
            )
        case .ocrProcessing:
            ReceiptOCRProgressView()
        case .review:
            if let draftBinding = Binding($viewModel.draft) {
                ReceiptReviewView(
                    draft: draftBinding,
                    onEditHeader: { viewModel.isEditingHeader = true },
                    onEditItem: { viewModel.editingItemId = $0 },
                    onRetake: { viewModel.retake() },
                    onSave: { save() },
                    saveErrorMessage: saveErrorMessage
                )
            }
        case .alreadySaved:
            ReceiptAlreadySavedView(onClose: { dismiss() })
        }
    }

    private func save() {
        guard let bookId = currentBook?.id ?? BookResolver.mainBookId() else { return }
        do {
            let count = try viewModel.save(
                expenseTypeName: expenseTypeName,
                bookId: bookId,
                bankAccounts: bookScopedBankAccounts
            )
            saveErrorMessage = nil
            savedItemCount = count
            showsSaveSuccessAlert = true
        } catch {
            saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? "保存に失敗しました。"
        }
    }
}
