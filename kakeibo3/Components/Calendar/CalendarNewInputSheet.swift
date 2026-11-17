import SwiftUI
import Combine

struct CalendarNewInputSheet: View {
    let targetDate: Date
    let onCreateExpense: () -> Void
    let onCreateIncome: () -> Void

    private let backgroundColor = Color.white
    private let subTextColor = Color.gray
    private let incomeButtonColor = AppColors.incomeColor
    private let expenseButtonColor = AppColors.expenseColor
    private let sheetHorizontalPadding: CGFloat = 28
    private let sheetTopPadding: CGFloat = 24
    private let itemSpacing: CGFloat = 16
    private let createButtonHeight: CGFloat = 48
    private let createButtonCornerRadius: CGFloat = 14
    private let titleFontSize: CGFloat = 22
    private let titleFontWeight: Font.Weight = .bold

    var body: some View {
        VStack(spacing: itemSpacing) {
            Text("新規入力")
                .font(.system(size: titleFontSize, weight: titleFontWeight))
                .foregroundStyle(.primary)

            Text(formattedDate)
                .font(AppFonts.body)
                .foregroundStyle(subTextColor)

            Button { onCreateExpense() } label: {
                Text("支出を作成")
                    .font(AppFonts.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: createButtonHeight)
                    .background(expenseButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: createButtonCornerRadius))
            }

            Button { onCreateIncome() } label: {
                Text("収入を作成")
                    .font(AppFonts.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: createButtonHeight)
                    .background(incomeButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: createButtonCornerRadius))
            }
        }
        .padding(.horizontal, sheetHorizontalPadding)
        .padding(.top, sheetTopPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: targetDate)
    }
}
