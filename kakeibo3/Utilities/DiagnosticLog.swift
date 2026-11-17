import CoreData
import Foundation

// MARK: - 調査用診断ログ（一時的な調査ツール）
//
// 「カテゴリー・支出がアプリ再起動後に消える」不具合の調査専用。個人情報・取引内容
// （金額・メモ・カテゴリー名・日付等）は一切出力しない。件数・UUID・ストア識別子のみを
// Documents/diagnostic_log.txtへ書き出す（TimingDebugLogと同じ、FileHandleを都度開閉する
// 方式。既存データの読み取りのみで、一切変更しない）。
enum DiagnosticLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var onAppearFireCount = 0
    nonisolated(unsafe) private static var lastBookResolutionSignature: String = ""

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostic_log.txt")
    }

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL() else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// 起動シーケンスの各時点でのスナップショットを記録する。
    /// 件数・識別子のみで、取引内容・カテゴリー名・金額等は含めない。
    static func logStartupSnapshot(label: String) {
        let books = BookDataSync.fetchAll()
        let selectedIdString = UserDefaults.standard.string(forKey: BookSettings.storageKey) ?? "(unset)"
        let resolvedBook = BookResolver.resolveCurrentBook(from: books, selectedIdString: selectedIdString)

        var categoryCount = 0
        var expenseCount = 0
        if let bookId = resolvedBook?.id {
            categoryCount = CategoryDataSync.fetchAll(bookId: bookId).count
            expenseCount = ExpenseDataSync.fetchAll(bookId: bookId).count
        }

        let coordinator = CoreDataStack.shared.container.persistentStoreCoordinator
        let storeInfo = coordinator.persistentStores.map { store -> String in
            let filename = store.url?.lastPathComponent ?? "?"
            let uuid = (coordinator.metadata(for: store)[NSStoreUUIDKey] as? String) ?? "?"
            return "\(filename)=\(uuid)"
        }.joined(separator: ", ")

        write("""
        SNAPSHOT[\(label)]: \
        books=\(books.count) \
        bookIds=[\(books.map { $0.id.uuidString.prefix(8) }.joined(separator: ","))] \
        selectedIdString=\(selectedIdString.prefix(8)) \
        resolvedBookId=\(resolvedBook?.id.uuidString.prefix(8) ?? "nil") \
        resolvedIsMain=\(resolvedBook?.isMain.description ?? "nil") \
        categoryCount(resolvedBook)=\(categoryCount) \
        expenseCount(resolvedBook)=\(expenseCount) \
        stores=[\(storeInfo)] \
        isCloudSyncActive=\(CoreDataStack.shared.isCloudSyncActive)
        """)
    }

    /// CoreDataStartupCoordinator専用。CoreDataStack.shared確定直後、Split Migration等の
    /// 起動時処理の実行結果を記録する。
    static func logStoreIdentity(label: String) {
        let coordinator = CoreDataStack.shared.container.persistentStoreCoordinator
        let storeInfo = coordinator.persistentStores.map { store -> String in
            let path = store.url?.path ?? "?"
            let uuid = (coordinator.metadata(for: store)[NSStoreUUIDKey] as? String) ?? "?"
            return "path=\(path) uuid=\(uuid)"
        }.joined(separator: " | ")
        write("STORE_IDENTITY[\(label)]: \(storeInfo)")
    }

    // MARK: - 【追加調査】.onAppearの発火回数と時刻（調査内容1）
    //
    // Kakeibo3App.swiftのトップレベル.onAppear（本来は起動ごとに1回のはず）が
    // 1セッション内で複数回発火していないかを直接数える。
    static func logOnAppearFired() {
        lock.lock()
        onAppearFireCount += 1
        let count = onAppearFireCount
        lock.unlock()
        write("ONAPPEAR: fired count=\(count) (この番号が2以上なら同一セッション内での複数回発火)")
    }

    // MARK: - 【追加調査】起動処理の開始・終了・重複実行（調査内容2）
    //
    // MigrationCoordinator/CoreDataStartupCoordinatorのrunIfNeeded()が多重に呼ばれて
    // いないか（isRunningガードが実際に発動したか）を記録する。
    static func logReentrancyGuardTriggered(coordinator: String) {
        write("REENTRANCY_GUARD: \(coordinator).runIfNeeded()が実行中に再度呼ばれ、ガードにより無視された")
    }

    static func logCoordinatorLifecycle(coordinator: String, event: String) {
        write("LIFECYCLE: \(coordinator) \(event)")
    }

    // MARK: - 【追加調査】帳簿作成直後のcontext.save()結果と別contextからの再取得（調査内容4,5）
    //
    // BookMigrationServiceが新規メイン帳簿を作成した直後、(a) viewContext上でのfetchAllで
    // 見えるか、(b) 全く別の新規backgroundContextでも見えるか、を同時に記録する。
    // これにより「A:保存自体が失敗」「C:保存後に別経路から取得できない」を区別できる。
    static func logBookSaveVerification(bookId: UUID) {
        let viewContextCount = BookDataSync.fetchAll().filter { $0.id == bookId }.count

        let freshContext = CoreDataStack.shared.container.newBackgroundContext()
        var freshContextCount = -1
        var freshContextError: String?
        freshContext.performAndWait {
            let request = CDBookData.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", bookId as CVarArg)
            do {
                freshContextCount = try freshContext.count(for: request)
            } catch {
                freshContextError = "\(error)"
            }
        }

        write("""
        BOOK_SAVE_VERIFY: bookId=\(bookId.uuidString.prefix(8)) \
        viewContextFetchAllCount=\(viewContextCount) \
        freshBackgroundContextCount=\(freshContextCount) \
        freshContextError=\(freshContextError ?? "none")
        """)
    }

    // MARK: - 【追加調査】帳簿解決状態の変化（調査内容6,10）
    //
    // BookResolver.resolveCurrentBook()は非常に高頻度（再描画ごと）に呼ばれるため、
    // 結果が前回と同一なら出力しない（signatureが変化した時だけ記録する）。
    // タブ切り替え時に選択中の帳簿がどう変わったか、帳簿が0件になる直前の状態を追える。
    static func logBookResolutionIfChanged(
        books: [BookData],
        selectedIdString: String,
        resolvedId: UUID?
    ) {
        let sortedIds = books.map { $0.id.uuidString.prefix(8) }.sorted().joined(separator: ",")
        let signature = "count=\(books.count)|ids=[\(sortedIds)]|selected=\(selectedIdString.prefix(8))|resolved=\(resolvedId?.uuidString.prefix(8) ?? "nil")"

        lock.lock()
        let changed = signature != lastBookResolutionSignature
        if changed { lastBookResolutionSignature = signature }
        lock.unlock()

        guard changed else { return }
        write("BOOK_RESOLUTION_CHANGED: \(signature)")
    }

    // MARK: - 【追加調査】収支保存時のbookId（調査内容9）
    //
    // 個人情報・取引内容(金額・メモ・カテゴリー名等)は出力しない。bookId(識別子)のみ。
    static func logTransactionSaveBookId(kind: String, bookId: UUID) {
        write("TRANSACTION_SAVE: kind=\(kind) bookId=\(bookId.uuidString.prefix(8))")
    }

    // MARK: - 【追加調査】persistent history：transaction author・timestamp・変更内容の要約（調査内容7,8）
    //
    // RemoteChangeObserverは処理済み履行履歴を都度purgeするため、何もしなければ事後調査で
    // 消えてしまう。purge前のこの時点で全件（自分の書き込み含む）を記録する。
    // 個人情報は含めない（entity名・変更種別・件数・識別子のみ）。
    static func logHistoryTransactions(_ transactions: [NSPersistentHistoryTransaction], cloudStoreID: String?) {
        for transaction in transactions {
            let changeSummary = Dictionary(grouping: transaction.changes ?? []) {
                "\($0.changedObjectID.entity.name ?? "?"):\($0.changeType.rawValue)"
            }.map { key, values in "\(key)=\(values.count)" }.sorted().joined(separator: ",")

            write("""
            HISTORY_TRANSACTION: transactionNumber=\(transaction.transactionNumber) \
            author=\(transaction.author ?? "nil") \
            bundleId=\(transaction.bundleID ?? "nil") \
            contextName=\(transaction.contextName ?? "nil") \
            processId=\(transaction.processID ?? "nil") \
            storeId=\(transaction.storeID ?? "nil") \
            isCloudStore=\(transaction.storeID == cloudStoreID) \
            timestamp=\(transaction.timestamp) \
            changes=[\(changeSummary)]
            """)
        }
    }

    // MARK: - 【追加調査】CloudKit同期イベント（調査内容8）
    //
    // NSPersistentCloudKitContainer.eventChangedNotificationを記録する。setup/import/export
    // それぞれの開始・終了・成否・エラーのタイミングが、帳簿が消えるタイミングと一致するか確認する。
    static func logCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        write("""
        CLOUDKIT_EVENT: type=\(event.type.rawValue) \
        succeeded=\(event.succeeded) \
        startDate=\(event.startDate) \
        endDate=\(event.endDate.map { "\($0)" } ?? "nil") \
        error=\(event.error.map { "\($0)" } ?? "none")
        """)
    }
}
