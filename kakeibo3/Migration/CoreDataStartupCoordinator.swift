import Combine
import CoreData
import Foundation

// MARK: - Split Migration〜CloudKit初回import待ちまでを、CoreDataStack.sharedへ触れる前に
// 完結させる起動シーケンスの入口(Step 2B以降を実際の起動へ接続する)
//
// これまでSplitMigrationBootstrap(旧Kakeibo3.sqlite → Cloud/Local分割)は実装・テスト済み
// だったが、本番の起動シーケンス(Kakeibo3App.swift)からは一度も呼ばれていなかった。
// そのため実機では毎回Cloud/Localストアが空の状態からスタートし、
// BookMigrationServiceが「空だからメイン帳簿を作る」と誤判定して重複メイン帳簿を
// 生成する不具合が実機で確認された。この型はその不具合の根本原因である
// 「Split Migrationが未接続」「CloudKit初回importを待たずにローカル空と断定する」の
// 両方を解消するために、MigrationCoordinator(SwiftData→単一Core Data、B1/B2)の後に
// 続けて実行する新しいステップとして追加する。
//
// 起動順（Kakeibo3App.swift）:
//   1. MigrationCoordinator: 旧SwiftData → 単一Core Data(Kakeibo3.sqlite)移行
//   2. CoreDataStartupCoordinator.runIfNeeded():
//      2a. SplitMigrationBootstrap: 単一Kakeibo3.sqlite → Cloud/Local分割移行
//          (CoreDataStack.sharedには一切触れない。SplitMigrationBootstrap自体が
//          独立した一時CoreDataStackインスタンスだけを使う設計のため)
//      2b. ここで初めてCoreDataStack.sharedへ触れる(Cloud/Localストアのロード＝CloudKit接続)
//      2c. CloudKitが有効なセッションなら、初回import完了(または妥当なタイムアウト)を待つ
//   3. BookMigrationService / DataInitializer / RootView表示 (Kakeibo3App.onAppear)
@MainActor
final class CoreDataStartupCoordinator: ObservableObject {

    enum State: Equatable {
        /// まだ開始していない
        case pending
        /// Split Migration(旧Kakeibo3.sqlite → Cloud/Local分割)を実行中
        case splitMigrating
        /// CoreDataStack.shared(Cloud/Localストア・CloudKit接続)をロード済み。
        /// CloudKit同期が有効な場合、初回importの完了を待っている。
        case waitingForCloudKitImport
        /// 【複数端末の同時初回起動対策・C1】ローカルにBookが1件も無く、このデバイスでも
        /// まだメイン帳簿を一度も確立していない(＝本当に新規インストールの可能性が高い)。
        /// ユーザーが明示的に「開始する」を選ぶまで、メイン帳簿の新規作成(createNew)を
        /// 保留する。既にBookがある、または確立済みの端末ではこの状態を経由しない。
        case awaitingFreshInstallConfirmation
        /// 通常画面へ進んでよい
        case ready
        /// 失敗。既存データ(旧ストア・本番ストアどちらも)は変更していない。
        case failed(String)
    }

    @Published private(set) var state: State = .pending

    /// CloudKit初回importを待つ最大秒数。ネットワーク不調・iCloud未サインイン等で
    /// 永久に成功イベントが来ないケースの安全弁(この秒数を過ぎると「わからない」まま
    /// .readyへ進む＝BookMigrationService側は`.pending`のまま保守的に振る舞う)。
    ///
    /// 【調査で判明した事実】複数デバイスが同じCloudKitコンテナへほぼ同時に初回接続する場合、
    /// このタイムアウト自体が短すぎても「新しいメイン帳簿を誤って作る」ことには直結しない
    /// （BookMigrationService.decideMainBookCreationは、タイムアウトしてもinitialImportStateが
    /// .pendingのままなら.waitAndRetryとなり、新規作成はしない設計で、これは今回変更していない）。
    /// ただし短すぎると「実際には他デバイスの既存メイン帳簿がもう少しで取り込まれるはずなのに、
    /// .pendingのまま帳簿が使えない時間」が不必要に長くなる。初回のスキーマ・ゾーン設定を伴う
    /// 初回importは数秒以上かかることもあるため、安全弁の意味を保ったまま少し長めにする。
    var initialImportTimeout: TimeInterval = 15

