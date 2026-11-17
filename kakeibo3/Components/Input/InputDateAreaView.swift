import SwiftUI
import Combine

// MARK: - 日付入力エリア

struct InputDateAreaView: View {
    @Binding var date: Date
    @Binding var isDatePickerPresented: Bool

    let layout: InputFormLayout

    var body: some View {
        HStack {
            Text("日付")
                .font(layout.rowTitleFont)
                .foregroundStyle(Color.black)

            Spacer()

            Button {
                isDatePickerPresented = true
            } label: {
                Text(formattedDate)
                    .font(layout.smallInputTextFont)
                    .foregroundStyle(.tint)
                    .frame(
                        width: layout.smallInputWidth,
                        height: layout.smallInputHeight
                    )
                    .background(layout.rowBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                            .stroke(layout.lineColor, lineWidth: 1)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, layout.rowHorizontalPadding)
        .frame(height: layout.normalRowHeight)
        .background(layout.rowBackgroundColor)
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
        }
    }

    private var datePickerSheet: some View {
        VStack(spacing: 20) {
            DatePicker(
                "日付を選択",
                selection: $date,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .padding()

            Button {
                isDatePickerPresented = false
            } label: {
                Text("決定")
                    .font(layout.dateDecisionButtonFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.dateDecisionButtonHeight)
                    .background(layout.mainColor)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: layout.dateDecisionButtonCornerRadius
                        )
                    )
            }
            .padding(.horizontal, layout.dateDecisionButtonHorizontalPadding)
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.medium])
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
