import Foundation

// MARK: - 複数帳簿対応：起動時マイグレーション
//
// BookDataが1件も無ければ「メイン帳簿」を自動作成する。その上で、対象モデルの
// bookId未設定（nil）な行をすべてメイン帳簿に紐づける。「BookDataが存在するか」では
// なく「nilなbookIdの行が残っているか」を毎回チェックすることで、後から新しく
// bookIdを追加したモデル（既にBookDataが存在する端末で追加されたもの）も
// 取りこぼさずバックフィルできる（対象が無ければ何もしない軽い処理）。
// Kakeibo3App.onAppearからSnapshotManager.backfillIfNeeded等より前に呼ぶ。
//
// 帳簿は「ほぼ別アプリ」として扱う方針のため、収入・支出だけでなくカテゴリー・支払い方法・
// 受け取り方法・銀行口座・予算・固定費・定期収入・定期振替・振替もすべて対象にする。
// AssetGraphCacheData（総資産推移キャッシュ）はbookIdを含む複合キーに変わったため、
// バックフィルではなく削除して作り直し（「更新」ボタンで再生成）に任せる。
//
// 【重要・実機で確認された重複バグの再発防止】
// 以前は「BookDataSync.fetchAll()が空 ＝ メイン帳簿を作ってよい」と即断していたが、
// CloudKit同期が有効な端末では、起動直後の時点でCloudKitの初回import
// （別端末・別セッションで既に作られたメイン帳簿等をこのデバイスへ取り込む処理）が
// まだ完了していないことがある。その状態で「空だから作る」と判断すると、直後に
// importが完了した際に既存のメイン帳簿と新しく作ったメイン帳簿が両方残り、
// 帳簿切り替え画面に同名の帳簿が重複表示される（実機で確認済みの不具合）。
// さらに、旧Kakeibo3.sqlite（Split Migration前の単一ストア）がまだ退避されていない
// 状態でも、Split Migrationが完了すればそこから本来のBookが出てくるはずなので、
// ここで先にメイン帳簿を作ってはいけない。
//
// このため「メイン帳簿を新規に作ってよいか」の判定をdecideMainBookCreation(_:)へ切り出し、
// 以下を組み合わせて判定する(A〜Dはユーザー指示のケース分類に対応):
//   A. 完全な新規インストール(旧ストアも無く、CloudKit同期もOFFか、ONでも初回import完了済みで
//      なお0件) → 作ってよい
//   B. Split Migration直後で既にBookが存在する → 既存のものを使う(このパスには来ない)
//   C. 旧Kakeibo3.sqliteがまだ存在する(Split Migration未完了/失敗) → 作らない(待つ)
//   D. CloudKit同期ONで初回import未完了 → 作らない(待つ)。OFFなら作ってよい
//
// 【重要・既知の残課題への対応】
// 上記のA〜Dだけでは閉じられない抜け道があった：CloudKit側の内部resetで
// ローカルの全Bookが一時的に消え、再インポートが終わる前に再起動が挟まると、
// 「initialImportStateは(前回の成功済みイベントにより)既にcompletedなのに、
// existingBooksは(reset直後で)0件」という状態になり、Cの判定に誤って「作ってよい」と
// 判断してしまう。これが実機調査で確認された重複メイン帳簿量産の直接の引き金だった。
//
// このデバイスで一度でもメイン帳簿を確立済みなら(establishedMainBookIdKeyに記録済みなら)、
// 以後は「existingBooksが0件」を二度と「新規作成してよい」の根拠にしない。
// 0件に見える状態は常に「同期側の過渡的な状態」として扱い、新しいメイン帳簿を
// 作るのではなく次回起動まで待つ。重複作成の方が、待ち続けることよりも
// 取り返しのつかない被害(帳簿が割れてデータが迷子になる)が大きいため、
// 「迷ったら作らず待つ」側に倒す。

