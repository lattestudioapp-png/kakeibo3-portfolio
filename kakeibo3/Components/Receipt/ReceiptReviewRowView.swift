import SwiftUI

// MARK: - レシート読み取り結果の商品1行

struct ReceiptReviewRowView: View {
    let item: ReceiptDraftItem
    let onToggle: () -> Void
    let onTap: () -> Void

    private var isUnsetCategory: Bool {
        item.category == ReceiptCategorySuggestionService.unsetCategory
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: item.isIncluded ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(item.isIncluded ? AppColors.main : Color.gray.opacity(0.4))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName.isEmpty ? "未設定" : item.productName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.black.opacity(item.isIncluded ? 0.85 : 0.35))

                    HStack(spacing: 6) {
                        Text(item.category)
                            .font(.system(size: 12))
                            .foregroundStyle(isUnsetCategory ? Color.red : AppColors.main)
                        if item.category == item.suggestedCategory && !isUnsetCategory {
                            Text("(候補)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.gray.opacity(0.6))
                        }
                    }
                }

                Spacer()

                Text("¥\(item.amount)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(item.isIncluded ? 0.85 : 0.35))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
