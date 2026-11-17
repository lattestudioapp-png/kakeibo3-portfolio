import SwiftUI
import Combine

// MARK: - カテゴリー詳細編集画面

/**
 1つのCategoryDataを編集する画面。

 できること:
 - カテゴリー名を変更
 - グラフ色を表示
 - カテゴリーを削除
 */
struct CategoryDetailEditView: View {

    // MARK: - SwiftData


    /**
     編集対象のカテゴリー。CategoryDataはCore Data移行によりstructになったため、
     @Bindableではなく@Stateで画面内の一時的な変更を保持する
     （保存はonChange経由でCategoryDataSync.updateへ都度反映する）。
     */
    @State private var category: CategoryData

    /**
     重複チェック用の全カテゴリー一覧。
     */
    let allCategories: [CategoryData]

    init(category: CategoryData, allCategories: [CategoryData]) {
        self._category = State(initialValue: category)
        self.allCategories = allCategories
    }

    // MARK: - 環境値

    @Environment(\.dismiss) private var dismiss

    // MARK: - ViewModel

    @StateObject private var viewModel = CategoryEditViewModel()

    // MARK: - 色選択シート

    @State private var isColorPickerPresented = false

    // MARK: - 色設定

    private var backgroundColor: Color { AppColors.sheetBackground }
    private let rowBackgroundColor = Color.white
    private let lineColor = AppColors.line
    private let deleteTextColor = Color.red.opacity(0.75)
    private let chevronColor = Color.gray.opacity(0.45)

    // MARK: - 行設定

    private let categoryNameRowHeight: CGFloat = AppLayout.textFieldRowHeight
    private let graphColorRowHeight: CGFloat = AppLayout.selectionRowHeight
    private let rowHorizontalPadding: CGFloat = 28
    private let rowTextOpacity: Double = 0.78
    private let colorSquareSize: CGFloat = AppLayout.categoryColorPreviewSize
    private let colorSquareCornerRadius: CGFloat = 6
    private let chevronFontSize: CGFloat = 16
    private let lineHeight: CGFloat = 1

    // MARK: - 削除ボタン設定

    private let deleteButtonHeight: CGFloat = 58
    private let deleteButtonWidth: CGFloat = 310
    private let deleteButtonCornerRadius: CGFloat = 28
    private let deleteButtonFontSize: CGFloat = 20
    private let deleteButtonBottomPadding: CGFloat = 42

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            headerArea
            categoryNameRow
            graphColorRow
            suspendToggleRow
            Spacer()
            deleteButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backgroundColor.ignoresSafeArea() }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // この画面はcategoryをローカルで直接書き換えるため、値の変化を検知して
        // Core Data側へも反映する。
        .onChange(of: category.isSuspended) { _, _ in
            CategoryDataSync.update(category)
        }
        .onChange(of: category.colorHex) { _, _ in
            CategoryDataSync.update(category)
        }
        .sheet(isPresented: $isColorPickerPresented) {
            colorPickerSheet
        }
        .alert("カテゴリー名を変更", isPresented: $viewModel.isRenameAlertPresented) {
            TextField("カテゴリー名", text: $viewModel.editingCategoryName)

            Button("変更") {
                viewModel.renameCategory(
                    category: category,
                    newName: viewModel.editingCategoryName,
                    existingCategories: allCategories
                )
            }

            Button("キャンセル", role: .cancel) {
                viewModel.editingCategoryName = category.name
            }
        } message: {
            Text("新しいカテゴリー名を入力してください")
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
    }

    // MARK: - ヘッダー

    private var headerArea: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppHeaderTitleView(title: category.name)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

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

    // MARK: - カテゴリー名行

    private var categoryNameRow: some View {
        Button {
            viewModel.editingCategoryName = category.name
            viewModel.isRenameAlertPresented = true
        } label: {
            HStack {
                Text(category.name)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(rowTextOpacity))

                Spacer()
            }
            .padding(.horizontal, rowHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: categoryNameRowHeight)
            .background(rowBackgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            line
        }
    }

    // MARK: - グラフ色行

    private var graphColorRow: some View {
        Button {
            isColorPickerPresented = true
        } label: {
            HStack {
                Text("グラフの色")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(rowTextOpacity))

                Spacer()

                RoundedRectangle(cornerRadius: colorSquareCornerRadius)
                    .fill(ColorHexConverter.color(from: category.colorHex))
                    .frame(width: colorSquareSize, height: colorSquareSize)

                Image(systemName: "chevron.right")
                    .font(.system(size: chevronFontSize, weight: .semibold))
                    .foregroundStyle(chevronColor)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, rowHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: graphColorRowHeight)
            .background(rowBackgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            line
        }
    }

    // MARK: - 使用停止行

    private var suspendToggleRow: some View {
        HStack {
            Text("非表示")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(rowTextOpacity))

            Spacer()

            Toggle("", isOn: Binding(
                get: { category.isSuspended },
                set: { category.isSuspended = $0 }
            ))
            .labelsHidden()
            .tint(AppColors.main)
        }
        .padding(.horizontal, rowHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: graphColorRowHeight)
        .background(rowBackgroundColor)
        .overlay(alignment: .bottom) {
            line
        }
    }

    // MARK: - カラーピッカーシート

    private var colorPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Text("グラフの色")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))

                Spacer()

                Button("完了") {
                    isColorPickerPresented = false
                }
                .font(AppFonts.button)
                .foregroundStyle(AppColors.main)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            CategoryColorPickerView(selectedColorHex: $category.colorHex)
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.fraction(0.72)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 削除ボタン

    private var isProtectedCategory: Bool {
        category.isProtected || (category.name == "初期残高" && category.type == "収入")
    }

    private var deleteButton: some View {
        Button {
            guard !isProtectedCategory else {
                viewModel.errorAlertMessage = "初期残高カテゴリーは削除できません。"
                return
            }
            dismiss()
            viewModel.deleteCategory(
                category: category
            )
        } label: {
            Text("このカテゴリーを削除")
                .font(.system(size: deleteButtonFontSize, weight: .regular))
                .foregroundStyle(deleteTextColor)
                .frame(width: deleteButtonWidth)
                .frame(height: deleteButtonHeight)
                .background(Color.white)
                .clipShape(
                    RoundedRectangle(cornerRadius: deleteButtonCornerRadius)
                )
        }
        .padding(.bottom, deleteButtonBottomPadding)
    }

    // MARK: - 共通線

    private var line: some View {
        Rectangle()
            .fill(lineColor)
            .frame(height: lineHeight)
    }
}
