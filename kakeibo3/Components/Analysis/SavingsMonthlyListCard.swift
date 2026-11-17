import SwiftUI

struct SavingsMonthlyListCard: View {
    let monthlySummaries: [MonthlySavingsSummary]

    private var reversedSummaries: [MonthlySavingsSummary] {
        Array(monthlySummaries.reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("月別一覧")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.8))

            VStack(spacing: 0) {
                ForEach(Array(reversedSummaries.enumerated()), id: \.offset) { index, item in
                    monthRow(item: item)
                    if index < reversedSummaries.count - 1 {
                        Divider()
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

    private func monthRow(item: MonthlySavingsSummary) -> some View {
        HStack(spacing: 0) {
            Text(item.fullMonthLabel)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatAnalysisAmount(item.savingsAmount))
                    .font(AppFonts.listAmount)
                    .foregroundStyle(savingsColor(item.savingsAmount))

                if let diff = item.monthOverMonthDiff {
                    Text("前月比 \(formatAnalysisDiff(diff))")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(analysisMomColor(diff: diff))
                } else {
                    Text("前月比 -")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.gray.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .opacity(item.hasData ? 1.0 : 0.38)
    }

    private func savingsColor(_ amount: Int) -> Color {
        if amount > 0 { return AppColors.main.opacity(0.85) }
        if amount < 0 { return Color(red: 0.85, green: 0.35, blue: 0.25) }
        return Color.black.opacity(0.55)
    }
}
