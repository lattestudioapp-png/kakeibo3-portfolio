import SwiftUI
import Combine

// MARK: - カテゴリー編集画面

struct CategoryEditView: View {

    // MARK: - 受け取る値

    init(selectedType: String) {
        self._selectedPageIndex = State(initialValue: Self.pageTypes.firstIndex(of: selectedType) ?? 0)
    }

    // MARK: - SwiftData

    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataList: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var bookScopedCategoryDataList: [CategoryData] {
        categoryDataList.filter { $0.bookId == currentBookId }
    }

    // MARK: - 環境値

    @Environment(\.dismiss) private var dismiss

    // MARK: - ViewModel

    @StateObject private var viewModel = CategoryEditViewModel()

    // MARK: - 表示タイプ（支出 / 収入）ページング
    //
    // 支出/収入を横スワイプで切り替えられるよう、入力Viewと同じ「2ページを横に並べて
    // dragOffsetぶんオフセットする」方式にする（TransactionTypeSwitchView/InputView参照）。

    private static let pageTypes = ["支出", "収入"]

    @State private var selectedPageIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingPage = false
    /// カテゴリー追加アラートで、どちらのページから追加されたか（アラート確定時に使う）
    @State private var addAlertType: String = "支出"

    private let swipeCommitThreshold: CGFloat = 80

    // MARK: - 詳細画面遷移状態

    @State private var selectedCategoryForEdit: CategoryData?

    // MARK: - 削除確認

    /// マイナスボタンが押され、削除確認中のカテゴリー（確認ダイアログの対象）
    @State private var categoryPendingDeletion: CategoryData?

    // MARK: - レイアウト定数

    private enum AddButtonLayout {
        static let headerToRowSpacing: CGFloat = 28
        static let addRowHeight: CGFloat = 50
        static let separatorColor = Color.gray.opacity(0.25)
        static let separatorHeight: CGFloat = 0.5
        static let rowToGuideSpacing: CGFloat = 10
        static let guideAreaHeight: CGFloat = 36
        static let guideHorizontalPadding: CGFloat = 28
        static let listRowHeight: CGFloat = 45
        static let listRowHorizontalPadding: CGFloat = 0
    }

    // MARK: - 色設定

    private var backgroundColor: Color { AppColors.background }
    private let listBackgroundColor = Color.white
    private let borderColor = AppColors.line
    private let guideTextColor = Color.gray
    private let addButtonTextColor = Color.blue
    private let deleteButtonColor = Color(red: 1.00, green: 0.23, blue: 0.28)
    private let deleteButtonMinusColor = Color.white

    // MARK: - 説明エリア設定

    private let guideFontSize: CGFloat = 15
    private let guideFontWeight: Font.Weight = .semibold
    private let guideTextOpacity: Double = 0.90
    private let guideLeftTextXOffset: CGFloat = -8
    private let guideRightTextXOffset: CGFloat = 7

    // MARK: - カテゴリー行設定

    private let categoryTextOpacity: Double = 1.0
    private let categoryTextLeadingPadding: CGFloat = 14
    private let categoryTextXOffset: CGFloat = -20
    private let categoryTextYOffset: CGFloat = 0

    // MARK: - カスタムアイコン設定

    private let chevronIconWidth: CGFloat = 18
    private let chevronIconHeight: CGFloat = 24
    private let chevronTrailingPadding: CGFloat = 8
    private let dragHandleIconWidth: CGFloat = 28
    private let dragHandleIconHeight: CGFloat = 24
    private let dragHandleTrailingPadding: CGFloat = 12

    // MARK: - 自作削除ボタン設定

    private let deleteButtonSize: CGFloat = 20
    private let deleteMinusWidthRatio: CGFloat = 0.48
    private let deleteMinusHeight: CGFloat = 2
    private let deleteButtonLeadingPadding: CGFloat = 12
    private let deleteButtonTrailingSpacing: CGFloat = 16
    private let deleteButtonXOffset: CGFloat = 0
    private let deleteButtonYOffset: CGFloat = 0

    // MARK: - リスト設定

    private let listRowLeadingInset: CGFloat = AddButtonLayout.listRowHorizontalPadding
    private let listRowTrailingInset: CGFloat = AddButtonLayout.listRowHorizontalPadding
    private let rowSeparatorLeadingPadding: CGFloat = -40
    private let rowSeparatorTrailingPadding: CGFloat = -50
    private let rowSeparatorHeight: CGFloat = 1
    private let rowSeparatorOpacity: Double = 0.18
    private let listTopPadding: CGFloat = 0
    private let listBottomPadding: CGFloat = 0

