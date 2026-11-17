import CoreData

// MARK: - Core Data永続化スタック（CloudKit Step 2A: Cloud/Local 2ストア構成）
//
// Phase 1でSwiftDataは完全に削除され、Core Dataがこのアプリの唯一の読み書き経路。
// CloudKit Step 1でモデルにCloud（ユーザーが編集する13エンティティ）/Local（DailySnapshot/
// MonthlySnapshot/AnalysisMonthlySnapshot/AssetGraphCacheDataの4エンティティ）の
// 2 Configurationを追加した。Step 2Aでは、そのConfigurationに対応する実際の2ストア構成
// （Kakeibo3Cloud.sqlite / Kakeibo3Local.sqlite）を`NSPersistentCloudKitContainer`で開く。
//
// 既存Kakeibo3.sqliteのユーザーデータをCloud/Localへ実移行する処理はStep 2Bで実装済み
// （kakeibo3/Migration/Split/参照）。remote change受信後のSnapshot再構築はRemoteChangeObserver
// （kakeibo3/Services/RemoteChangeObserver.swift）で実装済み。
//
// 本番経路（デフォルトのinit(inMemory:storeURL:)）のCloud store（cloudKitContainerOptions）は、
// XCTest実行中でないことに加え、ユーザーが設定画面の「iCloud同期」トグルでONにしているかどうか
// （CloudSyncSettings.isUserEnabledPreference()、既定はtrue）で決まる。NSPersistentCloudKit
// ContainerはストアをロードするタイミングでしかCloudKit接続の有無を決められないため、トグル変更は
// 次回起動時に反映される（アプリ実行中にストアを差し替えることはしない。詳細は
// CloudSyncSettings.swiftのコメント参照）。
//
// エンティティのCore Data上の名前（.xcdatamodeldのentity name＝CloudKit同期時のレコード型名）は
// プレフィックス無し（ExpenseData等）。ただしSwiftの生成クラス名（representedClassName）は
// 各モデルのドメイン用struct（ExpenseData等、Views/ViewModelsが直接触る値型）と同じモジュール内で
// 名前が衝突するため、意図的にCDプレフィックス付き（CDExpenseData等）のまま残している
// （*DataSync.swiftがCDExpenseData ⇔ ExpenseData(struct)の変換を担う）。
final class CoreDataStack {
    /// 宣言時の初期値はあえて`inMemory: true`にしている（ディスクもCloudKitも一切使わない、
    /// 即座に終わる構成）。Swiftの`static var`は最初に触れた瞬間（読み取りだけでなく、
    /// 他の値で上書きする代入であっても）に宣言時の初期値を1回構築するため、もしここが
    /// 本番と同じ`CoreDataStack()`（実CloudKit接続）だった場合、CoreDataStartupCoordinatorが
    /// `CoreDataStack.shared = stack`で初めて触れた瞬間に、使われることのない実CloudKit
    /// 接続インスタンスが無駄に（かつCloudKit側のスキーマ初期化がネットワーク越しに
    /// 遅延・停止した場合は起動そのものをブロックしてしまう形で）生成されてしまう
    /// （実機・実CloudKit接続でのみ再現し、どのテストでも検出できなかった不具合として発見）。
    /// この値は本番・テストいずれでも実際に使われる前に必ず上書きされるため、
    /// 高速・無害な構成で十分。
    static var shared = CoreDataStack(inMemory: true)

    let container: NSPersistentCloudKitContainer

    /// このインスタンスが実際にCloudKitミラーリングを有効にしてロードされたかどうか。
    /// テスト用・Migration用の全経路（inMemory/storeURL/throwingStoreURL）は常にfalse固定
    /// （CloudKitへ絶対につながないという既存の原則をそのまま維持する）。本番経路（デフォルトの
    /// init(inMemory:storeURL:)）だけが、XCTest実行中でなくユーザー設定（iCloud同期トグル、
    /// CloudSyncSettings参照）がONの場合にtrueになる。CloudSyncSettings.sharedはこの値を
    /// 起動時に1回だけ読んで「今回のセッションの実際の状態」として保持する。
    let isCloudSyncActive: Bool

    // MARK: - Cloud/Local構成の定数

