import SwiftUI

// MARK: - 予算概要カード（今月の予算 + 予算進捗を1枚にまとめたもの）

struct BudgetOverviewCard: View {
    let summary: BudgetMonthSummary

    private let overColor = Color(red: 0.85, green: 0.35, blue: 0.25)
    private var barColor: Color { summary.isOverBudget ? overColor : AppColors.main }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 上段：今月の予算
            HStack {
                Text("今月の予算")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.65))
                Spacer()
                if summary.isBudgetSet {
                    Text(formatAnalysisAmount(summary.totalBudgetAmount))
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))
                }
            }

            if summary.isBudgetSet {
                Divider()

                // 中段：予算進捗 + 消化率
                HStack {
                    Text("予算進捗")
                        .font(AppFonts.sectionTitle)
                        .foregroundStyle(Color.black.opacity(0.65))
                    Spacer()
                    if let rate = summary.usageRate {
                        HStack(spacing: 4) {
                            Text("消化率")
                                .font(AppFonts.caption)
                                .foregroundStyle(Color.black.opacity(0.45))
                            Text("\(rate)%")
                                .font(AppFonts.caption)
                                .monospacedDigit()
                                .foregroundStyle(barColor.opacity(0.85))
                        }
                    }
                }

                // 進捗バー
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.1))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor)
                            .frame(
                                width: max(0, geo.size.width * summary.usageRatio),
                                height: 18
                            )
                    }
                }
                .frame(height: 18)

                // 下段：使用済み / 残り
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("使用済み")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                        Text(formatAnalysisAmount(summary.totalUsedAmount))
                            .font(.system(size: 15, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(barColor)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(summary.isOverBudget ? "超過" : "残り")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                        Text(formatAnalysisAmount(abs(summary.remainingAmount)))
                            .font(.system(size: 15, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(
                                summary.isOverBudget ? overColor : Color.black.opacity(0.65)
                            )
                    }
                }
            } else {
                Text("予算が設定されていません")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
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
    }
}
