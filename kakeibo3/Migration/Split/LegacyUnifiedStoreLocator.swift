import CoreData

// MARK: - Cloud/Local分割前の旧Kakeibo3.sqliteの所在確認(Step 2B専用)
//
// Step 2A以前の`CoreDataStack`は`NSPersistentContainer(name: "Kakeibo3", ...)`の
// デフォルト命名規則(`<name>.sqlite`をdefaultDirectoryURL()配下に置く)のまま
// 単一ストアを開いていた。そのため旧ストアのファイル名は常に"Kakeibo3.sqlite"。

enum LegacyUnifiedStoreLocator {
    struct Paths: Equatable {
        let store: URL
        let wal: URL
        let shm: URL
    }

    static let storeFileName = "Kakeibo3.sqlite"

    static func paths(directory: URL) -> Paths {
        Paths(
            store: directory.appendingPathComponent(storeFileName),
            wal: directory.appendingPathComponent(storeFileName + "-wal"),
            shm: directory.appendingPathComponent(storeFileName + "-shm")
        )
    }

    /// store本体が実在する場合のみパス一式を返す(-wal/-shmは無くてもよい)。
    static func paths(directory: URL, requireExists: Bool) -> Paths? {
        let candidate = paths(directory: directory)
        if requireExists {
            guard FileManager.default.fileExists(atPath: candidate.store.path) else { return nil }
        }
        return candidate
    }

    /// 実機/シミュレータの標準的な保存先で旧Kakeibo3.sqliteを探す。
    static func productionPaths() -> Paths? {
        paths(directory: NSPersistentContainer.defaultDirectoryURL(), requireExists: true)
    }
}
