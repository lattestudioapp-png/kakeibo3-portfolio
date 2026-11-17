import SwiftUI
import Combine

struct CalendarMonthGridView: View {
    @ObservedObject var viewModel: CalendarViewModel

    // 全期間ぶんクエリするが、行数は「取引件数」ではなく「履歴の日数/月数」に比例するため、
    // 取引が増えても軽い（DailySnapshot/MonthlySnapshotの粒度で事前集計済みのため）
    @StateObject private var dailySnapshotObserver = DailySnapshotSync.observer()
    private var allDailySnapshots: [DailySnapshot] { dailySnapshotObserver.items }
    @StateObject private var monthlySnapshotObserver = MonthlySnapshotSync.observer()
    private var allMonthlySnapshots: [MonthlySnapshot] { monthlySnapshotObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage("showPreviousMonthCarryover") private var showCarryover = false
    @AppStorage(CalendarWeekStartSettings.storageKey) private var weekStartWeekday: Int = CalendarWeekStartSettings.defaultValue
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private let calendarTransactionService = CalendarTransactionService()
    private let calendar = Calendar.current
    private var backgroundColor: Color { AppColors.background }
    private let weekHeaderBackgroundColor = Color.white
    private let gridLineColor = Color.gray.opacity(0.35)
    private let weekdayTextColor = Color.gray
    private let sundayTextColor = Color(red: 0.70, green: 0.32, blue: 0.18)
    private let saturdayTextColor = Color.indigo.opacity(0.75)
    private let calendarHorizontalPadding: CGFloat = 0
    private let calendarTopPadding: CGFloat = 0
    private let weekHeaderHeight: CGFloat = 18
    private let gridLineWidth: CGFloat = 0.7
    private let dayCellHeight: CGFloat = 36

    // MARK: - 横スワイプでの月切り替え（見た目・ジェスチャーのみ。日付判定/集計ロジックには一切触れない）

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var settleOffset: CGFloat = 0
    @State private var isSettling = false

    private let swipeAnimationDuration: Double = 0.28
    private let commitDistanceRatio: CGFloat = 0.3
    private let commitFlingRatio: CGFloat = 0.6

    // 週の開始曜日設定に応じて、日月火水木金土を回転させた順序を返す
    private var weekSymbols: [String] {
        let base = ["日", "月", "火", "水", "木", "金", "土"]
        let startIndex = CalendarWeekStartSettings.clamped(weekStartWeekday) - 1
        return (0..<7).map { base[(startIndex + $0) % 7] }
    }

    // MonthSelectorView.moveMonthと全く同じ計算（AccountingMonthCalculatorの既存公開APIを
    // 呼ぶだけで、開始日・前倒し/後ろ倒し等の計算そのものには一切手を加えない）。
    private func adjacentMonthDate(offset: Int) -> Date? {
        guard let currentRange = AccountingMonthCalculator.range(containing: viewModel.selectedDate, calendar: calendar)
        else { return nil }
        let nextAnchor = AccountingMonthCalculator.adjacentAnchor(
            year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: offset
        )
        guard let nextRange = AccountingMonthCalculator.range(anchorYear: nextAnchor.year, anchorMonth: nextAnchor.month, calendar: calendar)
        else { return nil }
        return nextRange.actualStartDate
    }

    private var previousDate: Date { adjacentMonthDate(offset: -1) ?? viewModel.selectedDate }
    private var nextDate: Date { adjacentMonthDate(offset: 1) ?? viewModel.selectedDate }

    // 日付グリッドは既存のmakeCalendarDaysをそのまま呼ぶだけで、キャッシュしない
    // （Calendarの日付演算のみで軽く、常にライブ計算することで表示のズレを防ぐ）。
    private func days(for date: Date) -> [CalendarMonthDay] {
        calendarTransactionService.makeCalendarDays(selectedDate: date)
    }

    private var currentDays: [CalendarMonthDay] { days(for: viewModel.selectedDate) }
    private var previousDays: [CalendarMonthDay] { days(for: previousDate) }
    private var nextDays: [CalendarMonthDay] { days(for: nextDate) }

    // 表示中の月の週数だけをグリッドの高さに反映する（前後月の週数に引っ張られないようにする）。
    private var pageRowCount: Int { currentDays.count / 7 }

    private var bookMonthlySnapshots: [MonthlySnapshot] {
        guard let currentBookId else { return [] }
        return allMonthlySnapshots.filter { $0.bookId == currentBookId }
    }

    // 前後月プレビュー用の金額集計。既存のmonthAggregate/aggregateDateRangeを呼ぶだけで、
    // 集計ロジック自体には手を加えない（表示中の月は既存のviewModel.monthAggregateをそのまま使う）。
    private func previewAggregate(for date: Date) -> CalendarMonthAggregate {
        guard let currentBookId,
              let range = calendarTransactionService.aggregateDateRange(selectedDate: date)
        else { return .empty }
        let snapshots = allDailySnapshots.filter { $0.date >= range.start && $0.date < range.end && $0.bookId == currentBookId }
        return calendarTransactionService.monthAggregate(
            selectedDate: date, dailySnapshots: snapshots, allMonthlySnapshots: bookMonthlySnapshots
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            calendarPager
        }
        .background(weekHeaderBackgroundColor)
        .padding(.horizontal, calendarHorizontalPadding)
        .padding(.top, calendarTopPadding)
        .background(backgroundColor)
        .onAppear { rebuildAggregate() }
        .onChange(of: viewModel.selectedDate) { _, _ in rebuildAggregate() }
        .onChange(of: snapshotVersionKey) { _, _ in rebuildAggregate() }
        .onChange(of: selectedBookIdString) { _, _ in rebuildAggregate() }
    }

    // ロック状態の変化・取引の保存/編集/削除はすべてSnapshotManagerの更新を経由するため、
    // DailySnapshot/MonthlySnapshotのupdatedAtを見るだけで変化を検知できる
    // （行数は履歴の日数/月数ぶんなので取引件数が増えても軽い）
    private var snapshotVersionKey: String {
        let dailyPart = allDailySnapshots.reduce(0.0) { $0 + $1.updatedAt.timeIntervalSinceReferenceDate }
        let monthlyPart = allMonthlySnapshots.reduce(0.0) { $0 + $1.updatedAt.timeIntervalSinceReferenceDate }
        return "\(allDailySnapshots.count)-\(dailyPart)|\(allMonthlySnapshots.count)-\(monthlyPart)"
    }

    private func rebuildAggregate() {
        guard let currentBookId else { return }
        // グリッド42セル分に加え、月の開始日設定によっては集計期間がその範囲より
        // 先に伸びることがあるため、両方をカバーするaggregateDateRangeを使う
        guard let range = calendarTransactionService.aggregateDateRange(selectedDate: viewModel.selectedDate) else { return }
        let gridSnapshots = allDailySnapshots.filter { $0.date >= range.start && $0.date < range.end && $0.bookId == currentBookId }
        let bookMonthlySnapshots = allMonthlySnapshots.filter { $0.bookId == currentBookId }

        viewModel.rebuildMonthAggregateIfNeeded(dailySnapshots: gridSnapshots, allMonthlySnapshots: bookMonthlySnapshots)
    }

    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekSymbols.indices, id: \.self) { index in
                Text(weekSymbols[index])
                    .font(AppFonts.caption)
                    .foregroundStyle(weekTextColor(index: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: weekHeaderHeight)
                    .background(weekHeaderBackgroundColor)
                    .overlay(alignment: .trailing) { verticalLine }
                    .overlay(alignment: .bottom) { horizontalLine }
            }
        }
    }

    // 横方向の移動量が縦方向より大きい時だけ、横スワイプとして扱う
    // （日付セルのタップや縦方向の操作と誤反応しないようにするため）。
    private var isHorizontalDrag: Bool {
        abs(dragTranslation.width) > abs(dragTranslation.height)
    }

    private var liveDragOffset: CGFloat {
        isHorizontalDrag ? dragTranslation.width : 0
    }

    // 前月・当月・翌月の3ページを横に並べ、指の移動量にそのままoffset(x:)で追従させる。
    // 月の確定変更は指を離した時（handleDragEnded）だけ行い、日付グリッドの生成・集計の
    // 呼び出し方はrebuildAggregate/既存サービス呼び出しのまま変えていない。
    private var calendarPager: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            let pageHeight = geo.size.height
            let offsetX = isSettling ? settleOffset : liveDragOffset

            HStack(spacing: 0) {
                calendarGrid(days: previousDays, aggregate: previewAggregate(for: previousDate))
                    .frame(width: pageWidth, height: pageHeight, alignment: .top)
                calendarGrid(days: currentDays, aggregate: viewModel.monthAggregate)
                    .frame(width: pageWidth, height: pageHeight, alignment: .top)
                calendarGrid(days: nextDays, aggregate: previewAggregate(for: nextDate))
                    .frame(width: pageWidth, height: pageHeight, alignment: .top)
            }
            .offset(x: pageWidth > 0 ? -pageWidth + offsetX : 0)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragTranslation) { value, state, _ in
                        guard !isSettling else { return }
                        state = value.translation
                    }
                    .onEnded { value in
                        guard !isSettling, pageWidth > 0 else { return }
                        handleDragEnded(value: value, pageWidth: pageWidth)
                    }
            )
        }
        .frame(height: CGFloat(pageRowCount) * dayCellHeight)
        // 前後月の週数が表示中の月より多い場合に備え、はみ出した分を確実に切り取る
        .clipped()
    }

    private func handleDragEnded(value: DragGesture.Value, pageWidth: CGFloat) {
        let translation = value.translation.width
        let startOffset = translation

        guard abs(translation) > abs(value.translation.height) else {
            springBack(from: startOffset)
            return
        }

        let distanceThreshold = pageWidth * commitDistanceRatio
        // predictedEndTranslationは指の速度を反映した慣性後の予測移動量。実際の移動量が
        // 閾値未満でも、勢いよくフリックした場合はこちらで切り替えを検知する。
        let predicted = value.predictedEndTranslation.width
        let flingThresholdMet = abs(predicted) > pageWidth * (1 + commitFlingRatio)

        if translation < 0, abs(translation) > distanceThreshold || flingThresholdMet {
            commitSwipe(startOffset: startOffset, target: -pageWidth, resultDate: nextDate)
        } else if translation > 0, abs(translation) > distanceThreshold || flingThresholdMet {
            commitSwipe(startOffset: startOffset, target: pageWidth, resultDate: previousDate)
        } else {
            springBack(from: startOffset)
        }
    }

    // 月の確定変更は、既存のviewModel.selectedDateへの代入だけで行う
    // （CalendarViewModel/AccountingMonthCalculator側の処理は一切変更していない）。
    private func commitSwipe(startOffset: CGFloat, target: CGFloat, resultDate: Date) {
        settleOffset = startOffset
        isSettling = true
        withAnimation(.easeOut(duration: swipeAnimationDuration)) {
            settleOffset = target
        } completion: {
            settleOffset = 0
            isSettling = false
            viewModel.selectedDate = resultDate
        }
    }

    private func springBack(from startOffset: CGFloat) {
        settleOffset = startOffset
        isSettling = true
        withAnimation(.interactiveSpring()) {
            settleOffset = 0
        } completion: {
            isSettling = false
        }
    }

    private func calendarGrid(days: [CalendarMonthDay], aggregate: CalendarMonthAggregate) -> some View {
        VStack(spacing: 0) {
            let rowCount = days.count / 7

            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        if index < days.count {
                            let item = days[index]
                            CalendarMonthDayCellView(
                                item: item,
                                selectedDay: viewModel.selectedDay,
                                dailyTotal: adjustedDailyTotal(for: item, aggregate: aggregate),
                                onTap: { viewModel.selectDay(item.date) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var verticalLine: some View {
        Rectangle().fill(gridLineColor).frame(width: gridLineWidth)
    }

    private var horizontalLine: some View {
        Rectangle().fill(gridLineColor).frame(height: gridLineWidth)
    }

    // indexはグリッド上の列位置（週の開始曜日設定で変わる）だが、日曜/土曜の判定は
    // 実際の曜日値で行う（列0が必ず日曜とは限らないため）
    private func weekTextColor(index: Int) -> Color {
        let startWeekday = CalendarWeekStartSettings.clamped(weekStartWeekday)
        let weekday = (startWeekday - 1 + index) % 7 + 1
        if weekday == 1 { return sundayTextColor }
        if weekday == 7 { return saturdayTextColor }
        return weekdayTextColor
    }

    private func adjustedDailyTotal(for item: CalendarMonthDay, aggregate: CalendarMonthAggregate) -> CalendarDailyTotal {
        let cal = calendarTransactionService.calendar
        let raw = aggregate.dailyTotals[cal.startOfDay(for: item.date)]
            ?? CalendarDailyTotal(income: 0, expense: 0, balance: 0)

        guard showCarryover,
              let periodStart = aggregate.periodStartDate,
              cal.isDate(item.date, inSameDayAs: periodStart)
        else { return raw }

        // 繰越金はプラスなら収入、マイナスなら支出（絶対値）として振り分ける
        let co = aggregate.carryoverAmount
        let split = calendarTransactionService.splitCarryover(co)
        return CalendarDailyTotal(
            income: raw.income + split.income,
            expense: raw.expense + split.expense,
            balance: raw.balance + co
        )
    }
}
