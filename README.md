# kakeibo3

SwiftUIで開発しているiPhone向け家計簿アプリです。支出・収入・振替の記録、月ごとの集計、予算管理をまとめて扱います。データの永続化にはCore Dataを使用し、CloudKitによる個人用データの同期と、旧SwiftDataストアからの移行処理を実装しています。帳簿共有は非公開の開発用リポジトリで開発中で、このブランチでは未実装です。

> 採用選考・技術レビュー向けのソースコードです。開発用の非公開リポジトリから、2026年11月17日時点のコードを切り出しています。過去の開発履歴・作業ブランチは含みません。

## 主な機能

- 支出・収入・口座間振替の入力、検索、カレンダー表示
- カテゴリ別・期間別の分析、資産推移、予算管理
- 複数帳簿、定期取引、ゴミ箱
- バックアップ・復元、CSV出力、帳簿のPDF出力
- iCloudによる個人用データの同期（実機での確認が必要）

レシートOCRのコードも含みますが、現在は`FeatureFlags.isReceiptFeatureEnabled = false`で画面への導線を非表示にしています。同期の実機動作は、シミュレーターのテスト結果とは別に確認が必要です。

### 開発中・既知の課題

- 帳簿共有・招待：このブランチのサービスは未実装です。実装と検証は非公開の開発用リポジトリで進めています。
- 旧SwiftDataストアからの移行：既知の不具合の修正は開発用リポジトリにあり、この公開版には未反映です。実データの移行完了は保証できません。
- 複数端末での帳簿・定期取引の重複、古い編集による削除データの復活：修正は非公開の開発用リポジトリにあり、この公開版には未反映です。
- アプリのパスコードは現在UserDefaultsに保存しており、保存方式の改善が必要です。

2026年11月17日時点のコードです。App Store配布に向けた移行・同期・購入の実機確認は、ソース公開とは別に進めています。

## 構成とコードの読み方

| 場所 | 役割・確認できる実装 |
| --- | --- |
| `kakeibo3/Views`・`Components` | SwiftUIの画面と共通部品 |
| `kakeibo3/ViewModels` | 入力・カレンダー・分析・共有の画面状態 |
| `kakeibo3/Models`・`Repositories` | データ表現とデータアクセス |
| `kakeibo3/Services/CoreDataStack.swift`・`Services/CoreData` | ストア構成とモデルの保存・読み出し |
| `kakeibo3/Migration` | 旧ストアの判定、移行、検証、切り替え |
| `kakeibo3/Services/RecurringEntryGenerator.swift` | 定期取引の生成 |
| `kakeibo3/Services/BookSharingService.swift` | 帳簿共有のインターフェース（このブランチでは未実装） |
| `kakeibo3Tests` | 集計、保存・復元、移行、同期周辺などの単体・回帰テスト |
| `kakeibo3UITests` | 画面操作の回帰テスト |

ストア移行の失敗時の扱いや、複数端末からの変更とローカル状態を扱う実装を中心に確認できます。開発中の機能・改善点を含み、すべての端末・同期条件での動作を保証するものではありません。

## 開発環境

- macOSとXcode。今回の確認環境はXcode 26.4.1、iOS 26.4シミュレーターです。
- アプリターゲットの最小OSはiOS 26.0です。プロジェクト共通設定にはiOS 26.4の指定もあるため、まず26.4のシミュレーターで確認してください。
- 依存パッケージはSwift Package Managerで取得します。バージョンは`Package.resolved`に記録しています。

`kakeibo3.xcodeproj`を開き、`kakeibo3`スキームとiPhoneシミュレーターを選択してください。端末へのインストール、CloudKit、StoreKitの確認には、それぞれ自分の開発チーム・サービス設定が必要です。既存のBundle IDやCloudKitコンテナIDを使って配布しないでください。

### 単体テスト

```sh
xcodebuild test \
  -project kakeibo3.xcodeproj \
  -scheme kakeibo3 \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:kakeibo3Tests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

インストール済みのシミュレーターに合わせて`-destination`を変更してください。UIテストは`-only-testing:kakeibo3UITests`で別に実行できます。単体テスト中のCloudKit接続はコードで無効化しています。

元の非公開リポジトリの2026年11月17日のCI（`99d8545`、この公開版と同じアプリソース）では、シミュレーターの単体・回帰テスト553件成功・失敗0件をログで確認しました。今回の文書整理でテストを再実行した結果ではありません。UIテスト、実機での同期・招待受信、課金は今回の確認対象に含めていません。Swiftの並行処理などに関する既存のコンパイラー警告が残っています。

## 依存ライブラリ・素材・ライセンス

[THIRD_PARTY.md](THIRD_PARTY.md)に依存パッケージと素材の確認状況を記載しています。本リポジトリは採用選考・技術レビューでの閲覧を目的として公開しています。独自コード・画像にMIT等のOSSライセンスは付与していません。第三者ライブラリの利用条件は各提供元の記載を参照してください。
