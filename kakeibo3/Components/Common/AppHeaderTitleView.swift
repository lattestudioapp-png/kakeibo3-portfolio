import SwiftUI

struct AppHeaderTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(
                size: AppLayout.headerTitleFontSize,
                weight: AppLayout.headerTitleFontWeight
            ))
            .foregroundStyle(AppColors.headerTitle)
            .lineLimit(1)
    }
}
