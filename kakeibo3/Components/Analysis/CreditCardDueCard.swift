import SwiftUI

struct CreditCardDueCard: View {
    let settings: [PaymentMethodSettingData]
    let allExpenses: [ExpenseData]
    let bankAccounts: [BankAccountData]
    /// 分析Viewで選択中の月（月初の Date を渡す）。この月内の引き落とし日を表示する。
    let selectedDate: Date

    @State private var showsCreditCardSetting = false

    private var creditCardSettings: [PaymentMethodSettingData] {
        settings.filter {
            $0.type == PaymentMethodType.creditCard.rawValue && $0.isActive
                && DowngradeLockService.isCreditCardUsable($0, bankAccounts: bankAccounts)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("クレジットカード引き落とし予定")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.8))

            if creditCardSettings.isEmpty {
                emptyState
            } else {
                ForEach(creditCardSettings) { setting in
                    creditCardRow(setting)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.line, lineWidth: 1)
        )
        .sheet(isPresented: $showsCreditCardSetting) {
            CreditCardSettingView()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Button("設定する") { showsCreditCardSetting = true }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.main)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    // MARK: - Credit card row

    private func creditCardRow(_ setting: PaymentMethodSettingData) -> some View {
        let info = dueInfo(for: setting)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ColorHexConverter.color(from: setting.colorHex))
                    .frame(width: 8, height: 8)
                Text(setting.methodName)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineLimit(1)
            }

            if let info = info {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatWithdrawalDate(info.withdrawalDate))
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.5))
                        Text(formatAnalysisAmount(info.amount))
                            .font(.system(size: 20, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.82))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("対象期間")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.4))
                        Text(formatBillingPeriod(info.billingStart, info.billingEnd))
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                }
            } else {
                Button("締め日・引き落とし日を設定する") { showsCreditCardSetting = true }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.main)
            }
        }
        .padding(12)
        .background(Color(red: 0.96, green: 0.97, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Due info calculation

    private struct DueInfo {
        let withdrawalDate: Date
        let billingStart: Date
        let billingEnd: Date
        let amount: Int
    }

    /// 選択月内の引き落とし日・対象期間・金額を計算する。
    /// 「今日から次の引き落とし日を探す」ではなく「選択月の withdrawalDay に固定」する。
    private func dueInfo(for setting: PaymentMethodSettingData) -> DueInfo? {
        guard let closingDay = setting.closingDay,
              let withdrawalDay = setting.withdrawalDay else { return nil }

        let cal = Calendar.current

        // 選択月内の引き落とし日（月末より大きい場合は月末日を使用）
        let daysInMonth = cal.range(of: .day, in: .month, for: selectedDate)?.count ?? 28
        var components = cal.dateComponents([.year, .month], from: selectedDate)
        components.day = min(withdrawalDay, daysInMonth)
        guard let withdrawalDate = cal.date(from: components) else { return nil }

        // 引き落とし対象期間（締め日サイクル）はカレンダー通りの日付で決まるため、
        // 休業日調整は表示用の引き落とし日にのみ適用する
        let period = billingPeriod(for: withdrawalDate, closingDay: closingDay, withdrawalDay: withdrawalDay, cal: cal)
        let displayWithdrawalDate = HolidayCalendarService.adjustedDate(
            for: withdrawalDate,
            adjustment: setting.resolvedHolidayAdjustment
        )

        let start = cal.startOfDay(for: period.start)
        let end: Date = {
            guard let d = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: period.end)) else { return period.end }
            return d
        }()

        let amount = allExpenses
            .filter { $0.paymentMethod == setting.methodName && $0.date >= start && $0.date < end }
            .reduce(0) { $0 + $1.amount }

        return DueInfo(withdrawalDate: displayWithdrawalDate, billingStart: period.start, billingEnd: period.end, amount: amount)
    }

    private func billingPeriod(for withdrawalDate: Date, closingDay: Int, withdrawalDay: Int, cal: Calendar) -> (start: Date, end: Date) {
        // billingEnd: same month as withdrawal if closingDay < withdrawalDay, else previous month
        let offset = (closingDay < withdrawalDay) ? 0 : -1
        guard
            let withdrawalMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: withdrawalDate)),
            let billingEndMonthStart = cal.date(byAdding: .month, value: offset, to: withdrawalMonthStart)
        else { return (withdrawalDate, withdrawalDate) }

        let daysInBillingEnd = cal.range(of: .day, in: .month, for: billingEndMonthStart)?.count ?? 28
        var billingEndComponents = cal.dateComponents([.year, .month], from: billingEndMonthStart)
        billingEndComponents.day = min(closingDay, daysInBillingEnd)
        let billingEnd = cal.date(from: billingEndComponents) ?? withdrawalDate

        // billingStart: day after previous closing
        guard let prevMonthStart = cal.date(byAdding: .month, value: -1, to: billingEndMonthStart) else {
            return (billingEnd, billingEnd)
        }
        let daysInPrev = cal.range(of: .day, in: .month, for: prevMonthStart)?.count ?? 28
        var prevEndComponents = cal.dateComponents([.year, .month], from: prevMonthStart)
        prevEndComponents.day = min(closingDay, daysInPrev)
        let prevEnd = cal.date(from: prevEndComponents) ?? billingEnd
        let billingStart = cal.date(byAdding: .day, value: 1, to: prevEnd) ?? billingEnd

        return (start: billingStart, end: billingEnd)
    }

    // MARK: - Formatters
    //
    // カード行ごと（ForEach内）に呼ばれるため、DateFormatterを毎回生成しないよう
    // static letでキャッシュする。

    private static let withdrawalDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日"
        fmt.locale = Locale(identifier: "ja_JP")
        return fmt
    }()

    private static let billingPeriodFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        fmt.locale = Locale(identifier: "ja_JP")
        return fmt
    }()

    private func formatWithdrawalDate(_ date: Date) -> String {
        "\(Self.withdrawalDateFormatter.string(from: date))引き落とし"
    }

    private func formatBillingPeriod(_ start: Date, _ end: Date) -> String {
        "\(Self.billingPeriodFormatter.string(from: start))〜\(Self.billingPeriodFormatter.string(from: end))"
    }
}
