import SwiftUI

// MARK: - 選択中の月だけをfetchしてTransactionListComponentへ渡すコンテナ
//
// 以前は TransactionListComponent が ExpenseData / IncomeData / TransferData を
// 全件 @Query して selectedDate と同じ月だけ filter していたため、20年ぶんデータが
// 溜まるとスクロール・再描画のたびに全件 filter / map / sort / grouping が走って重かった。
//
// ここでは selectedDate から月初(monthStart)〜翌月月初(nextMonthStart)を作り、
// #Predicate で SwiftData 側に絞り込みを任せる（全件読んでから filter しない）。
//
// @Query の述語は「このViewのinitが呼ばれた時」に固定される。selectedDateが変わるたびに
// 親（CalendarView）がこのViewを新しい値として作り直すことで、initが再実行され述語も更新される
// （selectedDateをこのView自身の内部状態にすると、initが再実行されず古い月のままになるので注意）。
struct MonthlyTransactionListView: View {
    let selectedDate: Date
    /// 表示月の前月繰越額。カレンダー側で既にMonthlySnapshotから計算済みの値をそのまま使う
    /// （ここで全収入・全支出から計算し直すと、結局20年ぶんの全件読み込みが復活してしまうため）。
    let carryoverAmount: Int
    let onSelectTransaction: (TransactionListItem) -> Void


    @StateObject private var incomeDataObserver: CoreDataListObserver<CDIncomeData, IncomeData>
    private var incomeDataList: [IncomeData] { incomeDataObserver.items }
    @StateObject private var expenseDataObserver: CoreDataListObserver<CDExpenseData, ExpenseData>
    private var expenseDataList: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var transferDataObserver: CoreDataListObserver<CDTransferData, TransferData>
    private var transferDataList: [TransferData] { transferDataObserver.items }

    @AppStorage("showPreviousMonthCarryover") private var showCarryover = false

    private static let transactionListService = TransactionListService()
    private let transactionRepository: TransactionRepository = SwiftDataTransactionRepository()

    // selectedDateと同じ理由（initが呼ばれた時点で#Predicateが固定される）で、
    // bookIdが変わった時も親（CalendarView）がこのViewを新しい値として作り直す必要がある。
    init(
        selectedDate: Date,
        carryoverAmount: Int,
        bookId: UUID,
        onSelectTransaction: @escaping (TransactionListItem) -> Void
    ) {
        self.selectedDate = selectedDate
        self.carryoverAmount = carryoverAmount
        self.onSelectTransaction = onSelectTransaction

        // 月の開始日設定を反映した会計月の実際の期間（カレンダーグリッドと同じ基準）で絞り込む。
        // selectedDateの暦月をそのままanchorとして使うと、月の開始日設定次第では実際に属する
        // 会計期間とズレることがあるため、range(containing:)でselectedDateが実際に属する
        // 会計期間を検索して求める。
        let calendar = Calendar.current
        let accountingRange = AccountingMonthCalculator.range(containing: selectedDate, calendar: calendar)
        let monthStart = accountingRange?.actualStartDate
            ?? (calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate)
        let nextMonthStart = accountingRange?.actualEndDate ?? (calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart)

        let incomePredicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", monthStart as NSDate, nextMonthStart as NSDate, bookId as CVarArg)
        _incomeDataObserver = StateObject(wrappedValue: IncomeDataSync.observer(matching: incomePredicate))
        let expensePredicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", monthStart as NSDate, nextMonthStart as NSDate, bookId as CVarArg)
        _expenseDataObserver = StateObject(wrappedValue: ExpenseDataSync.observer(matching: expensePredicate))
        let transferPredicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", monthStart as NSDate, nextMonthStart as NSDate, bookId as CVarArg)
        _transferDataObserver = StateObject(wrappedValue: TransferDataSync.observer(matching: transferPredicate))
    }

    var body: some View {
        TransactionListComponent(
            selectedDate: selectedDate,
            items: items,
            onSelectTransaction: onSelectTransaction,
            onDelete: deleteItem
        )
    }

    // 選択月ぶん（最大でも数十〜数百件程度）だけが対象のため、都度組み立てても軽い。
    private var items: [TransactionListItem] {
        Self.transactionListService.makeItems(
            selectedDate: selectedDate,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList,
            transferDataList: transferDataList,
            carryoverAmount: showCarryover ? carryoverAmount : 0
        )
    }

    // MARK: - 削除
    //
    // @Query が選択月だけに絞られているため、sourceId の検索も選択月内の配列だけで済む。
    // 即時完全削除ではなく、ゴミ箱へ移動する（30日後に自動で完全削除される）。

    private func deleteItem(_ item: TransactionListItem) {
        _ = try? transactionRepository.trashTransaction(
            originalItem: item,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList,
            transferDataList: transferDataList
        )
    }
}