    /// 【複数端末の同時初回起動対策・緩和策】複数端末が同じ(本当に空の)CloudKitコンテナへ
    /// ほぼ同時に初回接続した場合、「初回importが0件で完了した」というだけでは
    /// 「本当に新規か、まだ他端末の書き込みがCloudKit経由で届いていないだけか」を
    /// 区別できない。両端末がこの瞬間に揃って.createNewと判定すると、互いに別の
    /// メイン帳簿を作ってしまい、後から重複として残る(実機調査で確認したCloudKit内部
    /// resetによる重複とは別の、本当に新規インストール同士が競合するケース)。
    ///
    /// NSPersistentCloudKitContainerはオブジェクト単位のCRDT的マージを行わないため、
    /// Core Data層だけでは「2台が同時に同じ意味のレコードを1件だけ作る」ことを
    /// 完全に保証できない(確実に防ぐには生のCloudKit APIで一意なレコードIDに対する
    /// サーバー側の競合解決を使う必要があり、これは今回のスコープを超える大きな変更)。
    ///
    /// そのため、ここでは完全な防止ではなく「競合が起きる窓を縮める」緩和策として、
    /// 新規作成されようとしているまさにその瞬間(ローカルが空・かつestablishedMainBookId
    /// も未確立)だけ追加で待ち、他端末の書き込みがCloudKit経由で届く時間を与える。
    /// 既に帳簿が確立済みの端末(ほとんどの起動)はこの待機の影響を一切受けない。
    ///
    /// 【C2:適応的待機への変更】固定でこの秒数だけ必ず寝るのではなく、この秒数を
    /// 「上限(ハードキャップ)」として使う。実際の待機はwaitOutFreshInstallRaceWindowIfNeeded()
    /// 参照。
    var freshInstallGraceWindow: TimeInterval = 5

    /// C2の適応的待機でのポーリング間隔。短くするほど「他端末の帳簿が届いた瞬間」を
    /// 早く検知できるが、CPU/バッテリーへの影響との兼ね合いでこの値にしている。
    var freshInstallPollInterval: TimeInterval = 0.5

    /// C2の適応的待機での「静穏期間」。CloudSyncSettings.shared.lastSyncEventAt
    /// (直近のCloudKit同期イベント発生時刻、成否問わず)からこの秒数だけ新しい
    /// イベントが無ければ、「もう同期活動が収まった＝これ以上待っても他端末の
    /// 帳簿が追加で届く可能性は低い」と判断して待機を終える。これにより、
    /// 本当に単独端末の新規インストール(競合相手がいない)では、
    /// freshInstallGraceWindowの上限まで待たず、この静穏期間が過ぎた時点で
    /// 早期に進める。
    var freshInstallQuietPeriod: TimeInterval = 1.5

    private var isRunning = false

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    /// 実アプリからはこちらを呼ぶ(実Application Support / 実UserDefaults.standardを使う)。
    func runIfNeeded() async {
        await runIfNeeded(
            productionDirectory: NSPersistentContainer.defaultDirectoryURL(),
            workDirectory: FileManager.default.temporaryDirectory,
            userDefaults: .standard
        )
    }

