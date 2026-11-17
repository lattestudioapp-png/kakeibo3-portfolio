import Foundation

// MARK: - 旧Kakeibo3.sqlite(分割前の単一ストア)の退避(Step 2B専用)
//
// 既存LegacyStoreEvacuator(SwiftDataストア用)と同じ「削除ではなくリネームで退避、
// store/wal/shmを一体として扱い、存在するものだけを対象にする」設計をそのまま踏襲する。
// パスの型がLegacyUnifiedStoreLocator.Paths(Core Data用)であるため、既存実装とは
// 独立した新しい型として定義する。

enum SplitLegacyStoreEvacuator {

    enum EvacuationError: Error, Equatable {
        case partialEvacuation(movedFiles: [String], failedFile: String)
    }

    static let backupSuffix = ".migrated-backup"

    static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + backupSuffix)
    }

    static func evacuate(
        paths: LegacyUnifiedStoreLocator.Paths,
        move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) throws {
        let fm = FileManager.default
        let originals = [paths.store, paths.wal, paths.shm]
        let existing = originals.filter { fm.fileExists(atPath: $0.path) }

        var moved: [String] = []
        for source in existing {
            let backup = backupURL(for: source)
            do {
                if fm.fileExists(atPath: backup.path) {
                    try fm.removeItem(at: backup)
                }
                try move(source, backup)
                moved.append(source.lastPathComponent)
            } catch {
                throw EvacuationError.partialEvacuation(movedFiles: moved, failedFile: source.lastPathComponent)
            }
        }
    }

    static func isFullyEvacuated(paths: LegacyUnifiedStoreLocator.Paths) -> Bool {
        let fm = FileManager.default
        return ![paths.store, paths.wal, paths.shm].contains { fm.fileExists(atPath: $0.path) }
    }
}