    // MARK: - 追加ボタン補助設定

    private let addButtonTextOpacity: Double = 1.0

    // MARK: - 共通線設定

    private let borderHeight: CGFloat = 1

    // MARK: - 表示カテゴリー

    private func categories(for type: String) -> [CategoryData] {
        viewModel.sortedCategories(
            type: type,
            categories: bookScopedCategoryDataList.filter { !$0.isSuspended }
        )
    }

    // MARK: - 使用停止カテゴリー一覧への遷移

    @State private var suspendedListType: String? = nil

    // MARK: - body

    var body: some View {
        NavigationStack {
            AppScreenContainer {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    HStack(spacing: 0) {
                        ForEach(Self.pageTypes.indices, id: \.self) { index in
                            categoryPage(for: Self.pageTypes[index])
                                .frame(width: width)
                        }
                    }
                    .offset(x: -CGFloat(selectedPageIndex) * width + dragOffset)
                    .contentShape(Rectangle())
                    .simultaneousGesture(pageSwipeGesture(width: width))
                    .clipped()
                }
            } headerOverlay: {
                headerContent
                    .frame(height: AppLayout.headerHeight, alignment: .top)
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedCategoryForEdit) { category in
                CategoryDetailEditView(
                    category: category,
                    allCategories: bookScopedCategoryDataList
                )
            }
            .sheet(isPresented: Binding(
                get: { suspendedListType != nil },
                set: { if !$0 { suspendedListType = nil } }
            )) {
                SuspendedCategoryListView(
                    type: suspendedListType ?? "支出",
                    categories: bookScopedCategoryDataList
                )
            }
            .onAppear {
                if let bookId = currentBookId ?? BookResolver.mainBookId() {
                    viewModel.createDefaultCategoriesIfNeeded(
                        existingCategories: categoryDataList,
                        bookId: bookId
                    )
                }
                // システムの reorder handle を透明にしてカスタム表示だけ見せる
                UITableView.appearance().tintColor = UIColor.black.withAlphaComponent(0.45)
            }
            .onDisappear {
                UITableView.appearance().tintColor = nil
            }
            .alert("カテゴリー追加", isPresented: $viewModel.isAddAlertPresented) {
                TextField("カテゴリー名", text: $viewModel.newCategoryName)

                Button("追加") {
                    // 以前はbookIdが解決できない場合、ここで無言のまま何もしなかった
                    // （InputView.onSave等と同じ理由で、保存ボタンを押しても何も起きないように見えた）。
                    // 他の保存系と同じく一度だけ再試行し、それでも解決できなければ明確にエラーを示す。
                    var bookId = currentBookId ?? BookResolver.mainBookId()
                    if bookId == nil {
                        BookMigrationService.migrateIfNeeded()
                        bookId = currentBookId ?? BookResolver.mainBookId()
                    }
                    if let bookId {
                        viewModel.addCategory(
                            type: addAlertType,
                            existingCategories: categoryDataList,
                            bookId: bookId
                        )
                    } else {
                        viewModel.errorAlertMessage = TransactionSaveError.noBookAvailable.errorDescription
                    }
                }

                Button("キャンセル", role: .cancel) {
                    viewModel.newCategoryName = ""
                }
            } message: {
                Text("追加するカテゴリー名を入力してください")
            }
            .alert(
                categoryPendingDeletion.map { "「\($0.name)」を削除しますか？" } ?? "削除しますか？",
                isPresented: Binding(
                    get: { categoryPendingDeletion != nil },
                    set: { if !$0 { categoryPendingDeletion = nil } }
                )
            ) {
                Button("はい", role: .destructive) {
                    guard let category = categoryPendingDeletion else { return }
                    viewModel.deleteCategory(
                        category: category
                    )
                    categoryPendingDeletion = nil
                }
                Button("いいえ", role: .cancel) {
                    categoryPendingDeletion = nil
                }
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { viewModel.errorAlertMessage != nil },
                    set: { if !$0 { viewModel.errorAlertMessage = nil } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorAlertMessage ?? "")
            }
            .alert(
                "このカテゴリーは非表示中です。再表示しますか？",
                isPresented: Binding(
                    get: { viewModel.suspendedCategoryPendingReactivation != nil },
                    set: { if !$0 { viewModel.suspendedCategoryPendingReactivation = nil } }
                )
            ) {
                Button("再表示する") {
                    if let category = viewModel.suspendedCategoryPendingReactivation {
                        viewModel.reactivateSuspendedCategory(category)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    viewModel.suspendedCategoryPendingReactivation = nil
                }
            }
        }
    }

