import SwiftUI
import Combine

struct CalendarMonthDayCellView: View {
    let item: CalendarMonthDay
    let selectedDay: Date
    let dailyTotal: CalendarDailyTotal
    let onTap: () -> Void

    private let calculator = CalendarTransactionCalculator()
    private let cellBackgroundColor = Color.white
    private let gridLineColor = Color.gray.opacity(0.35)
    private let weekdayTextColor = Color.gray
    private let sundayTextColor = Color(red: 0.70, green: 0.32, blue: 0.18)
    private let holidayTextColor = Color(red: 0.70, green: 0.32, blue: 0.18)
    private let saturdayTextColor = Color.indigo.opacity(0.75)
    private let outsideMonthTextColor = Color.gray.opacity(0.35)
    private let selectedDayBackgroundColor = AppColors.main
    private let selectedDayTextColor = Color.white
    private let dailyIncomeAmountColor = AppColors.incomeColor
    private let dailyExpenseAmountColor = AppColors.expenseColor
    private let dayCellHeight: CGFloat = 36
    private let gridLineWidth: CGFloat = 0.7
    private let dayFontSize: CGFloat = 12
    private let dayFontWeight: Font.Weight = .regular
    private let dayNumberLeadingPadding: CGFloat = 4
    private let dayNumberTopPadding: CGFloat = 2
    private let dayNumberXOffset: CGFloat = 0
    private let dayNumberYOffset: CGFloat = 0
    private let selectedDayBoxWidth: CGFloat = 17
    private let selectedDayBoxHeight: CGFloat = 15
    private let selectedDayBoxCornerRadius: CGFloat = 0
    private let selectedDayBoxLeadingPadding: CGFloat = 0
    private let selectedDayBoxTopPadding: CGFloat = 0
    private let selectedDayBoxXOffset: CGFloat = 0
    private let selectedDayBoxYOffset: CGFloat = 0
    private let selectedDayTextXOffset: CGFloat = 0
    private let selectedDayTextYOffset: CGFloat = 0
    private let dailyAmountFontSize: CGFloat = 8
    private let dailyAmountFontWeight: Font.Weight = .regular
    private let dailyAmountTrailingPadding: CGFloat = 3
    private let dailyAmountBottomPadding: CGFloat = 2
    private let dailyAmountVerticalSpacing: CGFloat = 0
    private let dailyAmountMinimumScaleFactor: CGFloat = 0.55

    var body: some View {
        Button { onTap() } label: {
            ZStack(alignment: .topLeading) {
                cellBackgroundColor
                dayNumberView
                dailyAmountView
            }
            .frame(maxWidth: .infinity)
            .frame(height: dayCellHeight)
            .overlay(alignment: .trailing) { verticalLine }
            .overlay(alignment: .bottom) { horizontalLine }
        }
        .buttonStyle(.plain)
    }

    private var dayNumberView: some View {
        let selected = calculator.calendar.isDate(item.date, inSameDayAs: selectedDay)
        return Group {
            if selected { selectedDayNumberView } else { normalDayNumberView }
        }
    }

    private var normalDayNumberView: some View {
        Text(calculator.dayNumber(item.date))
            .font(.system(size: dayFontSize, weight: dayFontWeight))
            .foregroundStyle(dayTextColor)
            .padding(.leading, dayNumberLeadingPadding)
            .padding(.top, dayNumberTopPadding)
            .offset(x: dayNumberXOffset, y: dayNumberYOffset)
    }

    private var selectedDayNumberView: some View {
        Text(calculator.dayNumber(item.date))
            .font(.system(size: dayFontSize, weight: dayFontWeight))
            .foregroundStyle(selectedDayTextColor)
            .offset(x: selectedDayTextXOffset, y: selectedDayTextYOffset)
            .frame(width: selectedDayBoxWidth, height: selectedDayBoxHeight)
            .background(selectedDayBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: selectedDayBoxCornerRadius))
            .padding(.leading, selectedDayBoxLeadingPadding)
            .padding(.top, selectedDayBoxTopPadding)
            .offset(x: selectedDayBoxXOffset, y: selectedDayBoxYOffset)
    }

    private var dailyAmountView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: dailyAmountVerticalSpacing) {
                    if dailyTotal.income > 0 {
                        Text(calculator.formatYen(dailyTotal.income))
                            .font(.system(size: dailyAmountFontSize, weight: dailyAmountFontWeight))
                            .monospacedDigit()
                            .foregroundStyle(dailyIncomeAmountColor)
                            .lineLimit(1)
                            .minimumScaleFactor(dailyAmountMinimumScaleFactor)
                    }

                    if dailyTotal.expense > 0 {
                        Text(calculator.formatYen(dailyTotal.expense))
                            .font(.system(size: dailyAmountFontSize, weight: dailyAmountFontWeight))
                            .monospacedDigit()
                            .foregroundStyle(dailyExpenseAmountColor)
                            .lineLimit(1)
                            .minimumScaleFactor(dailyAmountMinimumScaleFactor)
                    }
                }
                .padding(.trailing, dailyAmountTrailingPadding)
                .padding(.bottom, dailyAmountBottomPadding)
            }
        }
    }

    private var verticalLine: some View {
        Rectangle().fill(gridLineColor).frame(width: gridLineWidth)
    }

    private var horizontalLine: some View {
        Rectangle().fill(gridLineColor).frame(height: gridLineWidth)
    }

    private var dayTextColor: Color {
        if !item.isCurrentMonth { return outsideMonthTextColor }
        // 優先順位：祝日 > 日曜日 > 土曜日 > 平日（祝日が土曜と重なる場合も祝日色を優先）
        if HolidayCalendarService.isJapaneseHoliday(item.date) { return holidayTextColor }
        // calendar.component(.weekday:)は絶対値（日=1...土=7）で、週の開始曜日設定の
        // 影響を受けないため、列位置ではなくこちらで日曜/土曜を判定する
        let weekday = calculator.calendar.component(.weekday, from: item.date)
        if weekday == 1 { return sundayTextColor }
        if weekday == 7 { return saturdayTextColor }
        return weekdayTextColor
    }
}
