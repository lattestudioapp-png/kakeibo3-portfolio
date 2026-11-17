import CoreData

// MARK: - 旧Kakeibo3.sqlite(分割前の単一ストア)の安全な読み取り(Step 2B専用)
//
// SwiftDataLegacyReaderと同じ「store/wal/shmを一時領域へコピーし、コピー側だけを開いて
// 読む。元のストアは一切変更しない」という安全性パターンを踏襲する。
// 読み取り先はCore Data(SwiftDataではない)なので、既存の`CoreDataStack(throwingStoreURL:)`
// (単一ストア・cloudKitContainerOptions無し)がそのまま使える。

enum SplitMigrationReadError: Error, Equatable {
    case storeNotFound
}

struct SplitMigrationSourceSnapshot {
    let cloudRowsByEntity: [String: [SplitMigrationRow]]
    let localRowsByEntity: [String: [SplitMigrationRow]]
    let sourceFileSize: Int64
    let sourceModifiedAt: Date
    let sourceStoreIdentifier: String?
    let bookIDs: [UUID]
}

enum SplitMigrationSourceReader {

    /// 旧ストア(store/wal/shm一体)を一時領域へコピーし、コピー側だけをCore Dataで開いて
    /// Cloud対象13 Entity・Local対象4 Entityそれぞれの全行を読み取る。元のストアは無傷。
    static func readSnapshot(
        paths: LegacyUnifiedStoreLocator.Paths,
        workDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> SplitMigrationSourceSnapshot {
        guard FileManager.default.fileExists(atPath: paths.store.path) else {
            throw SplitMigrationReadError.storeNotFound
        }

        let workDir = workDirectory.appendingPathComponent("SplitMigrationSourceReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let copiedStore = workDir.appendingPathComponent(LegacyUnifiedStoreLocator.storeFileName)
        try FileManager.default.copyItem(at: paths.store, to: copiedStore)
        for sidecar in [paths.wal, paths.shm] where FileManager.default.fileExists(atPath: sidecar.path) {
            try FileManager.default.copyItem(at: sidecar, to: workDir.appendingPathComponent(sidecar.lastPathComponent))
        }

        let sourceAttributes = try? FileManager.default.attributesOfItem(atPath: paths.store.path)
        let sourceFileSize = (sourceAttributes?[.size] as? Int64) ?? 0
        let sourceModifiedAt = (sourceAttributes?[.modificationDate] as? Date) ?? .distantPast

        let stack = try CoreDataStack(throwingStoreURL: copiedStore)
        defer { try? stack.releasePersistentStoresForMigration() }
        let context = stack.container.viewContext
        let model = stack.container.managedObjectModel
        let sourceStoreIdentifier = ProductionStorePromoter.storeIdentifier(for: stack)

        let cloudRows = try readRows(entityNames: SplitEntityConfiguration.cloudEntityNames(model: model), context: context)
        let localRows = try readRows(entityNames: SplitEntityConfiguration.localEntityNames(model: model), context: context)

        let bookIDs = (cloudRows["BookData"] ?? [])
            .compactMap { $0.attributes["id"] as? UUID }

        return SplitMigrationSourceSnapshot(
            cloudRowsByEntity: cloudRows,
            localRowsByEntity: localRows,
            sourceFileSize: sourceFileSize,
            sourceModifiedAt: sourceModifiedAt,
            sourceStoreIdentifier: sourceStoreIdentifier,
            bookIDs: bookIDs
        )
    }

    private static func readRows(
        entityNames: [String], context: NSManagedObjectContext
    ) throws -> [String: [SplitMigrationRow]] {
        var result: [String: [SplitMigrationRow]] = [:]
        var thrownError: Error?
        context.performAndWait {
            for entityName in entityNames {
                do {
                    result[entityName] = try SplitCoreDataRowCopier.fetchAllRows(entityName: entityName, context: context)
                } catch {
                    thrownError = error
                    return
                }
            }
        }
        if let thrownError { throw thrownError }
        return result
    }
}
