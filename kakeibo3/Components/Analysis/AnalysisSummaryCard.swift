import SwiftUI

struct AnalysisSummaryCard: View {
    let title: String
    let totalAmount: Int
    let itemCount: Int
    let hasPrevMonthData: Bool
    let monthOverMonthDiff: Int
    var comparisonLabel: String = "前月比"
    let dailyAverage: Int
    var filterButtonTitle: String? = nil
    var onFilterTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title)
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.65))
                Spacer()
                if let filterButtonTitle, let onFilterTap {
                    Button(action: onFilterTap) {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(filterButtonTitle)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.main)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppColors.main.opacity(0.1)))
                        .overlay(Capsule().stroke(AppColors.main.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(formatAnalysisAmount(totalAmount))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))

            HStack {
                if hasPrevMonthData {
                    Text("\(comparisonLabel) \(formatAnalysisDiff(monthOverMonthDiff))")
                        .monospacedDigit()
                } else {
                    Text("\(comparisonLabel) -")
                }
                Spacer()
                Text("\(itemCount)件")
            }
            .font(AppFonts.caption)
            .foregroundStyle(Color.black.opacity(0.45))

            Divider()
                .padding(.top, 2)

            HStack {
                Text("1日平均")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.4))
                Spacer()
                Text(formatAnalysisAmount(dailyAverage))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.58 * 0.85))
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