    /// テスト用:本番ディレクトリ・作業ディレクトリ・UserDefaultsを直接指定して実行する。
    func runIfNeeded(
        productionDirectory: URL,
        workDirectory: URL,
        userDefaults: UserDefaults
    ) async {
        guard !isRunning else {
            DiagnosticLog.logReentrancyGuardTriggered(coordinator: "CoreDataStartupCoordinator")
            return
        }
        isRunning = true
        DiagnosticLog.logCoordinatorLifecycle(coordinator: "CoreDataStartupCoordinator", event: "開始")
        defer {
            isRunning = false
            DiagnosticLog.logCoordinatorLifecycle(coordinator: "CoreDataStartupCoordinator", event: "終了 state=\(state)")
        }

        state = .splitMigrating

        // 【調査用診断ログ】旧統合ストアが存在するかどうか自体を記録する
        // （存在しなければmigrateAndPromoteIfNeeded内部は.notNeededを即返すのみで、
        // 本番のCloud/Localストアには一切触れない設計であることの裏付けに使う）。
        DiagnosticLog.write("STARTUP: legacyUnifiedStoreExists=\(LegacyUnifiedStoreLocator.paths(directory: productionDirectory, requireExists: true) != nil)")

        let outcome = await Task.detached(priority: .userInitiated) {
            SplitMigrationBootstrap.migrateAndPromoteIfNeeded(
                workDirectory: workDirectory,
                productionDirectory: productionDirectory,
                userDefaults: userDefaults
            )
        }.value
        DiagnosticLog.write("STARTUP: SplitMigrationBootstrap outcome=\(outcome)")

        switch outcome {
        case .notNeeded, .promoted, .alreadyMigrated:
            break
        case .tempStoreVerified:
            // migrateAndPromoteIfNeeded経由ではこの状態は返らないはずだが、
            // 万一発生した場合は安全側に倒して失敗扱いにする(通常画面には進めない)。
            state = .failed("内部エラー: 想定外の移行状態(tempStoreVerified)")
            return
        case .failed(let failure):
            state = .failed("\(failure)")
            return
        }

        // ここで初めてCoreDataStack.sharedへ触れる(Split Migration完了・または不要と確定した後)。
        // Split Migrationが実際に書き込んだのと同じproductionDirectoryを明示的に渡す
        // (デフォルトのCoreDataStack()はNSPersistentContainer.defaultDirectoryURL()という
        // 固定パスしか見ないため、テストでproductionDirectoryを差し替えても追従できない。
        // 本番では両者は常に同じパスになるため挙動は変わらない)。
        //
        // ストアのロード自体(CloudKit有効時はスキーマ初期化等のネットワーク処理を含む)が
        // 失敗・タイムアウトする可能性があるため、ここは必ずdo/catchで受け止める
        // (以前はmakeProductionStack内部でfatalErrorしていたため、実機・実CloudKit接続で
        // この処理が長時間完了しない場合、ユーザーには「データを準備しています」の画面が
        // ハングしたまま無反応に見える不具合があった)。失敗時は既存の再試行可能な
        // エラー画面(.failed)へ落とす。既存のCloud/Localストア自体は変更・削除しない。
        let stack: CoreDataStack
        do {
            stack = try CoreDataStack.makeProductionStack(directory: productionDirectory)
        } catch {
            state = .failed("Core Dataストアの読み込みに失敗しました: \(error)")
            return
        }
        CoreDataStack.shared = stack
        DiagnosticLog.logStoreIdentity(label: "after makeProductionStack")
        // CloudKitイベントの監視をこの時点で開始する(以後のwaitForInitialImportSettledが
        // イベントを取りこぼさないよう、CoreDataStack.shared確定直後に生成する)。
        _ = CloudSyncSettings.shared
        // 他端末でのCloudKit経由の変更を監視するオブザーバーも、CoreDataStack.shared確定後の
        // この時点で起動する(RemoteChangeObserver参照)。
        _ = RemoteChangeObserver.shared

        if stack.isCloudSyncActive {
            state = .waitingForCloudKitImport
            let settledState = await CloudSyncSettings.shared.waitForInitialImportSettled(timeout: initialImportTimeout)
            await waitOutFreshInstallRaceWindowIfNeeded(
                initialImportState: settledState,
                lastSyncEventAtProvider: { CloudSyncSettings.shared.lastSyncEventAt }
            )
        }

        // 【C1:明示的な確認ゲート】ここまで来てもなお「ローカルが空・かつ未確立」
        // (＝BookMigrationService.migrateIfNeeded()が.createNewを選ぶ可能性が高い状況)
        // なら、ユーザーの明示的な「開始する」操作を待つ。既にBookがある、または
        // 確立済みの端末(ほとんどの起動)はここを経由せず、常に.readyへ直進する
        // (needsFreshInstallGraceWindowと全く同じ条件を再利用し、判定ロジックを
        // 二重実装しない)。
        if needsFreshInstallConfirmation() {
            state = .awaitingFreshInstallConfirmation
            return
        }

        state = .ready
    }

