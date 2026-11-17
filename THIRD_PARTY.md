# 依存ライブラリと素材

確認日: 2026-11-17

## Swift Package Manager

| パッケージ | 固定バージョン | 上流の確認先 |
| --- | --- | --- |
| Google Mobile Ads | 13.6.0 | [固定リビジョンのLICENSE](https://github.com/googleads/swift-package-manager-google-mobile-ads/blob/7651abff585dc8dacd1744222d5f03bdd2a8532a/LICENSE) |
| Google User Messaging Platform | 3.1.0 | [固定リビジョンのLICENSE](https://github.com/googleads/swift-package-manager-google-user-messaging-platform/blob/13b248eaa73b7826f0efb1bcf455e251d65ecb1b/LICENSE) |

両SPMリポジトリのLICENSEはApache License 2.0です。取得したSDKバイナリーまで一律にApache 2.0で再配布できるという意味ではありません。[Google Mobile Ads SDKの利用条件](https://developers.google.com/admob/ios/terms)も確認が必要です。依存コード・SDKバイナリーはこのリポジトリに同梱せず、SPMから取得します。

広告設定にはGoogle提供のデモIDを使用しています。[Googleのテスト広告の説明](https://developers.google.com/admob/ios/test-ads)を参照してください。これらは個人のAPI秘密鍵ではありません。

## Appleのフレームワーク

SwiftUI、Core Data、CloudKit、StoreKit、Vision/VisionKit等はApple SDKを参照しています。Apple SDKそのものは同梱していません。

## 画像素材

`kakeibo3/Assets.xcassets/AppIcon.appiconset/AppIcon.png`は、作者が自身で作成したと確認済みです（2026年11月17日）。この公開版には現行アイコンのみを含め、過去の画像履歴は含みません。

## アプリ独自コード

独自コード・画像にMIT等のOSSライセンスは付与していません。採用選考・技術レビュー向けに公開しています。
