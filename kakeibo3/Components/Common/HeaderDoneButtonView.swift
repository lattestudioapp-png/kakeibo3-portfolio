import SwiftUI

struct HeaderDoneButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: AppLayout.headerButtonIconSize, weight: .bold))
                .foregroundStyle(AppColors.headerButtonIcon)
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
                .background(Circle().fill(AppColors.headerButtonBackground))
        }
        .buttonStyle(.plain)
    }
}
