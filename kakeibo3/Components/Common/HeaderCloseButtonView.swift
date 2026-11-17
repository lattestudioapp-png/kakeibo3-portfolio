import SwiftUI

struct HeaderCloseButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: AppLayout.headerButtonIconSize, weight: .bold))
                .foregroundStyle(AppColors.headerButtonIcon)
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
                .background(Circle().fill(AppColors.headerButtonBackground))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("headerCloseButton")
    }
}
