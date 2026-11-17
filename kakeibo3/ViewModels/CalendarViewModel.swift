import Foundation
import SwiftUI
import Combine

final class CalendarViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published var selectedDay = Date()
    @Published var inputTargetDate = Date()
    @Published var isDayActionPresented = false

    // MARK: - 月集計キャッシュ
    //
    // 日別合計・月合計・前月繰越をまとめて保持する。
    // isDayActionPresented などの無関係な @Published 変更で
    // グリッドの42セル分の再集計が走らないように、
    // 月変更・取引データ変更のときだけ rebuildMonthAggregate を呼んで更新する。

    @Published private(set) var monthAggregate: CalendarMonthAggregate = .empty

    private let calendarService = CalendarTransactionService()
    private var lastAggregateKey: String = ""

    /// 変化検知用のキーが変わっていなければ再集計をスキップする。
    /// dailySnapshots はグリッド42セル分（前後月の余白セルを含む）の範囲で渡す。
    /// allMonthlySnapshots は全期間ぶん渡す（表示月にMonthlySnapshotが無い＝未来月の場合、
    /// 直近の過去月の月末残高を繰越として使うため、選択月以外の変化も検知する必要がある）。
    func rebuildMonthAggregateIfNeeded(dailySnapshots: [DailySnapshot], allMonthlySnapshots: [MonthlySnapshot]) {
        let key = aggregateKey(dailySnapshots: dailySnapshots, allMonthlySnapshots: allMonthlySnapshots)
        guard key != lastAggregateKey else { return }
        lastAggregateKey = key
        monthAggregate = calendarService.monthAggregate(
            selectedDate: selectedDate,
            dailySnapshots: dailySnapshots,
            allMonthlySnapshots: allMonthlySnapshots
        )
    }

    // グリッドは前後月の余白セルも含むため、dailySnapshots自体の更新時刻を使って変化検知する
    // （選択中の月のMonthlySnapshotだけを見ると、隣接月側の余白セルの変更を見逃すため）。
    // allMonthlySnapshotsは全体を見る（未来月表示時、繰越の元になる過去月の変化も拾う必要があるため）。
    //
    // selectedDateの暦月ではなく、実際に属する会計期間のanchorをキーに使う。月の開始日設定
    // 次第では、同じ暦月内でもselectedDateの移動（例：7/9→7/10、開始日=10日）が別の会計期間への
    // 移動になることがあり、暦月だけを見ていると再集計を見逃してしまうため。
    private func aggregateKey(dailySnapshots: [DailySnapshot], allMonthlySnapshots: [MonthlySnapshot]) -> String {
        let anchor = AccountingMonthCalculator.range(containing: selectedDate)
        let anchorPart = anchor.map { "\($0.anchorYear)-\($0.anchorMonth)" } ?? "0-0"
        let dailyPart = dailySnapshots.reduce(0.0) { $0 + $1.updatedAt.timeIntervalSinceReferenceDate }
        let monthlyPart = allMonthlySnapshots.reduce(0.0) { $0 + $1.updatedAt.timeIntervalSinceReferenceDate }
        return "\(anchorPart)|\(dailySnapshots.count)-\(dailyPart)|\(allMonthlySnapshots.count)-\(monthlyPart)"
    }

    func selectDay(_ date: Date) {
        selectedDay = date
        selectedDate = date
        inputTargetDate = date
        withAnimation(.easeOut(duration: 0.2)) {
            isDayActionPresented = true
        }
    }

    func closeDayAction() {
        withAnimation(.easeOut(duration: 0.15)) {
            isDayActionPresented = false
        }
    }

    func moveToDate(_ date: Date) {
        selectedDay = date
        selectedDate = date
    }
}