    /// 「はじめに」確認画面を表示すべきかどうかを判定する。
    /// needsFreshInstallGraceWindow(_:)と同じ条件を使う(本当に新規作成されようとしている
    /// 瞬間と、確認ゲートを出すべき瞬間は常に同一であるべきため)。
    private func needsFreshInstallConfirmation() -> Bool {
        let establishedMainBookId = UserDefaults.standard
            .string(forKey: BookMigrationService.establishedMainBookIdKey)
            .flatMap(UUID.init(uuidString:))
        return Self.needsFreshInstallGraceWindow(
            existingBooksIsEmpty: BookDataSync.fetchAll().isEmpty,
            establishedMainBookId: establishedMainBookId
        )
    }

    /// 「はじめに」確認画面で「開始する」が選ばれた後に呼ぶ。これが呼ばれるまで、
    /// BookMigrationService.migrateIfNeeded()は実行されない(＝新規メイン帳簿も作られない)。
    func confirmFreshInstall() {
        guard case .awaitingFreshInstallConfirmation = state else { return }
        state = .ready
    }

    /// 複数端末の同時初回起動の競合緩和が必要かどうかを判定する純粋関数。
    ///
    /// internal公開の理由: 実際のCloudKit接続・非同期待機を伴わずに、単体テストから
    /// 判定条件だけを決定的に検証できるようにするため(decideMainBookCreationと同じ理由)。
    static func needsFreshInstallGraceWindow(existingBooksIsEmpty: Bool, establishedMainBookId: UUID?) -> Bool {
        existingBooksIsEmpty && establishedMainBookId == nil
    }

