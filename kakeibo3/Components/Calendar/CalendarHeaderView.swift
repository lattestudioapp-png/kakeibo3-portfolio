import SwiftUI
import Combine

struct CalendarHeaderView: View {
    @Binding var selectedDate: Date
    var onTitleTap: (() -> Void)? = nil
    /// 月の開始日設定（年月表示基準）を反映したラベルを表示したい場合に、呼び出し側から渡す。
    var titleOverride: String? = nil

    private let headerHorizontalPadding: CGFloat = 28

    var body: some View {
        MonthSelectorView(
            selectedDate: $selectedDate,
            titleFontSize: 25,
            arrowIconSize: 20,
            arrowButtonWidth: 36,
            arrowButtonHeight: 36,
            arrowButtonSpacing: 8,
            arrowButtonCornerRadius: 21,
            onTitleTap: onTitleTap,
            titleOverride: titleOverride
        )
        // frame(height: headerButtonSize) で MonthSelectorView を 38pt に正規化し、
        // ZStack(alignment:.top) + padding(.top, headerContentTopPadding) で
        // 中心 Y = headerControlCenterY = 81pt に揃える
        .frame(height: AppLayout.headerButtonSize, alignment: .center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.top, AppLayout.headerContentTopPadding)
    }
}
