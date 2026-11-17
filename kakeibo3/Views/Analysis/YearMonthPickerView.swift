import SwiftUI

struct YearMonthPickerView: View {
    @Binding var year: Int
    @Binding var month: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let years = Array(2000...2100)
    private let months = Array(1...12)

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Button("キャンセル") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.5))

                Spacer()

                Text("年月を選択")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))

                Spacer()

                Button("確定") {
                    onConfirm()
                    dismiss()
                }
                .font(AppFonts.button)
                .foregroundStyle(AppColors.main)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            Spacer(minLength: 8)

            // ピッカー
            HStack(spacing: 24) {
                Picker("年", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text("\(y)年").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("月", selection: $month) {
                    ForEach(months, id: \.self) { m in
                        Text("\(m)月").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: 100)
            }
            .frame(height: 180)
            .clipped()

            Spacer(minLength: 16)
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}