    // MARK: - ヘッダーコンテンツ（支出/収入切り替えバー）

    private var headerContent: some View {
        HStack {
            HeaderCloseButtonView {
                dismiss()
            }
            .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppSegmentControl(
                items: Self.pageTypes,
                selectedIndex: selectedPageIndex,
                onSelect: { index in
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragOffset = 0
                        selectedPageIndex = index
                    }
                },
                width: AppLayout.transactionTypeSwitchWidth
            )

            Spacer()

            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.top, SegmentBarLayout.standard.topPadding)
    }

    // MARK: - ページコンテンツ（支出 / 収入 共通のレイアウトを type ぶんだけ作る）

    private func categoryPage(for type: String) -> some View {
        VStack(spacing: 0) {
            addButtonArea(for: type)
                .padding(.top, AddButtonLayout.headerToRowSpacing)
            Color.clear.frame(height: AddButtonLayout.rowToGuideSpacing)
            guideArea
            categoryList(for: type)
            suspendedListButton(for: type)
        }
        // categoryListの内容が少ない場合にVStackが縮んでしまい、下に背景色の余白が
        // 見えてしまう問題への対応。VStack自体を利用可能な高さいっぱいまで広げることで、
        // 可変サイズのcategoryList（List）がその余白分だけ伸び、
        // suspendedListButtonが画面下端（SafeArea内）に自然に収まるようにする。
        .frame(maxHeight: .infinity)
    }

    // MARK: - 使用停止カテゴリーへの導線

    private func suspendedListButton(for type: String) -> some View {
        Button {
            suspendedListType = type
        } label: {
            Text("非表示カテゴリー")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: AddButtonLayout.addRowHeight)
                .background(listBackgroundColor)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AddButtonLayout.separatorColor)
                .frame(height: AddButtonLayout.separatorHeight)
        }
    }

    // MARK: - ページングスワイプジェスチャー（入力Viewと同じ方式）

    private func pageSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical else { return }

                isDraggingPage = true

                if selectedPageIndex == 0 && value.translation.width > 0 {
                    dragOffset = value.translation.width * 0.25
                } else if selectedPageIndex == Self.pageTypes.count - 1 && value.translation.width < 0 {
                    dragOffset = value.translation.width * 0.25
                } else {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                let translation = value.translation.width

                // すぐにfalseへ戻すと、指を離した瞬間にカテゴリー行のButtonのタップ判定が
                // 拾われてしまい、横スワイプのつもりがカテゴリー詳細を開いてしまう
                // （List内のButtonとページスワイプのDragGestureが競合するため）。
                // 少し遅延させることで、タップ判定発火時点ではまだisDraggingPage=trueのままにする。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isDraggingPage = false
                }

                guard horizontal > vertical else {
                    withAnimation(.interactiveSpring()) { dragOffset = 0 }
                    return
                }

                if translation < -swipeCommitThreshold && selectedPageIndex < Self.pageTypes.count - 1 {
                    withAnimation(.easeOut(duration: 0.22)) {
                        selectedPageIndex += 1
                        dragOffset = 0
                    }
                } else if translation > swipeCommitThreshold && selectedPageIndex > 0 {
                    withAnimation(.easeOut(duration: 0.22)) {
                        selectedPageIndex -= 1
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.interactiveSpring()) { dragOffset = 0 }
                }
            }
    }

    // MARK: - 追加ボタン

    private func addButtonArea(for type: String) -> some View {
        Button {
            addAlertType = type
            viewModel.isAddAlertPresented = true
        } label: {
            Text("カテゴリー追加")
                .font(AppFonts.rowTitle)
                .foregroundStyle(addButtonTextColor.opacity(addButtonTextOpacity))
                .frame(maxWidth: .infinity)
                .frame(height: AddButtonLayout.addRowHeight)
                .background(listBackgroundColor)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AddButtonLayout.separatorColor)
                .frame(height: AddButtonLayout.separatorHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AddButtonLayout.separatorColor)
                .frame(height: AddButtonLayout.separatorHeight)
        }
    }

    // MARK: - 説明エリア

    private var guideArea: some View {
        HStack {
            Text("↓ 削除ボタン")
                .font(.system(size: guideFontSize, weight: guideFontWeight))
                .foregroundStyle(guideTextColor.opacity(guideTextOpacity))
                .offset(x: guideLeftTextXOffset)

            Spacer()

            Text("並び替え ↓")
                .font(.system(size: guideFontSize, weight: guideFontWeight))
                .foregroundStyle(guideTextColor.opacity(guideTextOpacity))
                .offset(x: guideRightTextXOffset)
        }
        .padding(.horizontal, AddButtonLayout.guideHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: AddButtonLayout.guideAreaHeight)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            borderLine
        }
    }

    // MARK: - カテゴリー一覧

    private func categoryList(for type: String) -> some View {
        List {
            ForEach(categories(for: type)) { category in
                categoryButtonRow(category)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: listRowLeadingInset,
                            bottom: 0,
                            trailing: listRowTrailingInset
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(listBackgroundColor)
            }
            .onMove { source, destination in
                viewModel.moveCategories(
                    categories: categories(for: type),
                    from: source,
                    to: destination
                )
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .tint(Color.black.opacity(0.45))
        .padding(.top, listTopPadding)
        .padding(.bottom, listBottomPadding)
        .scrollContentBackground(.hidden)
        .background(listBackgroundColor)
    }

    // MARK: - カテゴリー行（NavigationLink不使用・Button方式）

    private func categoryButtonRow(_ category: CategoryData) -> some View {
        HStack(spacing: 0) {
            deleteButton(for: category)

            Button {
                // 横スワイプ（支出/収入切り替え）の指離し直後にタップ判定が拾われて
                // カテゴリー詳細が開いてしまうのを防ぐ（pageSwipeGesture参照）。
                guard !isDraggingPage else { return }
                selectedCategoryForEdit = category
            } label: {
                HStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(ColorHexConverter.color(from: safeColorHex(category.colorHex)))
                            .frame(width: 12, height: 12)

                        Text(category.name)
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(Color.black.opacity(categoryTextOpacity))
                    }
                    .padding(.leading, categoryTextLeadingPadding)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.4))
                        .padding(.trailing, chevronTrailingPadding)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .environment(\.editMode, .constant(.inactive))
        }
        .frame(maxWidth: .infinity)
        .frame(height: AddButtonLayout.listRowHeight)
        .background(listBackgroundColor)
        .overlay(alignment: .bottom) {
            rowSeparator
        }
    }

    // MARK: - 自作削除ボタン

    private func deleteButton(for category: CategoryData) -> some View {
        Button {
            categoryPendingDeletion = category
        } label: {
            Circle()
                .fill(deleteButtonColor)
                .frame(width: deleteButtonSize, height: deleteButtonSize)
                .overlay {
                    Rectangle()
                        .fill(deleteButtonMinusColor)
                        .frame(
                            width: deleteButtonSize * deleteMinusWidthRatio,
                            height: deleteMinusHeight
                        )
                        .clipShape(Capsule())
                }
        }
        .buttonStyle(.plain)
        .padding(.leading, deleteButtonLeadingPadding)
        .padding(.trailing, deleteButtonTrailingSpacing)
        .offset(x: deleteButtonXOffset, y: deleteButtonYOffset)
    }

    // MARK: - カテゴリー名テキスト

    private func categoryRowText(_ categoryName: String) -> some View {
        HStack {
            Text(categoryName)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(categoryTextOpacity))
                .padding(.leading, categoryTextLeadingPadding)
                .offset(x: categoryTextXOffset, y: categoryTextYOffset)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - colorHex フォールバック

    private func safeColorHex(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#CFCFCF" : hex
    }

    // MARK: - 行の区切り線

    private var rowSeparator: some View {
        Rectangle()
            .fill(Color.gray.opacity(rowSeparatorOpacity))
            .frame(height: rowSeparatorHeight)
            .padding(.leading, rowSeparatorLeadingPadding)
            .padding(.trailing, rowSeparatorTrailingPadding)
    }

    // MARK: - 共通線

    private var borderLine: some View {
        Rectangle()
            .fill(borderColor)
            .frame(height: borderHeight)
    }
}


