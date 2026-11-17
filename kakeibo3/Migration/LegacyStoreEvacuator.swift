import Foundation

// MARK: - 旧SwiftDataストアの退避(store/wal/shmを一体として扱う)
//
// 削除ではなくリネーム(.migrated-backup)で退避する。存在するファイルだけを対象にし、
// 1件でも移動に失敗したら例外を投げて「どこまで移動できたか」を呼び出し側に伝える
// (途中で失敗した状態を検出できるようにするため)。

enum LegacyStoreEvacuator {

    enum EvacuationError: Error, Equatable {
        case partialEvacuation(movedFiles: [String], failedFile: String)
    }

    static let backupSuffix = ".migrated-backup"

    static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + backupSuffix)
    }

    /// - Parameter move: テスト用の差し替え可能なファイル移動処理。デフォルトは実際のFileManager。
    static func evacuate(
        paths: SwiftDataLegacyReader.LegacyStorePaths,
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

    /// 退避完了後、旧ストア側の元の場所(store/wal/shm)に何も残っていないことを確認する。
    static func isFullyEvacuated(paths: SwiftDataLegacyReader.LegacyStorePaths) -> Bool {
        let fm = FileManager.default
        return ![paths.store, paths.wal, paths.shm].contains { fm.fileExists(atPath: $0.path) }
    }
}
