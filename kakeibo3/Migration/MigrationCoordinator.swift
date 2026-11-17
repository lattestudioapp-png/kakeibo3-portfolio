import Foundation
import Combine

// MARK: - 起動シーケンスからMigrationBootstrapを呼び出す唯一の入口
//
// Kakeibo3App側の画面切り替え(移行中/失敗/通常)専用。CoreDataStack.sharedには
// 一切触れない(MigrationBootstrap自体がCoreDataStack.sharedを参照しない設計のため、
// ここも同様に守る)。重いファイルI/O・データ変換はTask.detachedでバックグラウンドへ
// 逃がし、@Published stateの更新だけを@MainActor上で行う。

@MainActor
final class MigrationCoordinator: ObservableObject {

    enum State: Equatable {
        /// 旧ストアの有無・移行済みかどうかを確認している(ごく短時間)
        case checking
        /// 旧SwiftDataストアからCore Dataへ実際に移行している
        case migrating
        /// 移行が成功した(今回実際に移行した、または既に移行済みと確認できた)
        case completed
        /// 旧SwiftDataストアが存在しない(新規インストール)。移行不要。
        case notNeeded
        /// 移行に失敗した。既存データは変更していない。
        case failed(String)
    }

    @Published private(set) var state: State = .checking

    /// 通常画面へ進んでよいか(completed/notNeededのどちらか)。
    var isReady: Bool {
        switch state {
        case .completed, .notNeeded: return true
        case .checking, .migrating, .failed: return false
        }
    }

    private var isRunning = false

    /// 実アプリからはこちらを呼ぶ(実Application Support / 実UserDefaults.standardを使う)。
    func runIfNeeded() async {
        await runIfNeeded(
            legacyPaths: SwiftDataLegacyReader.legacyStorePaths(),
            workDirectory: FileManager.default.temporaryDirectory,
            productionDirectory: SwiftDataLegacyReader.applicationSupportDirectory(),
            userDefaults: .standard
        )
    }

    /// テスト用:旧ストア・作業ディレクトリ・本番ディレクトリ・UserDefaultsを直接指定して実行する。
    func runIfNeeded(
        legacyPaths: SwiftDataLegacyReader.LegacyStorePaths?,
        workDirectory: URL,
        productionDirectory: URL?,
        userDefaults: UserDefaults
    ) async {
        guard !isRunning else {
            DiagnosticLog.logReentrancyGuardTriggered(coordinator: "MigrationCoordinator")
            return
        }
        isRunning = true
        DiagnosticLog.logCoordinatorLifecycle(coordinator: "MigrationCoordinator", event: "開始")
        defer {
            isRunning = false
            DiagnosticLog.logCoordinatorLifecycle(coordinator: "MigrationCoordinator", event: "終了 state=\(state)")
        }

        state = .checking

        guard let legacyPaths else {
            state = .notNeeded
            return
        }

        state = .migrating

        guard let productionDirectory else {
            state = .failed("Application Supportディレクトリを取得できません")
            return
        }

        let outcome = await Task.detached(priority: .userInitiated) {
            MigrationBootstrap.migrateAndPromote(
                legacyPaths: legacyPaths, workDirectory: workDirectory,
                productionDirectory: productionDirectory, userDefaults: userDefaults
            )
        }.value

        switch outcome {
        case .notNeeded:
            state = .notNeeded
        case .promoted, .alreadyMigrated:
            state = .completed
        case .tempStoreWriteSucceeded:
            // migrateAndPromote経由ではPhase B1単体の結果は返らないはずだが、
            // 万一発生した場合は安全側に倒して失敗扱いにする(通常画面には進めない)。
            state = .failed("内部エラー: 想定外の移行状態(tempStoreWriteSucceeded)")
        case .failed(let failure):
            state = .failed(String(describing: failure))
        }
    }

    /// エラー画面の「再試行」から呼ぶ。
    func retry() {
        Task { await runIfNeeded() }
    }

    /// テスト用:同じ条件で再試行する。
    func retry(
        legacyPaths: SwiftDataLegacyReader.LegacyStorePaths?,
        workDirectory: URL,
        productionDirectory: URL?,
        userDefaults: UserDefaults
    ) async {
        await runIfNeeded(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
    }
}