enum MainBookCreationDecision: Equatable {
    /// 既存のBookをそのまま使う(新規作成しない)
    case useExisting(UUID)
    /// 新しくメイン帳簿を作ってよい
    case createNew
    /// まだ判断材料が揃っていない(Split Migration未完了 or CloudKit初回import未完了)。
    /// 今回のmigrateIfNeeded()は何もせず、次回起動時に再判定する。
    case waitAndRetry
}

enum BookMigrationService {

    /// 一度でも確立されたメイン帳簿のidを永続化するキー。migrateIfNeeded()が
    /// useExisting/createNewのどちらを選んだ場合でも、その結果をここへ書き込む。
    /// 以後は「existingBooksが0件」だけを理由に新規作成することは二度と無い
    /// (decideMainBookCreation内のestablishedMainBookId分岐を参照)。
    static let establishedMainBookIdKey = "BookMigrationService.establishedMainBookId"

    /// 直前に確認したiCloudアカウント(FileManager.ubiquityIdentityToken)を、
    /// NSKeyedArchiverで永続化したDataとして保存するキー。
    ///
    /// 【既知の残課題への対応・iCloudアカウント変更】establishedMainBookIdKeyは
    /// 「この端末で一度でもメイン帳簿を確立したか」だけを記録しており、
    /// 「どのiCloudアカウントの時に確立したか」は見ていなかった。そのため、
    /// 同じ端末でiCloudアカウントをAさん→Bさんに切り替えると、Bさんのアカウントの
    /// CloudKitには何も無い(existingBooksが本当に0件)にもかかわらず、
    /// Aさんの時に確立したestablishedMainBookIdKeyが残っているせいで
    /// 「確立済みだから作らない」と永久にwaitAndRetryし続けてしまう
    /// (本来は安全弁のはずが、別アカウントでは「二度と帳簿を作れない」詰みになる)。
    ///
    /// migrateIfNeeded()は毎回起動時に現在のubiquityIdentityTokenをここに保存した値と
    /// 比較し、変化していれば「アカウントが変わった」と判断してestablishedMainBookIdKeyを
    /// クリアする(hasUbiquityIdentityChanged参照)。これは安全弁を元の状態(未確立)に
    /// 戻すだけであり、既存のBookData・支出・カテゴリー等を一切削除しない
    /// (削除は行わない。decideMainBookCreationの既存の判定ロジックに、まっさらな
    /// 端末と同じ条件で再度判断させるだけ)。
    static let lastKnownUbiquityIdentityTokenDataKey = "BookMigrationService.lastKnownUbiquityIdentityTokenData"

    /// 純粋関数として切り出し、単体テストから各ケースを直接検証できるようにしている。
    /// - Parameter establishedMainBookId: このデバイスで過去に確立済みのメイン帳簿id
    ///   (establishedMainBookIdKeyの値)。まだ一度も確立していなければnil。
    static func decideMainBookCreation(
        existingBooks: [BookData],
        legacyUnifiedStoreExists: Bool,
        cloudSyncActive: Bool,
        initialImportState: CloudSyncSettings.InitialImportState,
        establishedMainBookId: UUID? = nil
    ) -> MainBookCreationDecision {
        if let existingMain = existingBooks.first(where: { $0.isMain }) ?? existingBooks.min(by: { $0.sortOrder < $1.sortOrder }) {
            return .useExisting(existingMain.id)
        }

        // ここに来る時点でexistingBooksは空。

        // C: Split Migrationがまだ旧ストアを退避しきっていない(未実行 or 失敗)。
        // 先にメイン帳簿を作ると、後でSplit Migrationが走った時に重複の元になる。
        guard !legacyUnifiedStoreExists else { return .waitAndRetry }

        // 【既知の残課題への対応】一度でもメイン帳簿を確立済みのデバイスでは、
        // 0件に見える状態を二度と「新規作成してよい」根拠にしない
        // (CloudKit側の内部resetによる一時的な空白である可能性を排除できないため)。
        if establishedMainBookId != nil {
            return .waitAndRetry
        }

        if cloudSyncActive {
            switch initialImportState {
            case .pending:
                // D: CloudKit同期ONで初回import未完了。他端末の既存メイン帳簿が
                // まだ取り込まれていないだけの可能性があるため作らない。
                return .waitAndRetry
            case .completed:
                // import完了済みでなお0件 ＝ このApple IDでは本当に初めて。
                return .createNew
            case .notApplicable:
                // cloudSyncActive=trueのはずなのに.notApplicableは理論上到達しないが、
                // 判断材料が矛盾している以上は安全側(作らない)に倒す。
                return .waitAndRetry
            }
        }

        // A/D: CloudKit同期OFF、旧ストアも無く、ローカルも空 ＝ 作ってよい。
        return .createNew
    }

