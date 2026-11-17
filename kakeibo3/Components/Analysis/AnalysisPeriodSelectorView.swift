import SwiftUI

struct AnalysisPeriodSelectorView: View {
    @Binding var selectedPeriod: AnalysisPeriodType
    var onCustomTap: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalysisPeriodType.allCases, id: \.self) { period in
                    Button {
                        if period == .custom {
                            onCustomTap?()
                        } else {
                            selectedPeriod = period
                        }
                    } label: {
                        Text(period.rawValue)
                            .font(.system(
                                size: 13,
                                weight: selectedPeriod == period ? .semibold : .regular
                            ))
                            .foregroundStyle(
                                selectedPeriod == period
                                    ? AppColors.main
                                    : Color.gray.opacity(0.55)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedPeriod == period
                                          ? AppColors.main.opacity(0.1)
                                          : Color.gray.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
