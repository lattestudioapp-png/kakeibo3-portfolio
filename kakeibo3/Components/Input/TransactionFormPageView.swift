import SwiftUI

// MARK: - フォームページ（InputView / 編集View 共通）

struct TransactionFormPageView<AdditionalBottom: View>: View {

    // MARK: - Props

    let setting: TransactionInputSetting
    @ObservedObject var viewModel: InputViewModel
    let expenseCategoryNames: [String]
    let incomeCategoryNames: [String]
    var focusedField: FocusState<InputFocusedField?>.Binding
    @Binding var isCalculatorKeyboardPresented: Bool
    var isDraggingPage: Bool
    let layout: InputFormLayout
    var overrideExpenseMethods: [MethodOption]? = nil
    var overrideIncomeMethods: [MethodOption]? = nil
    var onTapUnsetMethod: (() -> Void)? = nil
    var onCameraButtonTap: (() -> Void)? = nil
    let onSave: () -> Void
    @ViewBuilder var additionalBottomContent: () -> AdditionalBottom

    // MARK: - 内部

    @State private var isPhotoFullScreenPresented = false
    @State private var fullScreenPhoto: MemoPhoto? = nil

    // 設定 > 入力 > 「カメラマークの表示」
    @AppStorage(MemoCameraIconSettings.storageKey) private var showsCameraIcon: Bool = MemoCameraIconSettings.defaultValue

    // ON: 写真が1枚もない間は写真追加エリアを隠す / OFF: 常に表示する
    private var showsPhotoThumbnailArea: Bool {
        showsCameraIcon ? !viewModel.memoPhotos.isEmpty : true
    }

    private var isExpense: Bool {
        setting.typeName == viewModel.expenseSetting.typeName
    }

    private func closeKeyboard() {
        focusedField.wrappedValue = nil
        isCalculatorKeyboardPresented = false
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            InputDateAreaView(
                date: $viewModel.date,
                isDatePickerPresented: $viewModel.isDatePickerPresented,
                layout: layout
            )
            .simultaneousGesture(TapGesture().onEnded { closeKeyboard() })

            MethodSelectAreaView(
                selectedMethod: isExpense
                    ? $viewModel.selectedExpenseMethod
                    : $viewModel.selectedIncomeMethod,
                methodTitle: setting.methodTitle,
                methods: isExpense
                    ? (overrideExpenseMethods ?? setting.methods.map { MethodOption(id: UUID(), name: $0, isLocked: false, colorHex: nil) })
                    : (overrideIncomeMethods ?? setting.methods.map { MethodOption(id: UUID(), name: $0, isLocked: false, colorHex: nil) }),
                layout: layout,
                onTapUnset: onTapUnsetMethod
            )
            .simultaneousGesture(TapGesture().onEnded { closeKeyboard() })

            MemoInputAreaView(
                memo: $viewModel.memo,
                memoPhotos: $viewModel.memoPhotos,
                focusedField: focusedField,
                isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
                onCameraButtonTap: onCameraButtonTap ?? {},
                showsCameraIcon: showsCameraIcon,
                focusId: setting.typeName,
                layout: layout
            )

            // 写真サムネイル一覧 / 追加ボタン / ローディング表示
            // 設定ONの場合は写真が1枚もない間はエリアごと隠す。OFFの場合は常に表示する。
            if showsPhotoThumbnailArea {
                photoThumbnailArea
            }

            AmountInputAreaView(
                amountText: $viewModel.amountText,
                isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
                focusedField: focusedField,
                layout: layout
            )

            CategorySelectAreaView(
                selectedCategory: isExpense
                    ? $viewModel.selectedExpenseCategory
                    : $viewModel.selectedIncomeCategory,
                isCategoryEditPresented: $viewModel.isCategoryEditPresented,
                expenseCategories: expenseCategoryNames,
                incomeCategories: incomeCategoryNames,
                selectedType: setting.typeName,
                expenseSetting: viewModel.expenseSetting,
                layout: layout,
                onCategoryChanged: { newCategories in
                    viewModel.fixSelectedCategoryIfNeeded(
                        for: setting.typeName,
                        newCategories: newCategories
                    )
                },
                isDraggingPage: isDraggingPage
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { closeKeyboard() })

            Spacer(minLength: 0)

            SaveButtonAreaView(layout: layout, onSave: onSave)

            additionalBottomContent()
        }
    }

    // MARK: - サムネイルエリア

    private var photoThumbnailArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(viewModel.memoPhotos) { photo in
                    thumbnailCell(for: photo)
                }

                // 追加処理中のローディングセル
                if viewModel.isAddingPhoto {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.12))
                            .frame(width: 75, height: 75)
                        ProgressView()
                    }
                } else {
                    addPhotoTile
                }
            }
            .padding(.horizontal, layout.memoHorizontalPadding)
            .padding(.vertical, 10)
        }
        .frame(height: 95)
        .background(Color.white)
        .background {
            // 写真が無い場合は矩形を報告せず、従来通りページ切り替えスワイプを優先させる
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PhotoAreaFramePreferenceKey.self,
                    value: viewModel.memoPhotos.isEmpty ? [] : [geometry.frame(in: .global)]
                )
            }
        }
        .fullScreenCover(item: $fullScreenPhoto) { photo in
            fullScreenView(for: photo)
        }
    }

    // MARK: - 写真追加ボタン（サムネイル一覧の末尾に表示）

    private var addPhotoTile: some View {
        Button {
            onCameraButtonTap?()
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
                .frame(width: 75, height: 75)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.55))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - サムネイルセル

    private func thumbnailCell(for photo: MemoPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 75, height: 75)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    fullScreenPhoto = photo
                    isPhotoFullScreenPresented = true
                }

            Button {
                viewModel.memoPhotos.removeAll { $0.id == photo.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    // MARK: - フルスクリーン表示

    private func fullScreenView(for photo: MemoPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            // imageData から UIImage を生成（1280px 圧縮済み）
            if let fullImage = UIImage(data: photo.imageData) {
                ZoomableImageView(image: fullImage)
            }
            Button {
                fullScreenPhoto = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }
}
