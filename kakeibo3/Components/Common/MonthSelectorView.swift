import SwiftUI
import Combine

// MARK: - 月切り替えComponent

/**
 前月ボタン、年月表示、翌月ボタンを表示する共通Component。
 背景は持たない。
 */
struct MonthSelectorView: View {
    @Binding var selectedDate: Date

    let titleColor: Color
    let arrowColor: Color
    let arrowButtonBackgroundColor: Color

    let titleFontSize: CGFloat
    let titleFontWeight: Font.Weight
    let arrowIconSize: CGFloat
    let arrowIconWeight: Font.Weight
    let arrowButtonWidth: CGFloat
    let arrowButtonHeight: CGFloat
    let arrowButtonSpacing: CGFloat
    let arrowButtonCornerRadius: CGFloat

    let titleYOffset: CGFloat
    let arrowButtonYOffset: CGFloat
    let onTitleTap: (() -> Void)?
    /// 月の開始日設定（年月表示基準）を反映したラベルを表示したい場合に、呼び出し側から渡す。
    /// nilなら従来通りselectedDateをそのままフォーマットする。
    let titleOverride: String?

    private let calendar = Calendar.current

    init(
        selectedDate: Binding<Date>,
        titleColor: Color = .white,
        arrowColor: Color = .white,
        arrowButtonBackgroundColor: Color = Color.white.opacity(0.20),
        titleFontSize: CGFloat = 25,
        titleFontWeight: Font.Weight = .bold,
        arrowIconSize: CGFloat = 20,
        arrowIconWeight: Font.Weight = .bold,
        arrowButtonWidth: CGFloat = 36,
        arrowButtonHeight: CGFloat = 36,
        arrowButtonSpacing: CGFloat = 18,
        arrowButtonCornerRadius: CGFloat = 21,
        titleYOffset: CGFloat = 0,
        arrowButtonYOffset: CGFloat = 0,
        onTitleTap: (() -> Void)? = nil,
        titleOverride: String? = nil
    ) {
        self._selectedDate = selectedDate
        self.titleColor = titleColor
        self.arrowColor = arrowColor
        self.arrowButtonBackgroundColor = arrowButtonBackgroundColor
        self.titleFontSize = titleFontSize
        self.titleFontWeight = titleFontWeight
        self.arrowIconSize = arrowIconSize
        self.arrowIconWeight = arrowIconWeight
        self.arrowButtonWidth = arrowButtonWidth
        self.arrowButtonHeight = arrowButtonHeight
        self.arrowButtonSpacing = arrowButtonSpacing
        self.arrowButtonCornerRadius = arrowButtonCornerRadius
        self.titleYOffset = titleYOffset
        self.arrowButtonYOffset = arrowButtonYOffset
        self.onTitleTap = onTitleTap
        self.titleOverride = titleOverride
    }

    var body: some View {
        HStack(spacing: arrowButtonSpacing) {
            Button {
                moveMonth(value: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: arrowIconSize, weight: arrowIconWeight))
                    .foregroundStyle(arrowColor)
                    .frame(width: arrowButtonWidth, height: arrowButtonHeight)
                    .background(arrowButtonBackgroundColor)
                    .clipShape(
                        RoundedRectangle(cornerRadius: arrowButtonCornerRadius)
                    )
            }
            .offset(y: arrowButtonYOffset)

            Text(monthTitle)
                .font(.system(size: titleFontSize, weight: titleFontWeight))
                .foregroundStyle(titleColor)
                .offset(y: titleYOffset)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTitleTap?()
                }

            Button {
                moveMonth(value: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: arrowIconSize, weight: arrowIconWeight))
                    .foregroundStyle(arrowColor)
                    .frame(width: arrowButtonWidth, height: arrowButtonHeight)
                    .background(arrowButtonBackgroundColor)
                    .clipShape(
                        RoundedRectangle(cornerRadius: arrowButtonCornerRadius)
                    )
            }
            .offset(y: arrowButtonYOffset)
        }
    }

    private var monthTitle: String {
        if let titleOverride { return titleOverride }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: selectedDate)
    }

    // selectedDateの暦月をそのままanchorとして使うと、月の開始日設定次第では
    // selectedDateが実際にはその1つ前の会計期間に属してしまうことがある
    // （例：開始日=10日でselectedDate=7/9の場合、7/9は6/10〜7/9の会計期間に属する）。
    // そのため、まずAccountingMonthCalculator.range(containing:)で「selectedDateが実際に
    // 属する会計期間」のanchorを求めてから、そのanchorを基準に±1ヶ月進める。
    // 移動後は新しいanchorの会計期間の開始日にジャンプする（暦月の「日」を保持する意味が
    // 会計期間ベースでは薄いため、常にその期間の最初の日を指す方が一貫性がある）。
    private func moveMonth(value: Int) {
        guard let currentRange = AccountingMonthCalculator.range(containing: selectedDate, calendar: calendar) else { return }
        let nextAnchor = AccountingMonthCalculator.adjacentAnchor(
            year: currentRange.anchorYear, month: currentRange.anchorMonth, offset: value
        )
        guard let nextRange = AccountingMonthCalculator.range(anchorYear: nextAnchor.year, anchorMonth: nextAnchor.month, calendar: calendar)
        else { return }

        selectedDate = nextRange.actualStartDate
    }
}
