import CoreData

// MARK: - 移行フロー専用のCoreDataStack拡張
//
// 本番CoreDataStack.swiftは変更せず、移行専用の操作(一時ストアの明示的なクローズ)だけを
// ここに隔離する。ストアをコーディネーターから外すとSQLiteのWALがcheckpointされた状態で
// クローズされるため、次にこのURLを開き直したときに永続化が正しく反映されているかを
// 検証できる(「一時ストアを閉じて再オープンし、永続化を再検証する」ためのヘルパー)。

extension CoreDataStack {
    func releasePersistentStoresForMigration() throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
