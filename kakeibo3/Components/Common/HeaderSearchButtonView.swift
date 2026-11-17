import SwiftUI

struct HeaderSearchButtonView: View {

    @State private var isShowingSearchView = false

    private let buttonSize: CGFloat = AppLayout.headerButtonSize
    private let iconSize: CGFloat = 20

    var body: some View {
        Button {
            isShowingSearchView = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(AppColors.headerButtonIcon)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(AppColors.headerButtonBackground))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isShowingSearchView) {
            SearchView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, AppLayout.headerButtonHorizontalPadding)
        .padding(.top, AppLayout.headerContentTopPadding)
    }
}
