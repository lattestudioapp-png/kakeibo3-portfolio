import Foundation

// MARK: - 収支リスト変換Service

/**
 IncomeData と ExpenseData を、履歴リスト表示用の TransactionListItem に変換するService。
 リストの並び順、月フィルター、日付グループ化もここで担当する。
 */
struct TransactionListService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// incomeDataList / expenseDataList / transferDataList は呼び出し側（MonthlyTransactionListView）で
    /// 既に選択月ぶんだけに絞り込み済みという前提。ここでは月フィルタをかけ直さない
    /// （selectedDateは前月繰越の仮想アイテムの日付を組み立てるためだけに使う）。
    func makeItems(
        selectedDate: Date,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData],
        transferDataList: [TransferData] = [],
        carryoverAmount: Int = 0
    ) -> [TransactionListItem] {
        let incomeItems = incomeDataList.map { TransactionListItem.income(from: $0) }
        let expenseItems = expenseDataList.map { TransactionListItem.expense(from: $0) }
        let transferItems = transferDataList.map { TransactionListItem.transfer(from: $0) }

        var allItems = incomeItems + expenseItems + transferItems

        // 表示専用の前月繰越を先頭に追加（SwiftData には保存しない）。
        // 日付は「その月の1日」ではなく、月の開始日設定を反映した会計期間の実際の開始日にする
        // （並び順の起点として使うだけだが、カレンダーグリッドの区切りと一致させておく）。
        // selectedDateの暦月をそのままanchorとして使うと実際に属する会計期間とズレることが
        // あるため、range(containing:)でselectedDateが実際に属する会計期間を検索して求める。
        if carryoverAmount != 0 {
            let periodStart = AccountingMonthCalculator.range(containing: selectedDate, calendar: calendar)?.actualStartDate
                ?? calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))
            if let periodStart {
                allItems.append(TransactionListItem.carryover(firstDayOfMonth: periodStart, amount: carryoverAmount))
            }
        }

        return allItems.sorted {
            if calendar.isDate($0.date, inSameDayAs: $1.date) {
                return $0.createdAt > $1.createdAt
            } else {
                return $0.date > $1.date
            }
        }
    }

    func groupedItems(
        from items: [TransactionListItem]
    ) -> [Date: [TransactionListItem]] {
        Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }
    }

    func groupedDates(
        from groupedItems: [Date: [TransactionListItem]]
    ) -> [Date] {
        groupedItems
            .filter { !$0.value.isEmpty }
            .keys
            .sorted(by: >)
    }
}
