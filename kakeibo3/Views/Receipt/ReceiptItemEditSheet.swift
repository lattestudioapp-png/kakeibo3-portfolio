import SwiftUI

// MARK: - 商品1件の編集シート（商品名・金額・カテゴリー）

struct ReceiptItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var productName: String
    @State private var amountText: String
    @State private var category: String

    let availableCategories: [String]
    let onSave: (String, Int, String) -> Void

    init(item: ReceiptDraftItem, availableCategories: [String], onSave: @escaping (String, Int, String) -> Void) {
        _productName = State(initialValue: item.productName)
        _amountText = State(initialValue: String(item.amount))
        _category = State(initialValue: item.category)
        self.availableCategories = availableCategories
        self.onSave = onSave
    }

    private var parsedAmount: Int? {
        Int(amountText.filter(\.isNumber))
    }

    private var canSave: Bool {
        !productName.trimmingCharacters(in: .whitespaces).isEmpty
            && (parsedAmount ?? 0) > 0
            && category != ReceiptCategorySuggestionService.unsetCategory
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldSection(title: "商品名") {
                        TextField("商品名を入力", text: $productName)
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    fieldSection(title: "金額") {
                        TextField("金額を入力", text: $amountText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    fieldSection(title: "カテゴリー") {
                        categoryGrid
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("商品を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(productName.trimmingCharacters(in: .whitespaces), parsedAmount ?? 0, category)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func fieldSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.5))
            content()
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(availableCategories, id: \.self) { name in
                Button {
                    category = name
                } label: {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(category == name ? AppColors.main : Color.black.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(category == name ? AppColors.main.opacity(0.12) : Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(category == name ? AppColors.main : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
