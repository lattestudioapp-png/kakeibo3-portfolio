import SwiftUI

// MARK: - 開始日が土日祝の場合の調整ピッカー

struct WeekendHolidayAdjustmentPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(WeekendHolidayAdjustment.storageKey)
    private var storedAdjustment: String = WeekendHolidayAdjustment.defaultValue.rawValue

    var body: some View {
        NavigationStack {
            List {
                ForEach(WeekendHolidayAdjustment.allCases, id: \.rawValue) { option in
                    Button {
                        storedAdjustment = option.rawValue
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option.rawValue == storedAdjustment {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.main)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("開始日が土日祝の場合")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(AppColors.main)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
