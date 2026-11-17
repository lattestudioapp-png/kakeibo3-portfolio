import SwiftUI
import Charts

struct AnalysisDonutChartCard: View {
    let title: String
    let items: [AnalysisCategorySummary]
    @Binding var selectedAngle: Double?

    private var selectedItem: AnalysisCategorySummary? {
        guard let angle = selectedAngle else { return nil }
        var cumulative = 0.0
        for item in items {
            cumulative += item.percentage
            if angle <= cumulative { return item }
        }
        return items.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.8))

            if items.isEmpty {
                Text("データがありません")
                    .font(AppFonts.body)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                HStack(spacing: 20) {
                    ZStack {
                        Chart(items) { item in
                            SectorMark(
                                angle: .value("割合", item.percentage),
                                innerRadius: .ratio(0.52),
                                angularInset: 1.5
                            )
                            .foregroundStyle(item.color)
                            .opacity(
                                selectedItem == nil || selectedItem?.id == item.id
                                ? 1.0 : 0.4
                            )
                        }
                        .chartAngleSelection(value: $selectedAngle)
                        .frame(width: 112, height: 112)

                        Circle()
                            .fill(Color.clear)
                            .frame(width: 58, height: 58)
                            .contentShape(Circle())
                            .onTapGesture { selectedAngle = nil }

                        if let selected = selectedItem {
                            donutTooltip(selected)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            legendRow(item: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .onTapGesture {
            selectedAngle = nil
        }
    }

    private func donutTooltip(_ item: AnalysisCategorySummary) -> some View {
        VStack(spacing: 2) {
            Text(item.categoryName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
                .lineLimit(1)
            Text(formatAnalysisAmount(item.totalAmount))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))
            Text("\(Int(item.percentage))%")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        )
    }

    private func legendRow(item: AnalysisCategorySummary) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.color)
                .frame(width: 10, height: 10)

            Text(item.categoryName)
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.7))
                .lineLimit(1)

            Spacer()

            Text("\(Int(item.percentage))%")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.55))
        }
    }
}
