import SwiftUI

struct PaymentSummaryCard: View {
    let title: String
    let totalAmount: Int
    let methodCount: Int
    let topMethodName: String?
    let hasPrevData: Bool
    let periodDiff: Int
    let comparisonLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.65))

            Text(formatAnalysisAmount(totalAmount))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))

            HStack {
                if hasPrevData {
                    Text("\(comparisonLabel) \(formatAnalysisDiff(periodDiff))")
                        .monospacedDigit()
                        .foregroundStyle(analysisMomColor(diff: periodDiff))
                } else {
                    Text("\(comparisonLabel) -")
                }
                Spacer()
                Text("利用方法 \(methodCount)種類")
            }
            .font(AppFonts.caption)
            .foregroundStyle(Color.black.opacity(0.45))

            Divider()
                .padding(.top, 2)

            HStack {
                Text("最多")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.4))
                Spacer()
                Text(topMethodName ?? "-")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.58))
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
