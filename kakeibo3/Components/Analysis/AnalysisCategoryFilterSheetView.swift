import SwiftUI

// MARK: - 分析「集計対象」カテゴリー選択シート
//
// 支出/収入タブの「集計対象」ボタンから開く。複数カテゴリーを選択し、
// 選んだカテゴリーだけをそのタブの集計対象（合計金額・円グラフ・カテゴリー別リスト）に絞り込む。
// 「すべて」を選ぶと絞り込みを解除する（＝nilとして扱う）。

struct AnalysisCategoryFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let categoryType: String
    let categories: [CategoryData]
    let onApply: (Set<String>?) -> Void

    @State private var selection: Set<String>

    init(categoryType: String, categories: [CategoryData], initialSelection: Set<String>?, onApply: @escaping (Set<String>?) -> Void) {
        self.categoryType = categoryType
        self.categories = categories
        self.onApply = onApply
        self._selection = State(initialValue: initialSelection ?? [])
    }

    private var isAllSelected: Bool { selection.isEmpty }

    private var sortedCategories: [CategoryData] {
        categories.sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = []
                    } label: {
                        HStack {
                            Text("すべて")
                                .font(AppFonts.rowTitle)
                                .foregroundStyle(Color.black.opacity(0.8))
                            Spacer()
                            if isAllSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.main)
                            }
                        }
                        .frame(minHeight: AppLayout.selectionRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    if sortedCategories.isEmpty {
                        Text("カテゴリーが登録されていません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    } else {
                        ForEach(sortedCategories) { category in
                            categoryRow(category)
                        }
                    }
                } header: {
                    Text("\(categoryType)カテゴリー")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("集計対象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        onApply(selection.isEmpty ? nil : selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.main)
                }
            }
        }
    }

    private func categoryRow(_ category: CategoryData) -> some View {
        Button {
            toggle(category.name)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(ColorHexConverter.color(from: CategoryColorPalette.normalize(category.colorHex)))
                    .frame(width: 12, height: 12)
                Text(category.name)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                if selection.contains(category.name) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.main)
                }
            }
            .frame(minHeight: AppLayout.selectionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ name: String) {
        if selection.contains(name) {
            selection.remove(name)
        } else {
            selection.insert(name)
        }
    }
}
