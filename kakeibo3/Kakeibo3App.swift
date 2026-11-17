import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@main
struct Kakeibo3App: App {
    @StateObject private var photoDialog = PhotoDialogCoordinator()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var passcodeManager = PasscodeManager.shared
    @StateObject private var entitlementStore = EntitlementStore.shared
    @StateObject private var migrationCoordinator = MigrationCoordinator()
    @StateObject private var startupCoordinator = CoreDataStartupCoordinator()

    @Environment(\.scenePhase) private var scenePhase

    // 起動時点の UserDefaults を直読みして初期ロック状態を決める
    @State private var isAppLocked = PasscodeManager.shared.isPasscodeLockEnabled
    @State private var didEnterBackground = false

    var body: some Scene {
        WindowGroup {
            Group {
                switch migrationCoordinator.state {
                case .checking, .migrating:
                    // 通常の家計簿画面は表示しない。CoreDataStack.shared / Repository /
                    // 各DataSync observer / BookMigrationService等はまだ一切起動しない。
                    MigrationProgressView()

                case .failed(let detail):
                    // 通常画面へは進めない。既存データ(旧SwiftDataストア・本番Core Dataストア
                    // どちらも)は変更していない。再試行のみ提供し、初期化系の選択肢は出さない。
                    MigrationErrorView(detail: detail) {
                        migrationCoordinator.retry()
                    }

                case .completed, .notNeeded:
                    switch startupCoordinator.state {
                    case .pending, .splitMigrating, .waitingForCloudKitImport:
                        // Split Migration(旧Kakeibo3.sqlite → Cloud/Local分割)、またはCloudKit
                        // 初回importの完了待ち。CoreDataStack.shared / BookMigrationService等は
                        // まだ一切実行しない(startupCoordinator.runIfNeeded()の中でのみ触れる)。
                        MigrationProgressView()

                    case .awaitingFreshInstallConfirmation:
                        // 【複数端末の同時初回起動対策・C1】ローカルが空・かつこの端末でも
                        // メイン帳簿を一度も確立していない場合のみ表示される(既存データのある
                        // 端末・アップデートではこの画面を経由しない)。「開始する」が押されるまで
                        // BookMigrationService.migrateIfNeeded()は呼ばれない。
                        FreshInstallConfirmationView {
                            startupCoordinator.confirmFreshInstall()
                        }

                    case .failed(let detail):
                        // 通常画面へは進めない。既存データ(旧Kakeibo3.sqlite・本番Cloud/Local
                        // ストアどちらも)は変更していない。再試行のみ提供する。
                        MigrationErrorView(detail: detail) {
                            startupCoordinator.retry()
                        }

                    case .ready:
                        // ここまで来て初めて、CoreDataStack.sharedのロード
                        // (＝Split Migration完了・CloudKit接続確定済み)が保証される。
                        MainView()
                            .preferredColorScheme(.light)
                            .environmentObject(photoDialog)
                            .environmentObject(themeManager)
                            .environmentObject(passcodeManager)
                            .environmentObject(entitlementStore)
                            // fullScreenCover をルートに置くことで、
                            // 設定シートなど全ての子 View より前面にロック画面を出せる
                            .fullScreenCover(isPresented: $isAppLocked) {
                                PasscodeLockView {
                                    isAppLocked = false
                                }
                                .interactiveDismissDisabled(true)
                            }
                            .onAppear {
                                // 【調査用診断ログ】このonAppear自体が同一セッション内で複数回
                                // 発火していないかを最優先で記録する（調査内容1）。
                                DiagnosticLog.logOnAppearFired()
                                setUpAdsIfNeeded()
                                // 【調査用診断ログ】個人情報・取引内容は一切出力しない（件数・識別子のみ）。
                                // カテゴリー・支出が再起動後に消える不具合の調査用。
                                DiagnosticLog.logStartupSnapshot(label: "before BookMigrationService.migrateIfNeeded()")
                                // 複数帳簿対応：BookDataが1件も無ければメイン帳簿を作成し、既存の収入・支出を
                                // 紐づける。スナップショットのbookIdバックフィルより先に済ませておく必要がある。
                                // (SwiftData→Core Data移行とは別の、既存の「nilなbookIdの行をメイン帳簿へ
                                // 割り当てる」バックフィル。移行済みのbookIdは書き換えない。詳細は末尾コメント参照)
                                BookMigrationService.migrateIfNeeded()
                                DiagnosticLog.logStartupSnapshot(label: "after BookMigrationService.migrateIfNeeded()")
                                // アプリ起動時に一度だけ、スナップショットが空なら全期間ぶんバックフィルする
                                // (SwiftDataからは移行しなかった派生データを、移行完了後のこのタイミングで
                                // 対象帳簿ぶんだけ作り直す)
                                SnapshotManager.backfillIfNeeded()
                                AnalysisSnapshotManager.backfillIfNeeded()
                                // 登録数の上限は廃止済みだが、過去にロックされたデータが残っている場合に備えて
                                // 念のため全解除しておく（現在は何もロックされないため通常は無害な呼び出し）
                                DowngradeLockService.unlockAll()
                                // 固定費/定期収入/定期振替：設定日が到来した分をここで生成する。
                                // バックグラウンド処理が無いため、起動のたびに確認するのが
                                // 「日付が来たら登録される」を成立させる唯一のタイミングになる。
                                RecurringEntryGenerator.backfillAllIfNeeded()
                                // ゴミ箱：trashedAtから30日以上経過した支出・収入・振替を起動のたびに完全削除する
                                TrashPurgeService.purgeExpiredIfNeeded()
                                // レシート写真のCloudKit同期（アップロード方向）：この機能の実装前から
                                // 存在する写真の1回限りの移行と、ensureSynced単体呼び出しが欠落した
                                // ケースの安全網を兼ねる（既存の.jpgファイル・収支データは読み取り専用で
                                // 一切変更しない）
                                ReceiptPhotoSyncService.backfillAllIfNeeded()
                                // レシート写真のCloudKit同期（ダウンロード方向）：他端末からCloudKit
                                // 経由で届いたがローカル.jpgへまだ書き出されていない写真を補う安全網。
                                // メインスレッドをブロックしないよう内部でTask.detachedを使うため、
                                // ここでは同期的に呼んでよい
                                ReceiptPhotoSyncService.materializeAllMissingLocalFilesIfNeeded()
                                // マネーアイテムの色：この機能が実装される前から存在するデータに、起動時に一度だけ色を確定・保存する
                                MoneyItemColorDefault.backfillMissingColorsIfNeeded()
                            }
                    }
                }
            }
            .task {
                // アプリ起動のたびに実行(SwiftDataLegacyReader.legacyStoreExists()が
                // ごく軽い存在確認のため、移行不要な通常起動でも体感コストはほぼ無い)。
                // バックグラウンド実行はしない: 通常画面はmigrationCoordinator.stateが
                // completed/notNeededになるまで表示されず、実処理自体もこのTaskの完了を
                // 待ってから状態が遷移する(並行実行しない)。
                await migrationCoordinator.runIfNeeded()
                // 続けてSplit Migration〜CloudKit接続確定〜初回import待ちを実行する。
                // migrationCoordinatorが失敗した場合はここへ進まない
                // (旧SwiftDataストアが読めないなら、その後の処理も安全に進められないため)。
                //
                // 【バグ修正】以前はここで`, startupCoordinator.isReady`も同時に要求していたが、
                // startupCoordinator.isReady(=既に.readyへ到達済みか)は、まさにこの直後で
                // 初めてrunIfNeeded()を呼ぼうとしている時点では常にfalseであり、
                // 「呼ぶ前から既に完了していることを要求する」という論理的に満たせない条件に
                // なっていた。結果、CoreDataStartupCoordinator.runIfNeeded()が永久に一度も
                // 呼ばれず、画面が「データを準備しています」のまま無限にハングする不具合があった
                // (実機・新規インストール相当の状態でのみ再現し、どのテストにも
                // CoreDataStartupCoordinator.runIfNeeded()自体を呼ばない経路が無かったため
                // 検出できなかった)。
                guard migrationCoordinator.isReady else { return }
                await startupCoordinator.runIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                didEnterBackground = true
                PasscodeManager.shared.recordBackgroundEntry()
                // 自動バックアップ（backgroundに入った瞬間のみ実行）。移行完了前は
                // CoreDataStack.sharedにまだ触れていないため、ここでは絶対に呼ばない。
                if migrationCoordinator.isReady, startupCoordinator.isReady, BackupManager.shared.autoBackupEnabled {
                    BackupManager.shared.performAutoBackup()
                }
            case .inactive:
                didEnterBackground = true
            case .active:
                if didEnterBackground && PasscodeManager.shared.shouldLockOnForeground() {
                    isAppLocked = true
                }
                // 自動バックアップ（アプリを開いた時も頻度チェックして実行）
                if migrationCoordinator.isReady, startupCoordinator.isReady, didEnterBackground, BackupManager.shared.autoBackupEnabled {
                    BackupManager.shared.performAutoBackup()
                }
                // バックグラウンドから復帰した時にも、日付が変わって設定日が到来した
                // 固定費/定期収入/定期振替が無いか確認する
                if migrationCoordinator.isReady, startupCoordinator.isReady, didEnterBackground {
                    RecurringEntryGenerator.backfillAllIfNeeded()
                }
                didEnterBackground = false
            @unknown default:
                break
            }
        }
    }

