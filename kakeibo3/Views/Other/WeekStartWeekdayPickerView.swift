import SwiftUI

// MARK: - カレンダーの開始曜日ピッカー

struct WeekStartWeekdayPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CalendarWeekStartSettings.storageKey)
    private var weekStartWeekday: Int = CalendarWeekStartSettings.defaultValue

    private let weekdaySymbols = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(CalendarWeekStartSettings.validRange, id: \.self) { weekday in
                    Button {
                        weekStartWeekday = weekday
                        dismiss()
                    } label: {
                        HStack {
                            Text(weekdaySymbols[weekday - 1])
                                .foregroundStyle(.primary)
                            Spacer()
                            if weekday == weekStartWeekday {
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
            .navigationTitle("カレンダーの開始曜日")
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
