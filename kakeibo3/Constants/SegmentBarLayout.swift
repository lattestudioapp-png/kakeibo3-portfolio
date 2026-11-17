import SwiftUI

struct SegmentBarLayout {
    let width: CGFloat
    let height: CGFloat
    let selectedHeight: CGFloat
    let innerPadding: CGFloat
    let topPadding: CGFloat
    let font: Font
    let backgroundColor: Color
    let selectedBackgroundColor: Color
    let textColor: Color

    func selectedWidth(itemCount: Int) -> CGFloat {
        (width - innerPadding * 2) / CGFloat(itemCount)
    }

    static var standard: SegmentBarLayout {
        SegmentBarLayout(
            width: 330,
            height: 40,
            selectedHeight: 32,
            innerPadding: 4,
            topPadding: 61,  // AppLayout.headerControlCenterY - height / 2 = 81 - 20
            font: .system(size: 16, weight: .bold),
            backgroundColor: Color.white.opacity(0.92),
            selectedBackgroundColor: Color.black.opacity(0.08),
            textColor: AppColors.main
        )
    }
}
