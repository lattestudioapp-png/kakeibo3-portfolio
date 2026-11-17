import SwiftUI
import StoreKit

// MARK: - 広告削除の購入画面

struct RemoveAdsUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var store: EntitlementStore

    @State private var isPurchasing = false
    @State private var isRestoring = false

    var body: some View {
        ZStack {
            AppColors.sheetBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        purchaseCard
                        if !store.hasRemoveAds {
                            restoreLink
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert(
            store.errorMessage ?? "",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppHeaderTitleView(title: "広告削除")
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - 購入カード

    private var purchaseCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 36))
                .foregroundStyle(themeManager.mainColor)

            Text("広告削除")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.82))

            Text(priceText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(themeManager.mainColor)

            Text("広告を非表示にして、より快適に使えます。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            purchaseButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var purchaseButton: some View {
        if store.hasRemoveAds {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("購入済みです。ご利用ありがとうございます。")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeManager.mainColor)
            .padding(.top, 4)
        } else {
            Button {
                purchase()
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text("購入する")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(themeManager.mainColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || store.isLoadingProducts)
            .padding(.top, 4)
        }
    }

    /// App Store から取得した価格（買い切り）。取得できない場合は想定価格（¥600）を表示する。
    private var priceText: String {
        if store.hasRemoveAds { return "購入済み" }
        return store.removeAdsProduct?.displayPrice ?? "¥600"
    }

    // MARK: - 購入の復元

    private var restoreLink: some View {
        Button {
            restore()
        } label: {
            HStack(spacing: 6) {
                if isRestoring {
                    ProgressView()
                }
                Text("購入を復元")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.45))
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
    }

    // MARK: - Actions

    private func purchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            await store.purchaseRemoveAds()
            isPurchasing = false
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            await store.restorePurchases()
            isRestoring = false
        }
    }
}