    // MARK: - 広告SDK初期化 & トラッキング許可リクエスト
    //
    // 起動のたびに呼ばれるが、ATTrackingManager は一度許可/拒否が決まった後は
    // 再度ダイアログを出さずキャッシュ済みの状態を返すだけなので害はない。

    private func setUpAdsIfNeeded() {
        // 家計簿アプリという性質上、広告の質は信頼に直結する。
        // 全対象を「一般向け（Gレーティング相当）」に制限し、出会い系・ギャンブル等の
        // 露骨な広告が紛れ込まないようにする（アダルト・ギャンブル系はこれで概ね除外される）。
        MobileAds.shared.requestConfiguration.maxAdContentRating = GADMaxAdContentRating.general
        MobileAds.shared.start(completionHandler: nil)
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }

    // MARK: - 各Migration/バックフィル処理の役割と実行順(3種類は別物)
    //
    // 1. migrationCoordinator → MigrationBootstrap(SwiftData → 単一Core Data(Kakeibo3.sqlite)移行。
    //    一回きり)。旧SwiftDataストアが存在する端末でだけ動く。CoreDataStack.sharedには一切
    //    触れず、完了するまで通常画面へは進まない。UUID・bookIdをそのまま維持してコピーするだけで、
    //    bookIdがnilだった行はnilのまま移す(3のBookMigrationServiceに委ねる)。
    //
    // 2. startupCoordinator → SplitMigrationBootstrap(単一Kakeibo3.sqlite → Cloud/Local分割移行。
    //    一回きり)+ CoreDataStack.sharedのロード(Cloud/Localストア・CloudKit接続) +
    //    CloudKit初回importの完了待ち。1が完了した後、CoreDataStack.sharedへ触れる前に必ず
    //    実行する(実機で確認された「Split Migration未接続のままCloud/Localストアが空で
    //    スタートし、BookMigrationServiceが誤ってメイン帳簿を重複生成する」不具合の対策)。
    //
    // 3. BookMigrationService.migrateIfNeeded()(メイン帳簿の確保 + nilなbookIdのバックフィル。
    //    起動のたび)。複数帳簿対応より前からある既存の仕組みで、startupCoordinatorがreadyに
    //    なった後の通常起動シーケンスの一部として毎回呼ばれる。「メイン帳簿を新規作成してよいか」
    //    は2で確定した状態(旧ストアの有無・CloudKit同期の有無・初回import完了状態)を踏まえて
    //    判定する(decideMainBookCreation(_:)参照)。bookId自体のバックフィル対象は
    //    bookId == nilの行のみで、既に値が入っているbookId(1の移行がそのままコピーした値も含む)は
    //    一切書き換えない。したがって「移行後にBookMigrationServiceがさらに古い移行を
    //    走らせてデータを書き換える」ことは起きない――1・3は対象が排他的(bookIdの
    //    有無で分かれる)であり、3は1・2の結果を壊さず補完するだけの関係にある。
}
