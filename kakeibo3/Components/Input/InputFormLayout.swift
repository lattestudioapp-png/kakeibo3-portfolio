import SwiftUI
import Combine

// MARK: - 入力フォーム共通レイアウト設定

struct InputFormLayout {
    var mainColor: Color { AppColors.main }
    var backgroundColor: Color { AppColors.background }
    let lineColor = AppColors.line
    let rowBackgroundColor = Color.white
    let memoBackgroundColor = Color.white
    let unselectedCategoryTextColor = Color.gray
    let memoTextColor = Color.black.opacity(0.65)
    let secondaryTextColor = Color.secondary
    let typeSwitchBackgroundColor = Color.white
    let selectedSwitchBackgroundColor = Color.gray.opacity(0.22)
    let thinBorderColor = Color.gray.opacity(0.30)

    let smallInputHeight: CGFloat = 30
    let normalRowHeight: CGFloat = 45
    let memoRowHeight: CGFloat = 45
    let amountRowHeight: CGFloat = 62
    let categoryHeaderHeight: CGFloat = 46
    let categoryButtonHeight: CGFloat = 50
    let saveButtonHeight: CGFloat = 54
    let dateDecisionButtonHeight: CGFloat = 50

    let smallInputWidth: CGFloat = 120
    let amountInputMaxWidth: CGFloat = 180

    // 支出/収入バーの位置
    let typeSwitchTopPadding: CGFloat = SegmentBarLayout.standard.topPadding

    // 入力欄全体の開始位置
    // マイナスを弱くすると下がる。例: -50
    // マイナスを強くすると上がる。例: -70
    let dateAndAmountTopOffset: CGFloat = 0

    let categoryAndMemoTopPadding: CGFloat = 0
    let categoryGridTopPadding: CGFloat = 4
    let categoryGridBottomPadding: CGFloat = 18
    let memoTextFieldYOffset: CGFloat = 0
    let memoAreaYOffset: CGFloat = 0
    let saveButtonTopPadding: CGFloat = 8
    let saveButtonBottomPadding: CGFloat = 8
    let bottomNavigationSpacerHeight: CGFloat = AppLayout.bottomNavigationHeight

    let rowHorizontalPadding: CGFloat = 28
    let memoHorizontalPadding: CGFloat = 28
    let categoryHorizontalPadding: CGFloat = 28
    let saveButtonHorizontalPadding: CGFloat = 42
    let dateDecisionButtonHorizontalPadding: CGFloat = 16

    let smallInputCornerRadius: CGFloat = 10
    let categoryButtonCornerRadius: CGFloat = 14
    let saveButtonCornerRadius: CGFloat = 16
    let dateDecisionButtonCornerRadius: CGFloat = 14

    let rowTitleFont: Font = .headline
    let memoTitleFont: Font = .headline
    let memoTextFieldFont: Font = .body

    let smallInputTextFont: Font = .headline

    let amountFontSize: CGFloat = 30
    let amountFontWeight: Font.Weight = .bold
    let categoryButtonFont: Font = .subheadline.weight(.semibold)
    let categoryEditButtonFont: Font = .subheadline.bold()
    let saveButtonFont: Font = .title3.bold()
    let typeSwitchFont: Font = .headline.bold()
    let dateDecisionButtonFont: Font = .headline

    // 電卓キーボードの下部余白調整（正の値で下にずらす・負の値で上にずらす）
    let calculatorKeyboardBottomPadding: CGFloat = 95

    let memoPlaceholder = "メモ"
    let showsMemoTopBorder = true
    let showsMemoBottomBorder = true

    let categoryColumnCount: Int = 4
    let categoryGridSpacing: CGFloat = 10
    let categoryMinimumScaleFactor: CGFloat = 0.7
    let selectedCategoryBackgroundOpacity: CGFloat = 0.12
    let selectedCategoryLineWidth: CGFloat = 2
    let unselectedCategoryLineWidth: CGFloat = 1

    var categoryColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: categoryGridSpacing),
            count: categoryColumnCount
        )
    }
}
