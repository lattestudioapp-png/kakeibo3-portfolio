import SwiftUI

// MARK: - カテゴリーScrollView スクロール位置 PreferenceKey

struct CategoryScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 最もスクロールされている（最も負の）値を採用する
        value = min(value, nextValue())
    }
}

// MARK: - カテゴリー選択エリア

/**
 入力フォーム内のカテゴリー選択エリア。

 カテゴリー一覧はSwiftDataのCategoryDataから作られた[String]を受け取る。
 このView自身はSwiftDataを直接操作せず、表示と選択だけを担当する。
 */
struct CategorySelectAreaView: View {

    // MARK: - Binding

    @Binding var selectedCategory: String
    @Binding var isCategoryEditPresented: Bool

    // MARK: - カテゴリー一覧

    let expenseCategories: [String]
    let incomeCategories: [String]

    // MARK: - 入力状態

    let selectedType: String
    let expenseSetting: TransactionInputSetting
    let layout: InputFormLayout
    let onCategoryChanged: ([String]) -> Void
    var isDraggingPage: Bool = false

    // MARK: - 現在表示するカテゴリー

    private var currentCategories: [String] {
        selectedType == expenseSetting.typeName ? expenseCategories : incomeCategories
    }

    // MARK: - 疑似バウンス

    @State private var localScrollOffsetY: CGFloat = 0
    private let categoryVisualPullMax: CGFloat = 80
    private let categoryVisualPullResistance: CGFloat = 0.7

    private var visualPullOffset: CGFloat {
        min(max(localScrollOffsetY, 0) * categoryVisualPullResistance, categoryVisualPullMax)
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            categoryHeader
            categoryScrollArea
        }
        .onPreferenceChange(CategoryScrollOffsetPreferenceKey.self) { value in
            localScrollOffsetY = value
        }
    }

    // MARK: - ヘッダー

    private var categoryHeader: some View {
        HStack {
            Text("カテゴリー")
                .font(layout.rowTitleFont)
                .foregroundStyle(Color.black)

            Spacer()

            Button("追加 / 編集") {
                isCategoryEditPresented = true
            }
            .font(layout.categoryEditButtonFont)
            .foregroundStyle(layout.mainColor)
        }
        .padding(.horizontal, layout.rowHorizontalPadding)
        .frame(height: layout.categoryHeaderHeight)
        .background(layout.backgroundColor)
    }

    // MARK: - カテゴリー一覧

    private var categoryScrollArea: some View {
        ScrollView(.vertical, showsIndicators: true) {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: CategoryScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("CategoryScroll")).minY
                    )
            }
            .frame(height: 0)

            Color.clear
                .frame(height: visualPullOffset)

            LazyVGrid(
                columns: layout.categoryColumns,
                spacing: layout.categoryGridSpacing
            ) {
                // id: \.self（カテゴリー名文字列）だと、同名のカテゴリーが2つある場合に
                // SwiftUIがIDの重複と判断し、2つ目以降が描画されなくなる。
                // 配列内の位置を組み合わせて必ず一意なIDにする。
                ForEach(Array(currentCategories.enumerated()), id: \.offset) { _, category in
                    Button {
                        guard !isDraggingPage else { return }
                        selectedCategory = category
                    } label: {
                        Text(category)
                            .font(layout.categoryButtonFont)
                            .foregroundStyle(
                                selectedCategory == category
                                ? layout.mainColor
                                : layout.unselectedCategoryTextColor
                            )
                            .minimumScaleFactor(layout.categoryMinimumScaleFactor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: layout.categoryButtonHeight)
                            .background(
                                selectedCategory == category
                                ? layout.mainColor.opacity(layout.selectedCategoryBackgroundOpacity)
                                : layout.rowBackgroundColor
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: layout.categoryButtonCornerRadius)
                                    .stroke(
                                        selectedCategory == category
                                        ? layout.mainColor
                                        : layout.lineColor,
                                        lineWidth: selectedCategory == category
                                        ? layout.selectedCategoryLineWidth
                                        : layout.unselectedCategoryLineWidth
                                    )
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: layout.categoryButtonCornerRadius)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.categoryHorizontalPadding)
            .padding(.top, layout.categoryGridTopPadding)
            .padding(.bottom, layout.categoryGridBottomPadding)
        }
        .coordinateSpace(name: "CategoryScroll")
        .frame(maxHeight: .infinity)
        .background(layout.backgroundColor)
        .onChange(of: currentCategories) { _, newCategories in
            onCategoryChanged(newCategories)
        }
    }
}
