import SwiftUI

// MARK: - OCR読み取り結果の確認画面（ヘッダー + 商品一覧）

struct ReceiptReviewView: View {
    @Binding var draft: ReceiptDraft
    let onEditHeader: () -> Void
    let onEditItem: (UUID) -> Void
    let onRetake: () -> Void
    let onSave: () -> Void
    let saveErrorMessage: String?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                headerCard
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                itemListCard
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }

            bottomBar
        }
        .background(AppColors.sheetBackground)
    }

    // MARK: - ヘッダー

    private var headerCard: some View {
        Button(action: onEditHeader) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(draft.date.map { dateFormatter.string(from: $0) } ?? "未設定")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.gray.opacity(0.5))
                }

                Text(draft.storeName ?? "未設定")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black.opacity(0.65))

                Text("支払い方法：\(draft.paymentMethod ?? "未設定")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.5))

                Divider()

                HStack {
                    Text("レシート合計")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.5))
                    Spacer()
                    Text(draft.receiptTotal.map { "¥\($0)" } ?? "未設定")
                        .font(.system(size: 14, weight: .medium))
                }
                HStack {
                    Text("商品合計")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.5))
                    Spacer()
                    Text("¥\(draft.itemsTotal)")
                        .font(.system(size: 14, weight: .medium))
                }

                if draft.hasTotalMismatch {
                    HStack {
                        Text("差額")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("¥\(draft.mismatchAmount)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Color.red)
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 商品一覧

    private var itemListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("商品一覧")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.5))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 50) }
                    ReceiptReviewRowView(
                        item: item,
                        onToggle: { draft.items[index].isIncluded.toggle() },
                        onTap: { onEditItem(item.id) }
                    )
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
    }

    // MARK: - 下部ボタン

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 24)
            }
            HStack(spacing: 12) {
                Button(action: onRetake) {
                    Text("撮り直す")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button(action: onSave) {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.main)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
    }
}
