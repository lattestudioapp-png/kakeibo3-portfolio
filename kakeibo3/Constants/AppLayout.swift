import SwiftUI

enum AppLayout {
    // 全画面共通ヘッダーの高さ
    static let headerHeight: CGFloat = 110

    // 下部ナビゲーションバー用の高さ
    // 広告削除を購入していない場合はタブバーの下にバナー広告が表示され、その分タブバーが
    // 上にずれるため、広告導入前と同じ「保存ボタン〜タブバー」等の距離感を保てるよう、
    // 広告表示中はその高さ＋余白ぶんを上乗せする。
    static var bottomNavigationHeight: CGFloat {
        baseBottomNavigationHeight + (EntitlementStore.shared.hasRemoveAds ? 0 : adBannerReservedHeight)
    }
    private static let baseBottomNavigationHeight: CGFloat = 78

    // バナー広告の高さ + タブバーとの間隔（MainView の広告表示レイアウトと同じ値を使う）
    static let adBannerHeight: CGFloat = 50
    static let adBannerSpacing: CGFloat = 25
    static let adBannerReservedHeight: CGFloat = adBannerHeight + adBannerSpacing

    // 支出 / 収入切り替えバーの横幅（入力画面・編集画面共通）
    static let transactionTypeSwitchWidth: CGFloat = 250
    // レシート機能有効時、入力画面の切り替えバーに「レシート」を含めた3択分の横幅
    static let transactionTypeSwitchWidthWithReceipt: CGFloat = 340

    // ヘッダー内ボタン共通（Close / Done / Search）
    static let headerButtonSize: CGFloat = 38
    static let headerButtonIconSize: CGFloat = 18
    static let headerButtonHorizontalPadding: CGFloat = 20
    static let headerContentTopPadding: CGFloat = 62

    // ヘッダー内コントロール（ボタン・タイトル・セグメント）の中心 Y 座標
    // ZStack(alignment: .top) + padding(.top, headerContentTopPadding) で高さ headerButtonSize の要素を配置したときの中心
    static let headerControlCenterY: CGFloat = headerContentTopPadding + headerButtonSize / 2
    // = 62 + 19 = 81

    // ヘッダータイトル文字スタイル
    static let headerTitleFontSize: CGFloat = 20
    static let headerTitleFontWeight: Font.Weight = .regular

    // 選択行 / テキスト入力行
    static let selectionRowHeight: CGFloat = 56
    static let textFieldRowHeight: CGFloat = 56

    // カテゴリー編集行
    static let categoryEditRowHeight: CGFloat = 45

    // カテゴリー色プレビュー
    static let categoryColorPreviewSize: CGFloat = 30

    // 分析詳細画面専用ヘッダー（モーダルシートとして表示される詳細画面）
    // ヘッダーボタン/タイトルの上下余白。ヘッダー背景は .ignoresSafeArea で Dynamic Island まで延伸する。
    static let detailHeaderVerticalPadding: CGFloat = 12
    // 月切り替えバーの高さ
    static let detailMonthSelectorBarHeight: CGFloat = 52

    // 金額入力キーボード：全画面共通定数
    // proxy.size.height * 0.38 で動的計算すると画面コンテキスト（TabView / sheet）によって
    // 高さが変わるため、共通定数で固定して全画面で統一する。
    static let calculatorKeyboardBodyHeight: CGFloat = 265

    // 通常画面用キーボードコンテナ（InputView基準）
    // InputView の calculatorKeyboardBottomPadding と同じ値。
    // BottomNavigationBarの高さ分だけキーボードを上に押し上げ、背景色で隙間を埋める。
    static let normalKeyboardBottomPadding: CGFloat = 95

    // Sheet用キーボードコンテナ調整定数
    // sheet内ではGeometryReader / SafeArea の基準が通常画面と異なるため
    // InputViewと同じ見た目になるよう個別調整する。初期値はすべて 0。
    static let sheetKeyboardBottomPadding: CGFloat = 95
    static let sheetKeyboardTopPadding: CGFloat = 0
    static let sheetKeyboardBottomOffset: CGFloat = 0
}
