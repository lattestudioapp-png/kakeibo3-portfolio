import SwiftUI

// MARK: - 分析詳細画面共通「項目」リストカード
//
// 用途: 資産詳細・カテゴリ詳細・支払い方法詳細で
//       日付グループ化・カレンダー同一レイアウトの取引一覧を表示する。

struct AnalysisItemListCard: View {
    let items: [TransactionListItem]
    @Binding var openItemID: UUID?
    var onTap: ((TransactionListItem) -> Void)? = nil
    let onDelete: (TransactionListItem) -> Void

    // MARK: - 日付グループ（新しい順）

    private var groupedDates: [Date] {
        let cal = Calendar.current
        return Set(items.map { cal.startOfDay(for: $0.date) }).sorted(by: >)
    }

    private func group(for date: Date) -> [TransactionListItem] {
        let cal = Calendar.current
        return items
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            itemsHeading
            Divider()

            if items.isEmpty {
                emptyState
            } else {
                ForEach(groupedDates, id: \.self) { date in
                    DateGroupedTransactionSection(
                        date: date,
                        items: group(for: date),
                        openItemID: $openItemID,
                        onTap: onTap,
                        onDelete: onDelete
                    )
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - 見出し

    private var itemsHeading: some View {
        Text("項目")
            .font(AppFonts.sectionTitle)
            .foregroundStyle(Color.black.opacity(0.65))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
    }

    // MARK: - 空状態

    private var emptyState: some View {
        Text("取引がありません")
            .font(AppFonts.body)
            .foregroundStyle(Color.black.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
    }

}
