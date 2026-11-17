import SwiftUI

struct AppHeaderTitleBarView: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            AppColors.main
                .ignoresSafeArea(edges: .top)

            HStack {
                HeaderCloseButtonView { onClose() }
                    .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

                Spacer()

                AppHeaderTitleView(title: title)

                Spacer()

                Color.clear
                    .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
            }
            .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
            .padding(.top, AppLayout.headerContentTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: AppLayout.headerHeight)
    }
}
