import Combine
import CoreData
import Foundation

// MARK: - iCloud同期のユーザー設定・状態管理
//
// NSPersistentCloudKitContainerはストアをロードする瞬間にしかCloudKitミラーリングの有無を
// 決められず、かつロード済みのコンテナに対して動的にON/OFFする公開APIは無い。加えてこの
// コードベース自身が「同一プロセス内でNSPersistentCloudKitContainerを何度も作り直すと、
// ミラーリングデリゲートのエクスポート活動登録が競合し低確率で内部破壊を起こす」ことを
// 実測済み（CoreDataStack.swiftのコメント参照）。そのため、アプリ実行中にPersistent Storeを
// 差し替えることはしない設計にする。
//
// 方式：ユーザーがToggleを変更したら希望値(isUserEnabled)を即座にUserDefaultsへ保存するだけに
// とどめ、実際にCloudKit接続の有無を切り替えるのは「次回アプリ起動時」。今回のプロセスが
// 実際どちらで起動したか(currentSessionEnabled)と希望値が食い違っていれば、
// 「変更は次回アプリ起動時に反映されます」とUIに表示する(アプリ側から強制終了はしない)。
final class CloudSyncSettings: ObservableObject {
    static let shared = CloudSyncSettings()

    enum State: Equatable {
        case disabled
        case enabling
        case enabled
        case disabling
        case error(String)
    }

    // internal公開の理由: テストから「キーが存在しない状態(＝既存ユーザー/新規インストール直後)」
    // を直接作り出して既定値の分岐を検証できるようにするため(cloudStoreDescriptionと同じ理由)。
    static let isUserEnabledKey = "CloudSyncSettings.isUserEnabled"

    /// CoreDataStackの初期化中に呼ぶための、シングルトンを介さない直接読み取り。
    /// CloudSyncSettings.shared.init()はCoreDataStack.shared.isCloudSyncActiveを参照するため、
    /// CoreDataStack自身の初期化中にCloudSyncSettings.sharedへ触れると循環初期化になる。
    ///
    /// デフォルト(キーが存在しない場合)はtrue。既存ユーザーはこのトグルが存在する前から
    /// CloudKit同期が常時有効だったため、アップデート後に突然OFFになるのを防ぐ。新規インストールも
    /// 同じ既定値でON（Apple標準アプリのiCloud同期系機能――設定でOFFにできる前提で
    /// デフォルトはON、という方針に合わせた）。
    static func isUserEnabledPreference() -> Bool {
        (UserDefaults.standard.object(forKey: isUserEnabledKey) as? Bool) ?? true
    }

    /// 起動直後・希望値変更直後にUIへ即座に反映するための値。didSetで即UserDefaultsへ保存する
    /// （実際のCloudKit接続切り替えは次回起動時、CoreDataStackの初期化経路で行われる）。
    @Published var isUserEnabled: Bool {
        didSet {
            guard isUserEnabled != oldValue else { return }
            UserDefaults.standard.set(isUserEnabled, forKey: Self.isUserEnabledKey)
        }
    }

    /// 今回のプロセスが実際にCloudKitを有効にしてCoreDataStackをロードしたかどうか。
    /// CoreDataStack.shared.isCloudSyncActiveをそのまま保持し、起動時に1回だけ確定・以後不変。
    let currentSessionEnabled: Bool

    /// 今回のセッションで、CloudKitの初回setup/import/exportのいずれかが1回でも成功したか。
    @Published private(set) var hasCompletedInitialSync = false

    /// 直近で観測したCloudKitイベントのエラー(あれば)。次の成功イベントでnilに戻る。
    @Published private(set) var lastErrorMessage: String?

    /// 直近でCloudKitの同期イベント(setup/import/export)が完了した時刻(成否問わず)。
    ///
    /// 【複数端末の同時初回起動対策】hasCompletedInitialSyncは「初回importが一度でも
    /// 成功したか」を示す一方向フラグ(一度trueになると以後は常にtrue)で、2回目以降の
    /// incremental import/exportが起きても変化しない。CoreDataStartupCoordinatorの
    /// 起動時競合緩和待機は「CloudKit側でまだ何か同期活動が続いているか」を区別する
    /// 必要があり、そのためにイベントの発生そのもの(成否問わず、都度)を記録する。
    @Published private(set) var lastSyncEventAt: Date?

    /// 希望値(isUserEnabled)と実際の起動状態(currentSessionEnabled)が食い違っている
    /// ＝変更を反映するには次回起動が必要、の意味。純粋関数に切り出し、単体テストから
    /// シングルトンを介さず直接検証できるようにしている。
    var needsRestartToApply: Bool {
        Self.needsRestart(isUserEnabled: isUserEnabled, currentSessionEnabled: currentSessionEnabled)
    }

