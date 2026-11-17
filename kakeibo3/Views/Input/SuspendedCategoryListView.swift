import SwiftUI

// MARK: - 使用停止カテゴリー一覧
//
// 「その他 > カテゴリー」の各ページ（支出/収入）から遷移する、使用停止中のカテゴリーだけを表示する画面。
// タップすると既存のCategoryDetailEditViewを開き、使用停止をOFFに戻せる（再開すると通常のカテゴリー編集一覧に復活する）。

struct SuspendedCategoryListView: View {
    @Environment(\.dismiss) private var dismiss

    let type: String
    let categories: [CategoryData]

    @State private var selectedCategoryForEdit: CategoryData?

    private var suspendedCategories: [CategoryData] {
        categories
            .filter { $0.type == type && $0.isSuspended }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                } else {
                    return $0.sortOrder < $1.sortOrder
                }
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if suspendedCategories.isEmpty {
                    Text("非表示中のカテゴリーはありません")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.35))
                } else {
                    ForEach(suspendedCategories) { category in
                        Button {
                            selectedCategoryForEdit = category
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(ColorHexConverter.color(from: category.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(category.name)
                                    .font(AppFonts.rowTitle)
                                    .foregroundStyle(Color.black.opacity(0.8))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.gray.opacity(0.4))
                            }
                            .frame(minHeight: AppLayout.selectionRowHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("非表示カテゴリー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .sheet(item: $selectedCategoryForEdit) { category in
                CategoryDetailEditView(
                    category: category,
                    allCategories: categories
                )
            }
        }
    }
}
