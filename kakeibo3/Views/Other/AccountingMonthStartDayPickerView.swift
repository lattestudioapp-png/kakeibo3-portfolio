import SwiftUI

// MARK: - 月の開始日ピッカー（1〜31日）

struct AccountingMonthStartDayPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AccountingMonthSettings.startDayStorageKey)
    private var startDay: Int = AccountingMonthSettings.startDayDefaultValue

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountingMonthSettings.minDay...AccountingMonthSettings.maxDay, id: \.self) { day in
                    Button {
                        startDay = day
                        dismiss()
                    } label: {
                        HStack {
                            Text("\(day)日")
                                .foregroundStyle(.primary)
                            Spacer()
                            if day == startDay {
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
            .navigationTitle("月の開始日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(AppColors.main)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