    /// 既にメイン帳簿が確立済み、またはローカルに何らかのBookが既にある場合は即座に戻る
    /// (ほとんどの起動はここに該当し、待機の影響を一切受けない)。
    /// 「ローカルが空・かつ未確立」という、まさに.createNewされようとしている瞬間だけ
    /// 追加で待ち、他端末の書き込みがCloudKit経由で届く時間を与える
    /// (BookMigrationService.migrateIfNeeded()はこの関数が返った後、Kakeibo3App.onAppearから
    /// 呼ばれる)。
    ///
    /// 【C2:固定5秒 → 適応的な待機】単純に固定秒数だけ寝るのではなく、以下の2点を行う:
    ///   1. ポーリングして、待機の途中で他端末の帳簿が1件でも届いたら即座に抜ける
    ///      (固定sleepでは、既に届いているのに残り時間をただ浪費していた)
    ///   2. CloudSyncSettings.shared.lastSyncEventAt(直近の同期イベント発生時刻)を見て、
    ///      「freshInstallQuietPeriod秒、新しい同期イベントが無い」状態が続いたら、
    ///      本当に競合相手がいないと判断し、freshInstallGraceWindow(上限)まで待たずに
    ///      早期に抜ける。単独端末の新規インストールでは通常この早期終了が効く。
    ///
    /// 【待機そのものが無意味なケースを事前に除外】CloudSyncSettings.shared.initialImportStateが
    /// .completedでない(＝初回importがまだ終わっていない、またはタイムアウトして
    /// 確信が持てないまま)場合、decideMainBookCreationはどのみち.waitAndRetryを返すため、
    /// ここで追加の待機をしても無意味(オフライン・ネットワーク不調で初回importが
    /// いつまでも終わらないケースで、無駄な待機を課さないための分岐)。
    ///
    /// internal公開の理由: isCloudSyncActive=trueの実CloudKit接続を伴わずに、
    /// 単体テストから直接この待機処理自体を決定的に検証できるようにするため。
    ///
    /// - Parameter initialImportState: 呼び出し元(runIfNeeded())からは、直前のwaitForInitialImportSettled()
    ///   の戻り値をそのまま渡す。単体テストからは、CloudSyncSettings.shared(真のシングルトンで
    ///   currentSessionEnabledが起動時に固定される。CloudSyncSettingsTests.swiftのコメント参照)に
    ///   一切触れずに「.completed」等の状況を直接作り出せるようにするため、必須パラメータにしている
    ///   (デフォルト値としてCloudSyncSettings.shared.initialImportStateを直接参照すると、
    ///   MainActor分離の都合で警告が出るため、呼び出し元で明示的に渡す形に統一する)。
    /// - Parameter lastSyncEventAtProvider: 呼び出し元からは実際のCloudSyncSettings.shared.lastSyncEventAtを
    ///   都度読むクロージャを渡す(ポーリング中に新しいCloudKitイベントが届けば、その都度最新の値を見る)。
    ///   単体テストからは、プロセス全体で共有される真のシングルトン(他のテストの実行順に値が
    ///   左右され得る)に触れず、決定的な値を返すクロージャに差し替えられるようにしている。
    func waitOutFreshInstallRaceWindowIfNeeded(
        initialImportState: CloudSyncSettings.InitialImportState,
        lastSyncEventAtProvider: () -> Date?
    ) async {
        let establishedMainBookId = UserDefaults.standard
            .string(forKey: BookMigrationService.establishedMainBookIdKey)
            .flatMap(UUID.init(uuidString:))
        guard Self.needsFreshInstallGraceWindow(
            existingBooksIsEmpty: BookDataSync.fetchAll().isEmpty,
            establishedMainBookId: establishedMainBookId
        ) else { return }
        guard initialImportState == .completed else { return }
        guard freshInstallGraceWindow > 0 else { return }

        let waitStartedAt = Date()
        while true {
            if !BookDataSync.fetchAll().isEmpty { return }
            guard Self.shouldContinueWaitingForFreshInstallRace(
                now: Date(),
                waitStartedAt: waitStartedAt,
                hardCap: freshInstallGraceWindow,
                quietPeriod: freshInstallQuietPeriod,
                lastSyncEventAt: lastSyncEventAtProvider()
            ) else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(freshInstallPollInterval, 0.01) * 1_000_000_000))
        }
    }

    /// C2の適応的待機を、まだ続けるべきかどうかを判定する純粋関数。
    ///
    /// - hardCapを過ぎていれば、どのような状況でも待機を終える(安全側のフォールバック。
    ///   固定5秒だった以前の挙動と同じ「最後は必ず進む」という性質を保つ)
    /// - lastSyncEventAtがnil(この起動でまだCloudKitイベントを一度も観測していない)場合は、
    ///   待機開始時刻を基準に静穏期間を測る
    /// - lastSyncEventAtがある場合は、そこからquietPeriod秒経っていなければ
    ///   「まだ同期活動が続いている可能性がある」として待ち続ける
    ///
    /// internal公開の理由: 実際の非同期待機・CloudKit接続を伴わずに、単体テストから
    /// Dateを直接合成して各分岐を決定的に検証できるようにするため(decideMainBookCreationと
    /// 同じ理由)。
    static func shouldContinueWaitingForFreshInstallRace(
        now: Date,
        waitStartedAt: Date,
        hardCap: TimeInterval,
        quietPeriod: TimeInterval,
        lastSyncEventAt: Date?
    ) -> Bool {
        guard now.timeIntervalSince(waitStartedAt) < hardCap else { return false }
        let quietSince = lastSyncEventAt ?? waitStartedAt
        return now.timeIntervalSince(quietSince) < quietPeriod
    }

    /// エラー画面の「再試行」から呼ぶ。
    func retry() {
        Task { await runIfNeeded() }
    }
}