    static let cloudKitContainerIdentifier = "iCloud.com.kusumoto.kakeibo3"
    static let cloudConfigurationName = "Cloud"
    static let localConfigurationName = "Local"
    static let cloudStoreFileName = "Kakeibo3Cloud.sqlite"
    static let localStoreFileName = "Kakeibo3Local.sqlite"
    static let transactionAuthor = "app"

    // XCTestConfigurationFilePathは、Xcodeがテストホストとしてアプリを起動する時だけ
    // 環境変数に設定される(実際のユーザー起動では絶対に設定されない、Appleの
    // テストランナー自体が設定する値)。テストホスト起動時、`Kakeibo3App.swift`の通常の
    // 起動処理が`CoreDataStack.shared`へ最初に触れた瞬間に(各QARegressionTestCase.setUp
    // による差し替えより前に、プロセスにつき1回だけ)実CloudKit接続のNSPersistentCloudKit
    // Containerが生成されてしまう問題を実測で確認した。CloudKitアカウント無しの環境でも、
    // NSPersistentCloudKitContainerはミラーリングデリゲートのバックグラウンドな
    // エラー回復ループをプロセスの生存中ずっと走らせ続けるらしく、これが無関係な別の
    // Core Data操作(例: AssetGraphCacheServiceのcontext.perform)と低確率で衝突し、
    // Core Data内部を破壊してテストを不安定にしていた(390回超のフルスイート連続実行で
    // 実測・再現・原因特定済み)。テストホスト起動時は本番の2ストア構成自体は維持しつつ、
    // CloudKit接続だけを無効化することでこれを回避する(実際のユーザー起動には一切影響しない)。
    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 本番経路（デフォルトのinit(inMemory:storeURL:)、および
    /// makeProductionStack(directory:)）でCloud storeにcloudKitContainerOptionsを
    /// 設定するかどうかの判定。1箇所にまとめ、両者が食い違わないようにする。
    private static func shouldEnableCloudKitForProductionStack() -> Bool {
        !isRunningUnderXCTest && CloudSyncSettings.isUserEnabledPreference()
    }

    /// CoreDataStartupCoordinator専用。Split Migrationが実際に書き込んだディレクトリと
    /// 同じ場所でCloud/Localストアを開く(デフォルトのinit(inMemory:storeURL:)は常に
    /// NSPersistentContainer.defaultDirectoryURL()という固定パスしか見ないため、
    /// テストでSplit Migration先を差し替えても追従できない。本番では
    /// NSPersistentContainer.defaultDirectoryURL()と一致するため挙動は変わらない)。
    /// 判定ロジック(isRunningUnderXCTest・CloudSyncSettingsのユーザー設定)は
    /// デフォルトinitの本番分岐と共通のshouldEnableCloudKitForProductionStack()を使う。
    /// ロード失敗（ストア破損等）・タイムアウト（CloudKit有効時、スキーマ初期化等の
    /// ネットワーク処理がstoreLoadTimeout秒以内に終わらない場合）のいずれもthrowする。
    /// CoreDataStartupCoordinatorが受け取り、既存の再試行可能なエラー画面へ安全に落とす
    /// （以前はここでfatalErrorしていたため、タイムアウトしても画面はハングしたまま
    /// 無反応に見え、実際には復旧不能なクラッシュへ向かっていた）。
    static func makeProductionStack(directory: URL) throws -> CoreDataStack {
        let enableCloud = shouldEnableCloudKitForProductionStack()
        return try CoreDataStack(cloudLocalDirectory: directory, enableCloudKit: enableCloud, enableHistoryTracking: true)
    }