    static func needsRestart(isUserEnabled: Bool, currentSessionEnabled: Bool) -> Bool {
        isUserEnabled != currentSessionEnabled
    }

    /// UI表示用の集約状態。純粋な値の組み合わせから導出するため、単体テストから
    /// computeState(_:)を直接呼んで各分岐を検証できる(シングルトンの生成をやり直さずに済む)。
    var state: State {
        Self.computeState(
            isUserEnabled: isUserEnabled,
            currentSessionEnabled: currentSessionEnabled,
            hasCompletedInitialSync: hasCompletedInitialSync,
            lastErrorMessage: lastErrorMessage
        )
    }

    static func computeState(
        isUserEnabled: Bool, currentSessionEnabled: Bool, hasCompletedInitialSync: Bool, lastErrorMessage: String?
    ) -> State {
        if let lastErrorMessage { return .error(lastErrorMessage) }
        if !currentSessionEnabled { return .disabled }
        if !isUserEnabled { return .disabling }
        return hasCompletedInitialSync ? .enabled : .enabling
    }

    // MARK: - CloudKit初回import待ち（BookMigrationService等がCloudKit取り込み完了前に
    // 「データ無し」と誤判定するのを防ぐために使う。詳細はBookMigrationService.swift参照）

    enum InitialImportState: Equatable {
        /// このセッションはCloudKit無効で起動している(トグルOFF、テスト等)。import自体が発生しない。
        case notApplicable
        /// CloudKit有効で起動しているが、まだ1件も成功イベントを観測していない
        /// (＝ローカルにCloudKit由来のデータがまだ反映されていない可能性がある、判断を保留すべき状態)。
        case pending
        /// 少なくとも1回、setup/import/exportのいずれかが成功した
        /// (＝この時点でローカルに反映されているはずのCloudKitデータは反映済みとみなせる)。
        case completed
    }

    var initialImportState: InitialImportState {
        Self.computeInitialImportState(currentSessionEnabled: currentSessionEnabled, hasCompletedInitialSync: hasCompletedInitialSync)
    }

    static func computeInitialImportState(currentSessionEnabled: Bool, hasCompletedInitialSync: Bool) -> InitialImportState {
        guard currentSessionEnabled else { return .notApplicable }
        return hasCompletedInitialSync ? .completed : .pending
    }

    /// 起動シーケンスから呼ぶ。CloudKit無効ならすぐ`.notApplicable`を返す。有効な場合は
    /// 最初の成功イベントが来るまで、または`timeout`秒経つまで待つ(タイムアウトはネットワーク
    /// 不調・iCloud未サインイン等で永久に成功イベントが来ないケースへの安全弁で、その場合は
    /// `.pending`のまま返す＝呼び出し元は「まだ確信が持てない」として保守的に振る舞うこと)。
    /// エラーイベントを観測した場合も同様に`.pending`のまま返す(失敗した＝成功もしていないため)。
    func waitForInitialImportSettled(timeout: TimeInterval, pollInterval: TimeInterval = 0.2) async -> InitialImportState {
        guard currentSessionEnabled else { return .notApplicable }
        if hasCompletedInitialSync { return .completed }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasCompletedInitialSync { return .completed }
            try? await Task.sleep(nanoseconds: UInt64(max(pollInterval, 0.01) * 1_000_000_000))
        }
        return hasCompletedInitialSync ? .completed : .pending
    }

    private var eventObserver: NSObjectProtocol?

    private init() {
        isUserEnabled = Self.isUserEnabledPreference()
        currentSessionEnabled = CoreDataStack.shared.isCloudSyncActive
        if currentSessionEnabled {
            observeCloudKitEvents()
        }
    }

    deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    private func observeCloudKitEvents() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: CoreDataStack.shared.container,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            self?.apply(Self.outcome(forEventEndDate: event.endDate, errorDescription: event.error?.localizedDescription))
        }
    }

    enum SyncOutcome: Equatable {
        case succeeded
        case failed(String)
    }

    /// NSPersistentCloudKitContainer.Eventの該当プロパティをそのまま渡す想定の純粋関数
    /// (システム型に依存しないため、単体テストから合成したendDate/errorDescriptionで直接検証できる)。
    /// nilを返す場合は「まだ進行中のイベントなので何もしない」の意味。
    static func outcome(forEventEndDate endDate: Date?, errorDescription: String?) -> SyncOutcome? {
        guard endDate != nil else { return nil }
        if let errorDescription { return .failed(errorDescription) }
        return .succeeded
    }

    func apply(_ outcome: SyncOutcome?) {
        switch outcome {
        case nil:
            break
        case .succeeded:
            lastSyncEventAt = Date()
            lastErrorMessage = nil
            hasCompletedInitialSync = true
        case .failed(let message):
            lastSyncEventAt = Date()
            lastErrorMessage = message
        }
    }
}
