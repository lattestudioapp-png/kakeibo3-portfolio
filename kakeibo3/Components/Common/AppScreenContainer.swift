import SwiftUI

// MARK: - アプリ共通画面土台

struct AppScreenContainer<Content: View, HeaderOverlay: View>: View {
    let content: Content
    let headerOverlay: HeaderOverlay

    @AppStorage(AppColors.themeColorStorageKey)
    private var themeHex: String = AppColors.defaultThemeHex

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder headerOverlay: () -> HeaderOverlay
    ) {
        self.content = content()
        self.headerOverlay = headerOverlay()
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                AppHeaderBackground()

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            headerOverlay
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - ヘッダー上に重ねるものがない画面用

extension AppScreenContainer where HeaderOverlay == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.headerOverlay = EmptyView()
    }
}