    // NSPersistentContainer(name:)だけを呼ぶと、呼ぶたびに.momdをディスクから探して
    // NSManagedObjectModelを再生成する。テストのようにCoreDataStackを何百回も作り直す
    // 状況では、同じエンティティ名（CDBookData等）を持つモデルインスタンスが複数同時に
    // 存在することになり、「+[CDBookData entity] Failed to find a unique match for an
    // NSEntityDescription to a managed object subclass」という実行時エラーの原因になる。
    // モデルはプロセス内で1つだけロードし、全CoreDataStackインスタンスで使い回す。
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let modelURL = Bundle.main.url(forResource: "Kakeibo3", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Could not load Kakeibo3 Core Data model")
        }
        return model
    }()

    /// - Parameters:
    ///   - inMemory: テスト用。trueの場合はディスクに書き込まない
    ///     `NSInMemoryStoreType`の単一ストアを使い、テストごとに独立した状態を作れるようにする。
    ///     Cloud/Local全17エンティティを1ストアにまとめて扱う（Step 1以前と同じ挙動）。
    ///     CloudKitには絶対につながない（`cloudKitContainerOptions`を明示的にnilにする）。
    ///   - storeURL: テスト用・Migration用。指定すると実ディスク上のSQLiteストアをそのURLに
    ///     単一ストアとして作成する。同じURLを指して2回`CoreDataStack`を作り直すことで、
    ///     「アプリを終了して再起動し、同じストアを開き直す」状況を`inMemory`では検証できない
    ///     範囲まで再現できる。こちらもCloudKitには絶対につながない。
    ///     どちらも指定しない場合（本番の実際の起動経路）は、Cloud/Local 2ストア構成
    ///     （`NSApplicationSupportDirectory`配下、Cloud側だけCloudKit同期を有効化）を開く。
    ///
    ///   ロード失敗時はfatalErrorする。アプリの起動時にストアが開けないのは復旧不能なため
    ///   （移行フローなど、失敗を例外として受け取って旧データを守りたい場面は
    ///   `init(throwingStoreURL:)`を使う）。
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        do {
            if inMemory || storeURL != nil {
                container = try Self.makeSingleStoreContainer(inMemory: inMemory, storeURL: storeURL)
                isCloudSyncActive = false
            } else {
                let enableCloud = Self.shouldEnableCloudKitForProductionStack()
                container = try Self.makeCloudLocalContainer(
                    baseDirectory: NSPersistentContainer.defaultDirectoryURL(),
                    enableCloudKit: enableCloud
                )
                isCloudSyncActive = enableCloud
            }
        } catch {
            fatalError("Could not load Core Data store: \(error)")
        }
    }

    enum LoadError: Error {
        case failed(Error)
        case timedOut
    }

    /// 移行フロー専用。ストアのロード失敗をfatalErrorさせず例外として受け取りたい場面
    /// （一時Core Dataストアの生成・再オープンなど）で使う。既存の`init(inMemory:storeURL:)`の
    /// 挙動（fatalError）は変更しない。単一ストア・CloudKit接続無し（Migration専用の
    /// ローカル一時/検証ストアがCloudKit同期を試みることは絶対に無いようにする）。
    init(throwingStoreURL storeURL: URL) throws {
        container = try Self.makeSingleStoreContainer(inMemory: false, storeURL: storeURL)
        isCloudSyncActive = false
    }

    /// 本番と同じCloud/Local 2ストア構成を、指定した任意のディレクトリ上で開く。
    /// テスト用途（一時ディレクトリでStep 2Aの2ストア構成そのものを検証する）に加え、
    /// Step 2B移行パイプラインが一時ストア・本番ストアを問わず同じ2ストア構成を
    /// 組み立てるための共通の入口としても使う（本番ではbaseDirectoryに
    /// `NSPersistentContainer.defaultDirectoryURL()`を渡す`init(inMemory:storeURL:)`の
    /// デフォルト経路と同じ構成になる）。
    ///
    /// - Parameter enableCloudKit: falseにすると、Cloud storeにも`cloudKitContainerOptions`を
    ///   設定せず(Local同様nilのまま)、Configuration分割によるEntity振り分け・
    ///   persistent history tracking等の構成だけを検証できるようにする。
    ///   `NSPersistentCloudKitContainer`のCloudKitミラーリング機構は本来「プロセス内で
    ///   長時間・1個だけ」動かす前提の設計で、同一プロセス内で短命なインスタンスを
    ///   何十個も連続生成・破棄すると(テストやMigrationパイプラインでの検証がまさにこれ)、
    ///   ミラーリングデリゲートのエクスポート活動登録が競合し、無関係な別のCore Data操作まで
    ///   巻き込んで低確率に内部破壊を起こすことを実測で確認した。本番の実際の起動経路
    ///   （`init(inMemory:storeURL:)`のデフォルト分岐、プロセス内で1個だけ生成される）は
    ///   常にtrueで呼ぶため影響を受けない。テスト・Migrationパイプラインからは、
    ///   実際にCloudKit optionの値そのものを検証する場合を除き、falseを渡すこと。
    /// - Parameter enableHistoryTracking: persistent history tracking / remote change通知を
    ///   実際に有効化するかどうか。これらのオプション自体もCloudKitとは独立に実コストを持ち
    ///   (保存ごとの履歴レコード生成等)、同一テストプロセス内で本番相当の2ストアを
    ///   何十回も連続生成すると、それだけで無関係な別テストのCore Data操作を巻き込んで
    ///   低確率にプロセスを不安定化させることを実測で確認した。「history tracking自体の
    ///   設定を検証するテスト」以外は既定のtrueのままにせず、明示的にfalseを渡すこと。
    init(
        cloudLocalDirectory directory: URL, enableCloudKit: Bool = true, enableHistoryTracking: Bool = true
    ) throws {
        container = try Self.makeCloudLocalContainer(
            baseDirectory: directory, enableCloudKit: enableCloudKit, enableHistoryTracking: enableHistoryTracking
        )
        isCloudSyncActive = enableCloudKit
    }

    // MARK: - 単一ストア構成（テスト用in-memory・テスト用実SQLite・Migration用一時/検証ストア）
    //
    // これらは「CloudKitに絶対つながない、ローカル専用の素のストア」として扱う。
    // cloudKitContainerOptionsは未設定でも元々nilだが、意図を明確にするため明示的にnilを代入する。
    // Configurationも指定しない（nil = 「Default」扱いで、Cloud/Local 17エンティティ全てを
    // 1ストアにまとめて読み書きする、Step 1以前と同じ挙動を維持する）。

    private static func makeSingleStoreContainer(inMemory: Bool, storeURL: URL?) throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "Kakeibo3", managedObjectModel: Self.managedObjectModel)

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else if let storeURL {
            description = NSPersistentStoreDescription(url: storeURL)
        } else {
            description = NSPersistentStoreDescription()
        }
        description.shouldAddStoreAsynchronously = false
        description.cloudKitContainerOptions = nil
        container.persistentStoreDescriptions = [description]

        try loadStoresSynchronously(container)
        configureViewContext(container.viewContext)
        return container
    }

    // MARK: - Cloud/Local 2ストア構成（本番、およびテストで同一構成を検証する経路）
    //
    // Cloud: Configuration分割済みの13エンティティ（ユーザーが編集する永続データ）。
    //   cloudKitContainerOptionsを設定し、CloudKitへ同期する。
    // Local: Configuration分割済みの4エンティティ（DailySnapshot/MonthlySnapshot/
    //   AnalysisMonthlySnapshot/AssetGraphCacheData、いずれもCloud側の元データから
    //   再生成可能な派生データ）。cloudKitContainerOptionsはnilのまま、CloudKitへは繋がない。
    // 両ストアともpersistent history tracking・remote change通知を有効化する
    // （Step 2AではまだSnapshotRebuildQueue等との連携は実装しないが、Step 2以降で
    // remote change検知に使うための土台として、この時点で両方有効にしておく）。

    private static func makeCloudLocalContainer(
        baseDirectory: URL, enableCloudKit: Bool, enableHistoryTracking: Bool = true
    ) throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "Kakeibo3", managedObjectModel: Self.managedObjectModel)
        container.persistentStoreDescriptions = [
            cloudStoreDescription(baseDirectory: baseDirectory, enableCloudKit: enableCloudKit, enableHistoryTracking: enableHistoryTracking),
            localStoreDescription(baseDirectory: baseDirectory, enableHistoryTracking: enableHistoryTracking),
        ]

        try loadStoresSynchronously(container)
        configureViewContext(container.viewContext)
        return container
    }

    static func cloudStoreURL(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(cloudStoreFileName)
    }

    static func localStoreURL(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(localStoreFileName)
    }

    /// internal公開の理由: テストが実際にストアをロードせずに(＝CloudKitミラーリング機構を
    /// 起動せずに)description自体の設定値(configuration/cloudKitContainerOptions等)だけを
    /// 検証できるようにするため。同一プロセス内で本番相当のCloudKit接続を複数生成すると
    /// ミラーリングデリゲートのエクスポート活動登録が競合するため(実測で確認済み)、
    /// 「本当にロードする必要がある検証」以外はこちらを直接呼ぶこと。
    static func cloudStoreDescription(
        baseDirectory: URL, enableCloudKit: Bool, enableHistoryTracking: Bool = true
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: cloudStoreURL(baseDirectory: baseDirectory))
        description.configuration = cloudConfigurationName
        description.shouldAddStoreAsynchronously = false
        description.cloudKitContainerOptions = enableCloudKit
            ? NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            : nil
        if enableHistoryTracking {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        return description
    }

    /// internal公開の理由はcloudStoreDescription(baseDirectory:enableCloudKit:)と同じ。
    static func localStoreDescription(baseDirectory: URL, enableHistoryTracking: Bool = true) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: localStoreURL(baseDirectory: baseDirectory))
        description.configuration = localConfigurationName
        description.shouldAddStoreAsynchronously = false
        description.cloudKitContainerOptions = nil
        if enableHistoryTracking {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        return description
    }

    // MARK: - 共通ヘルパー

    /// loadPersistentStores完了を待つ上限。ローカルストアのみの読み込みは通常一瞬で終わるが、
    /// CloudKit有効時はこの呼び出しの内部でCloudKit側のスキーマ初期化（新規Entity追加後の
    /// 初回スキーマ拡張等）がネットワーク越しに走ることがあり、その完了待ちでコールバックが
    /// 遅延する場合がある（実機・実CloudKit接続でのみ再現し、enableCloudKit: falseの
    /// テストでは再現しない）。無期限に待つと起動そのものが永久にブロックされるため、
    /// CloudSyncSettings.waitForInitialImportSettled(timeout:)やAssetGraphCacheServiceの
    /// タイムアウトと同じ考え方で、一定時間で確実に失敗として返す。
    private static let storeLoadTimeout: TimeInterval = 20

    // loadPersistentStoresは非同期で呼ばれる可能性があり、完了を待たずに
    // CoreDataStack.sharedへアクセスすると、ストア未接続のcontextへ保存を試みて
    // 静かに失敗する（呼び出し側はtry?で握りつぶすため気づきにくい）。
    // ローカルストアの読み込みは通常一瞬で終わるため、
    // ここでセマフォを使って全ストア（Cloud/Localの2つ、または単一ストアの1つ）の
    // 読み込み完了を同期的に待ってからinitを返す。
    private static func loadStoresSynchronously(_ container: NSPersistentCloudKitContainer) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var remaining = container.persistentStoreDescriptions.count
        var firstError: Error?
        container.loadPersistentStores { _, error in
            lock.lock()
            if firstError == nil { firstError = error }
            remaining -= 1
            let isDone = remaining == 0
            lock.unlock()
            if isDone { semaphore.signal() }
        }
        guard semaphore.wait(timeout: .now() + storeLoadTimeout) == .success else {
            throw LoadError.timedOut
        }

        if let firstError {
            throw LoadError.failed(firstError)
        }
    }

    private static func configureViewContext(_ context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = Self.transactionAuthor
    }

    // MARK: - 書き込みトランザクション
    //
    // 【スレッド閉じ込め違反の根本修正・再発防止メモ】
    // viewContextは`NSManagedObjectContext.mainQueueConcurrencyType`固定（Appleの仕様上
    // 変更不可）で、その専用キュー（実質メインスレッド）以外から直接触ると、Core Data内部の
    // 変更通知管理（NSSet相当）を破壊し、捕捉不能な NSInvalidArgumentException
    // （-[__NSCFSet addObject:]: attempt to insert nil）やEXC_BAD_ACCESSで低確率にクラッシュする。
    // 以前のperformAndSave(_:)はこのcontextを素通しで直接触っており、「呼び出し元は常に
    // メインスレッド/MainActorのはず」という前提だけに頼っていた。実際には
    // QARegressionTestFactory.seedStandardData（async テスト関数から呼ばれ、await復帰後の
    // 再開スレッドはSwift Concurrencyの規約上保証されない）や、TestDataView経由の
    // TestDataGenerator/PerformanceTestDataGenerator（Task.detachedから明示的に呼ばれる設計）が
    // この前提を破っており、実測でCategoryDataSync.insert/PaymentMethodSettingDataSync.insert等の
    // 呼び出し時にクラッシュを再現・確認した（AssetGraphCacheServiceを2ae54f3で直した時と
    // 同型・別箇所の未修正バグ）。
    //
    // 修正方針：
    // 1. 同期版performAndSave(_:)は`context.performAndWait`でcontextの専用キューへ必ず
    //    処理を委譲するようにし、呼び出し元のスレッドによらず安全にする（メインスレッド/
    //    MainActorから呼んだ場合は、既にそのキュー上にいるため追加のディスパッチなしで
    //    インラインに実行される＝既存の同期呼び出し元に速度面の悪影響は無い）。
    //    Views/ViewModelsなどMainActor上の同期呼び出し元はこちらを使い続けてよい。
    // 2. ただし、既にasync文脈にいる呼び出し元が同期版を使うと、`performAndWait`が
    //    Swift Concurrencyのcooperativeスレッドプールのスレッドをブロックしてしまう
    //    （Task.detachedもこのプールを使うため対象。AssetGraphCacheServiceの旧実装
    //    「Task.detached + performAndWait」がまさにこの理由で危険とされ2ae54f3で廃止された
    //    アンチパターンと同じ）。そのため、async文脈向けに`context.perform`（非ブロッキングな
    //    非同期版、iOS 15+）を使う新API `performAndSave<T>(_:) async throws -> T` を用意する。
    //    QARegressionTestFactoryの新しい非同期版シード関数（*Async）はこちらを使う。
    // 3. 保存失敗時はどちらの版もrollbackしてから返す／投げる（以前は`try? context.save()`で
    //    失敗を握りつぶし、コンテキストが不整合な半保存状態のまま次の変更が積み重なる余地が
    //    あった）。
    // 4. どちらの版も、work/changesクロージャの外へNSManagedObjectを persist しない
    //    （呼び出し元は戻り値に値型のみ使うこと。`T`がNSManagedObjectやそれを保持する型の場合、
    //    context外のスレッドから触れると同じスレッド閉じ込め違反を再発するため使用禁止）。

    /// MainActor（View/ViewModelからの同期呼び出し）向け。
    /// 内部で`context.performAndWait`を使うため、呼び出し元のスレッドによらず安全。
    /// 既にasync文脈にいる場合はcooperativeスレッドプールを塞がないよう、
    /// 代わりに`performAndSave(_:) async throws -> T`を使うこと。
    func performAndSave(_ changes: (NSManagedObjectContext) -> Void) {
        let context = container.viewContext
        context.performAndWait {
            changes(context)
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                context.rollback()
            }
        }
    }

    /// `performAndSave(_:)`と同じ挙動だが、`context.save()`が実際に成功したかを呼び出し元へ
    /// 返す（既存の`performAndSave(_:)`は失敗時にrollbackするだけで呼び出し元には一切伝えない
    /// ため、支出/収入/振替の保存のように「保存が成功したとUIに表示する前に、本当に永続化
    /// できたかを確認したい」呼び出し元向けに用意する）。
    /// - Returns: 変更が無かった場合、または保存に成功した場合はtrue。保存が失敗した場合のみfalse。
    @discardableResult
    func performAndSaveChecked(_ changes: (NSManagedObjectContext) -> Void) -> Bool {
        let context = container.viewContext
        var succeeded = true
        context.performAndWait {
            changes(context)
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                context.rollback()
                succeeded = false
            }
        }
        return succeeded
    }

    /// async文脈向け。`context.perform`（非同期版、iOS 15+）でcontextの専用キューへ
    /// 非ブロッキングにdispatchするため、呼び出し元のスレッド（cooperativeスレッドプール等）を
    /// 塞がない。保存に失敗した場合はrollbackしてからエラーを投げる。
    /// - Important: `work`から`NSManagedObject`（やそれを内包する値）をcontextの外へ
    ///   返さないこと。戻り値`T`はcontextのキュー外でも安全な値型に限る。
    func performAndSave<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = container.viewContext
        return try await context.perform {
            let result = try work(context)
            guard context.hasChanges else { return result }
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            return result
        }
    }
}
