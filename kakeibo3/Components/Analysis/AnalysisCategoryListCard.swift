import SwiftUI

struct AnalysisCategoryListCard: View {
    let title: String
    let items: [AnalysisCategorySummary]
    @Binding var showsMonthOverMonth: Bool
    let emptyMessage: String
    var comparisonLabel: String = "前月比"
    var mode: AnalysisDetailMode = .expenseCategory
    var dateRange: AnalysisDateRange

    @State private var selectedItem: AnalysisCategorySummary?

    init(
        title: String = "カテゴリー別",
        items: [AnalysisCategorySummary],
        showsMonthOverMonth: Binding<Bool>,
        comparisonLabel: String = "前月比",
        emptyMessage: String,
        mode: AnalysisDetailMode = .expenseCategory,
        dateRange: AnalysisDateRange
    ) {
        self.title = title
        self.items = items
        self._showsMonthOverMonth = showsMonthOverMonth
        self.comparisonLabel = comparisonLabel
        self.emptyMessage = emptyMessage
        self.mode = mode
        self.dateRange = dateRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Button(action: { showsMonthOverMonth.toggle() }) {
                    Text(showsMonthOverMonth ? "\(comparisonLabel) ON" : "\(comparisonLabel) OFF")
                        .font(AppFonts.caption)
                        .foregroundStyle(showsMonthOverMonth ? Color.white : Color.gray.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(showsMonthOverMonth
                                      ? AppColors.main.opacity(0.85)
                                      : Color.gray.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            if items.isEmpty {
                Text(emptyMessage)
                    .font(AppFonts.body)
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
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button {
                            selectedItem = item
                        } label: {
                            categoryRow(item: item)
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
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
        .sheet(item: $selectedItem) { item in
            CategoryAnalysisDetailView(
                item: item,
                mode: mode,
                dateRange: dateRange,
                comparisonLabel: comparisonLabel
            )
        }
    }

    private func categoryRow(item: AnalysisCategorySummary) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 10, height: 10)

            Text(item.categoryName)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatAnalysisAmount(item.totalAmount))
                    .font(AppFonts.listAmount)
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.65))
                    .lineLimit(1)

                if showsMonthOverMonth {
                    if let diff = item.monthOverMonthDiff {
                        Text("\(comparisonLabel) \(formatAnalysisDiff(diff))")
                            .font(.system(size: 10, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(analysisMomColor(diff: diff))
                            .lineLimit(1)
                    } else {
                        Text("\(comparisonLabel) -")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Text("\(Int(item.percentage))%")
                .font(AppFonts.caption)
                .foregroundStyle(Color.gray.opacity(0.65))
                .frame(width: 38, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.45))
                .frame(width: 14)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: showsMonthOverMonth ? 58 : 48)
        .contentShape(Rectangle())
    }
}
