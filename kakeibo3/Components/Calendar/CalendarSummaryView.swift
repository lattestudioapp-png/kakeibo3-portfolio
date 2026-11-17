import SwiftUI
import Combine

// MARK: - カレンダー月合計表示

/**
 カレンダー下に表示する月合計エリア。

 表示する内容:
 - 収入
 - 支出
 - 合計

 このViewでは、CalendarViewModel が持つ集計済みの月合計（monthAggregate）を読むだけで、
 このView自身では収入・支出データの取得・集計は行わない。

 見た目の数値はこのView内で管理している。
 */
struct CalendarSummaryView: View {

    // MARK: - 外部から受け取る値

    @ObservedObject var viewModel: CalendarViewModel
    var onTapIncome: (() -> Void)? = nil
    var onTapExpense: (() -> Void)? = nil
    var onTapBalance: (() -> Void)? = nil

    // MARK: - 設定

    @AppStorage("showPreviousMonthCarryover") private var showCarryover = false

    // MARK: - 計算担当

    /**
     月合計の計算と、金額表示の整形を担当する。
     */
    private let calendarService = CalendarTransactionService()

    // MARK: - 色設定

    /**
     月合計エリアの背景色。
     */
    private let backgroundColor = Color.white

    /**
     「収入」「支出」「合計」のタイトル文字色。
     */
    private let titleColor = Color.black.opacity(0.65)

    /**
     収入金額の文字色。
     */
    private let incomeColor = AppColors.incomeColor

    /**
     支出金額の文字色。
     */
    private let expenseColor = AppColors.expenseColor

    /**
     合計金額の文字色。
     プラスなら収入と同じ青、マイナスなら支出と同じ赤、0ならグレー。
     */
    private func balanceColor(for amount: Int) -> Color {
        if amount > 0 { return incomeColor }
        if amount < 0 { return expenseColor }
        return Color.black.opacity(0.70)
    }

    /**
     上下の区切り線の色。
     */
    private let borderColor = Color.gray.opacity(0.25)

    // MARK: - サイズ設定

    /**
     月合計エリア全体の高さ。
     */
    private let areaHeight: CGFloat = 52

    /**
     月合計エリアの左右余白。
     */
    private let horizontalPadding: CGFloat = 20

    /**
     上下の区切り線の太さ。
     */
    private let borderHeight: CGFloat = 0.7

    // MARK: - フォント設定

    /**
     金額文字のサイズ。
     */
    private let amountFontSize: CGFloat = 13

    // MARK: - body

    var body: some View {
        let total = viewModel.monthAggregate.monthlyTotal
        let carryover = showCarryover ? viewModel.monthAggregate.carryoverAmount : 0
        // 繰越金はプラスなら収入、マイナスなら支出（絶対値）として振り分ける
        let carryoverSplit = calendarService.splitCarryover(carryover)
        let displayIncome = total.income + carryoverSplit.income
        let displayExpense = total.expense + carryoverSplit.expense

        HStack(spacing: 0) {
            summaryItem(
                title: "収入",
                amount: calendarService.formatYen(displayIncome),
                color: incomeColor,
                onTap: onTapIncome
            )

            summaryItem(
                title: "支出",
                amount: calendarService.formatYen(displayExpense),
                color: expenseColor,
                onTap: onTapExpense
            )

            summaryItem(
                title: "合計",
                amount: calendarService.formatYen(displayIncome - displayExpense),
                color: balanceColor(for: displayIncome - displayExpense),
                onTap: onTapBalance
            )
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: areaHeight)
        .background(backgroundColor)
        .overlay(alignment: .top) {
            borderLine
        }
        .overlay(alignment: .bottom) {
            borderLine
        }
    }

    // MARK: - 合計1項目

    private func summaryItem(
        title: String,
        amount: String,
        color: Color,
        onTap: (() -> Void)?
    ) -> some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(AppFonts.caption)
                    .foregroundStyle(titleColor)

                Text(amount)
                    .font(.system(size: amountFontSize, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    // MARK: - 区切り線

    /**
     月合計エリアの上端・下端に表示する薄い線。
     */
    private var borderLine: some View {
        Rectangle()
            .fill(borderColor)
            .frame(height: borderHeight)
    }
}
