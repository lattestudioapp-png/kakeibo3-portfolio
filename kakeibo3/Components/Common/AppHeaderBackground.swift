import SwiftUI

// MARK: - 共通ヘッダー背景

struct AppHeaderBackground: View {
    @AppStorage(AppColors.themeColorStorageKey)
    private var themeHex: String = AppColors.defaultThemeHex

    var body: some View {
        AppColors.main
            .frame(height: AppLayout.headerHeight)
            .ignoresSafeArea(edges: .top)
    }
}
