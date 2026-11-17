import SwiftUI

// MARK: - 取引リスト表示（選択月のitemsを受け取って表示するだけ）
//
// 以前はここで ExpenseData / IncomeData / TransferData を全件 @Query し、
// selectedDate と同じ月だけ filter していたため、20年ぶんデータが溜まると
// スクロール・再描画のたびに全件 filter / map / sort / grouping が走って重かった。
// 現在は選択月ぶんだけ fetch 済みの items を親（MonthlyTransactionListView）から受け取り、
// ここでは日付ごとの grouping と表示だけを担当する。

struct TransactionListComponent: View {
    let selectedDate: Date
    let items: [TransactionListItem]
    let onSelectTransaction: (TransactionListItem) -> Void
    let onDelete: (TransactionListItem) -> Void

    // 日付グループ化は items が実際に変化した時だけ作り直す（onAppear / onChange(of: items)）。
    // body 内で直接 Dictionary(grouping:) すると、openItemID / isDraggingList など
    // 無関係な @State 変更のたびに grouping をやり直してしまうため @State にキャッシュする。
    @State private var groupedItems: [Date: [TransactionListItem]] = [:]
    @State private var groupedDates: [Date] = []
    @State private var openItemID: UUID?

    // スクロール中の誤タップ防止（縦方向に一定量ドラッグしたらタップを無効化する）
    @State private var isDraggingList = false
    private let dragTapCancelThreshold: CGFloat = 10

    private static let transactionListService = TransactionListService()

    private let dividerLeadingPadding: CGFloat = 0
    private let dividerTrailingPadding: CGFloat = 0

    private let listBackgroundColor = Color.white

    private let emptyLineDividerOpacity: Double = 0.15
    private let emptyLineCount: Int = 12
    private let emptyLineHeight: CGFloat = 50

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("topAnchor")

                    ForEach(groupedDates, id: \.self) { date in
                        dateSection(date)
                    }

                    emptyLines

                    Color.clear
                        .frame(height: AppLayout.bottomNavigationHeight)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(listBackgroundColor)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if abs(value.translation.height) > dragTapCancelThreshold, !isDraggingList {
                            isDraggingList = true
                        }
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isDraggingList = false
                        }
                    }
            )
            .onAppear {
                rebuildGroups()
                DispatchQueue.main.async {
                    proxy.scrollTo("topAnchor", anchor: .top)
                }
            }
            .onChange(of: items) { _, _ in
                rebuildGroups()
            }
            .onChange(of: selectedDate) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("topAnchor", anchor: .top)
                }
            }
        }
    }

    // MARK: - グルーピングの再計算

    private func rebuildGroups() {
        let newGroupedItems = Self.transactionListService.groupedItems(from: items)
        groupedItems = newGroupedItems
        groupedDates = Self.transactionListService.groupedDates(from: newGroupedItems)
    }

    // MARK: - 日付セクション

    private func dateSection(_ date: Date) -> some View {
        DateGroupedTransactionSection(
            date: date,
            items: groupedItems[date] ?? [],
            openItemID: $openItemID,
            onTap: onSelectTransaction,
            onDelete: deleteItem,
            isDraggingList: isDraggingList
        )
    }

    // MARK: - 削除

    private func deleteItem(_ item: TransactionListItem) {
        openItemID = nil
        onDelete(item)
    }

    private var emptyLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<emptyLineCount, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: emptyLineHeight)
                    .overlay(alignment: .bottom) {
                        Divider()
                            .background(Color.gray.opacity(emptyLineDividerOpacity))
                            .padding(.leading, dividerLeadingPadding)
                            .padding(.trailing, dividerTrailingPadding)
                    }
            }
        }
    }
}