    /// iCloudアカウントが変わったかどうかを判定する純粋関数。
    ///
    /// - Parameter storedTokenData: 前回起動時に保存したubiquityIdentityTokenのアーカイブ(無ければnil)。
    /// - Parameter currentTokenData: 今回起動時の実際のubiquityIdentityTokenのアーカイブ
    ///   (iCloud未サインインならnil)。
    ///
    /// storedTokenDataがnil(まだ一度も記録していない＝この機能追加前からの既存ユーザー、
    /// または初回起動)の場合は「変化なし」として扱う。ここで誤って「変化した」と
    /// 判定すると、既存ユーザーのestablishedMainBookIdが起動直後に無条件でクリアされてしまい、
    /// 本来防ぎたかったCloudKit resetのタイミングと重なった場合に再び重複作成の危険が生じるため、
    /// 「記録が無ければ変化なしとみなす」という安全側の既定値にしている。
    static func hasUbiquityIdentityChanged(storedTokenData: Data?, currentTokenData: Data?) -> Bool {
        guard let storedTokenData else { return false }
        return storedTokenData != currentTokenData
    }

    /// - Parameter legacyUnifiedStoreExists: 省略時は実際の本番ディレクトリ
    ///   (`NSPersistentContainer.defaultDirectoryURL()`)を見て判定する。テストから明示的に
    ///   `false`を渡すことで、シミュレータの実ファイルシステムに偶然残っている
    ///   旧Kakeibo3.sqlite(他のテスト・手動実行の残骸)に左右されず決定的に検証できる。
    static func migrateIfNeeded(
        legacyUnifiedStoreExists: Bool = LegacyUnifiedStoreLocator.productionPaths() != nil
    ) {
        // 「BookDataが1件も無い」ことをゲートにすると、後からbookIdを追加した
        // モデル（カテゴリー・支払い方法等）が、既にBookDataが存在する端末では
        // 一切バックフィルされなくなってしまう。そのためBookDataの有無に関わらず、
        // 毎回nilなbookIdをメイン帳簿へバックフィルする（対象が無ければ何もしない軽い処理）。
        // 【iCloudアカウント変更の検知】existingBooksを読む前に、まずアカウントが
        // 変わっていないかを確認し、変わっていればestablishedMainBookIdKeyをクリアする
        // (BookData等の実データは一切削除しない。安全弁を未確立状態に戻すだけ)。
        let currentUbiquityTokenData = FileManager.default.ubiquityIdentityToken.flatMap { token in
            try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        }
        let storedUbiquityTokenData = UserDefaults.standard.data(forKey: lastKnownUbiquityIdentityTokenDataKey)
        if hasUbiquityIdentityChanged(storedTokenData: storedUbiquityTokenData, currentTokenData: currentUbiquityTokenData) {
            DiagnosticLog.write("BookMigrationService: iCloudアカウントの変更を検知。establishedMainBookIdKeyをクリアします")
            UserDefaults.standard.removeObject(forKey: establishedMainBookIdKey)
        }
        if let currentUbiquityTokenData {
            UserDefaults.standard.set(currentUbiquityTokenData, forKey: lastKnownUbiquityIdentityTokenDataKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastKnownUbiquityIdentityTokenDataKey)
        }

        let existingBooks = BookDataSync.fetchAll()
        let establishedMainBookId = UserDefaults.standard
            .string(forKey: establishedMainBookIdKey)
            .flatMap(UUID.init(uuidString:))
        let decision = decideMainBookCreation(
            existingBooks: existingBooks,
            legacyUnifiedStoreExists: legacyUnifiedStoreExists,
            cloudSyncActive: CoreDataStack.shared.isCloudSyncActive,
            initialImportState: CloudSyncSettings.shared.initialImportState,
            establishedMainBookId: establishedMainBookId
        )
        let diagCloudSyncActive = CoreDataStack.shared.isCloudSyncActive
        let diagImportState = CloudSyncSettings.shared.initialImportState
        let diagMessage = "BookMigrationService: existingBooks.count=\(existingBooks.count) legacyUnifiedStoreExists=\(legacyUnifiedStoreExists) cloudSyncActive=\(diagCloudSyncActive) initialImportState=\(diagImportState) establishedMainBookId=\(establishedMainBookId?.uuidString.prefix(8) ?? "nil") decision=\(decision)"
        DiagnosticLog.write(diagMessage)

        let mainBookId: UUID
        switch decision {
        case .useExisting(let id):
            mainBookId = id
        case .createNew:
            let mainBook = BookData(name: "メイン帳簿", sortOrder: 0, isMain: true)
            mainBookId = mainBook.id
            UserDefaults.standard.set(mainBookId.uuidString, forKey: BookSettings.storageKey)
            BookDataSync.insert(mainBook)
            DiagnosticLog.write("BookMigrationService: created NEW main book id=\(mainBookId.uuidString.prefix(8))")
            // 【調査用診断ログ】保存直後、(a)viewContextのfetchAllと(b)全く別のbackgroundContextの
            // 両方から見えるかを確認する（調査内容4,5：A/B/Cの切り分け）。
            DiagnosticLog.logBookSaveVerification(bookId: mainBookId)
        case .waitAndRetry:
            // メイン帳簿がまだ無い＝バックフィル先も無いため、今回は何もせず次回起動を待つ。
            return
        }

        // 【重要】useExisting/createNewのどちらであっても、ここで必ず確立済みidとして記録する。
        // これにより、次回以降「existingBooksが0件」に見えても二度と新規作成されなくなる
        // (このkeyが未設定の既存インストールでも、次に正常解決できた時点で自動的に書き込まれる)。
        UserDefaults.standard.set(mainBookId.uuidString, forKey: Self.establishedMainBookIdKey)

        for income in IncomeDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = income
            updated.bookId = mainBookId
            IncomeDataSync.update(updated)
        }
        for expense in ExpenseDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = expense
            updated.bookId = mainBookId
            ExpenseDataSync.update(updated)
        }
        for transfer in TransferDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = transfer
            updated.bookId = mainBookId
            TransferDataSync.update(updated)
        }
        for account in BankAccountDataSync.fetchAll() where account.bookId == nil {
            var updated = account
            updated.bookId = mainBookId
            BankAccountDataSync.update(updated)
        }
        for method in ReceiveMethodDataSync.fetchAll() where method.bookId == nil {
            var updated = method
            updated.bookId = mainBookId
            ReceiveMethodDataSync.update(updated)
        }
        for budget in BudgetDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = budget
            updated.bookId = mainBookId
            BudgetDataSync.update(updated)
        }
        for recurringBudget in RecurringBudgetDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = recurringBudget
            updated.bookId = mainBookId
            RecurringBudgetDataSync.update(updated)
        }
        for fixedExpense in FixedExpenseDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = fixedExpense
            updated.bookId = mainBookId
            FixedExpenseDataSync.update(updated)
        }
        for recurringIncome in RecurringIncomeDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = recurringIncome
            updated.bookId = mainBookId
            RecurringIncomeDataSync.update(updated)
        }
        for recurringTransfer in RecurringTransferSettingDataSync.fetch(matching: NSPredicate(format: "bookId == nil")) {
            var updated = recurringTransfer
            updated.bookId = mainBookId
            RecurringTransferSettingDataSync.update(updated)
        }

        // AssetGraphCacheDataは複合キー化により旧行がそのままでは使えないため、削除だけしておく
        // （分析>資産の「更新」ボタンで帳簿ごとに作り直される）
        AssetGraphCacheDataSync.deleteAllWithNilBookId()
    }
}
