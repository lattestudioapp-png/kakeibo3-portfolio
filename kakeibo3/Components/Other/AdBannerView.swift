import SwiftUI
import GoogleMobileAds

// MARK: - バナー広告View（無料版のみ表示）
//
// 有料版判定は呼び出し側（MainView）で行い、このViewは渡された広告ユニットIDで
// バナー広告を表示するだけに専念する。

struct AdBannerView: UIViewRepresentable {
    let adUnitID: String

    /// Googleが公開しているテスト用バナー広告ユニットID。
    /// 本番配信前に、自分のAdMobアカウントで取得した広告ユニットIDに差し替えること。
    static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.currentRootViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        uiView.rootViewController = Self.currentRootViewController()
    }

    private static func currentRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
