import SwiftUI

struct BudgetCategoryListCard: View {
    let summary: BudgetMonthSummary
    let onSettingTap: () -> Void

    private let overColor = Color(red: 0.85, green: 0.35, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("カテゴリー別予算")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Button(action: onSettingTap) {
                    Text("設定")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppColors.main.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSettingTap)

            if summary.categorySummaries.isEmpty {
                Text("予算が設定されていません")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.line, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(summary.categorySummaries.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        categoryRow(item: item)
                        if index < summary.categorySummaries.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.line, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func categoryRow(item: BudgetCategorySummary) -> some View {
        let barColor = item.isOverBudget ? overColor : AppColors.main
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.categoryName)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                if let rate = item.usageRate {
                    Text("\(rate)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(barColor.opacity(0.85))
                }
            }

            HStack(spacing: 4) {
                Text(formatAnalysisAmount(item.usedAmount))
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(barColor)
                Text("/")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.3))
                Text(item.budgetAmount.map { formatAnalysisAmount($0) } ?? "-")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.45))
                Spacer()
                if let remaining = item.remainingAmount {
                    let label = item.isOverBudget
                        ? "超過 \(formatAnalysisAmount(-remaining))"
                        : "残り \(formatAnalysisAmount(remaining))"
                    Text(label)
                        .font(AppFonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(item.isOverBudget ? overColor : Color.black.opacity(0.45))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * item.usageRatio), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func unsetCategoryRow(item: BudgetCategorySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.categoryName)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                Text("-")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.gray.opacity(0.5))
            }

            HStack(spacing: 4) {
                Text(formatAnalysisAmount(item.usedAmount))
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.6))
                Text("/")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.3))
                Text("未設定")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.35))
            }

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
