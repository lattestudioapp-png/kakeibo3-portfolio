import Foundation

// MARK: - カレンダー収支Service

/**
 カレンダー表示で必要な日付生成・日別集計・月別集計を担当するService。
 既存の CalendarTransactionCalculator を内部で使い、Viewから計算処理を分離する。
 */
struct CalendarTransactionService {
    private let calculator = CalendarTransactionCalculator()

    var calendar: Calendar {
        calculator.calendar
    }

    func makeCalendarDays(selectedDate: Date) -> [CalendarMonthDay] {
        calculator.makeCalendarDays(selectedDate: selectedDate)
    }

    func dailyTotal(
        date: Date,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) -> CalendarDailyTotal {
        calculator.dailyTotal(
            date: date,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList
        )
    }

    func monthlyTotal(
        selectedDate: Date,
        incomeDataList: [IncomeData],
        expenseDataList: [ExpenseData]
    ) -> CalendarMonthlyTotal {
        calculator.monthlyTotal(
            selectedDate: selectedDate,
            incomeDataList: incomeDataList,
            expenseDataList: expenseDataList
        )
    }

    func dayNumber(_ date: Date) -> String {
        calculator.dayNumber(date)
    }

    func formatYen(_ value: Int) -> String {
        calculator.formatYen(value)
    }

    func monthAggregate(
        selectedDate: Date,
        dailySnapshots: [DailySnapshot],
        allMonthlySnapshots: [MonthlySnapshot]
    ) -> CalendarMonthAggregate {
        calculator.monthAggregate(
            selectedDate: selectedDate,
            dailySnapshots: dailySnapshots,
            allMonthlySnapshots: allMonthlySnapshots
        )
    }

    func gridDateRange(selectedDate: Date) -> (start: Date, end: Date)? {
        calculator.gridDateRange(selectedDate: selectedDate)
    }

    func aggregateDateRange(selectedDate: Date) -> (start: Date, end: Date)? {
        calculator.aggregateDateRange(selectedDate: selectedDate)
    }

    func resolveCarryover(year: Int, month: Int, allMonthlySnapshots: [MonthlySnapshot]) -> Int {
        calculator.resolveCarryover(year: year, month: month, allMonthlySnapshots: allMonthlySnapshots)
    }

    func splitCarryover(_ amount: Int) -> (income: Int, expense: Int) {
        calculator.splitCarryover(amount)
    }
}
