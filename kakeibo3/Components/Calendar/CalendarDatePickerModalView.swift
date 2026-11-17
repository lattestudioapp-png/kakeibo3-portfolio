import SwiftUI

// MARK: - カレンダー日付選択モーダル（ホイール型）

struct CalendarDatePickerModalView: View {
    @Binding var selectedDate: Date
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.colorScheme, .light)
            .frame(height: 216)
            .clipped()
            .padding(.top, 12)
            .padding(.horizontal, 16)

            Divider()

            HStack(spacing: 0) {
                Button(action: onCancel) {
                    Text("キャンセル")
                        .font(AppFonts.button)
                        .foregroundStyle(AppColors.main)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 56)

                Button(action: onConfirm) {
                    Text("決定")
                        .font(AppFonts.button)
                        .foregroundStyle(AppColors.main)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.colorScheme, .light)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: 340)
        .padding(.horizontal, 32)
    }
}
