import CoreData

// MARK: - Cloud/Local 2ストアの安全な昇格(Step 2B専用)
//
// 既存ProductionStorePromoter(単一ストア用)と全く同じ3段階アルゴリズム
// (.stagingReady → .legacyEvacuated → .incomingPromoted、各段階は同一ボリューム内の
// 単一ファイルrenameでアトミック)を、Cloud/Local2ストアそれぞれに独立して適用する。
// ジャーナルは2ストアぶんのパスを1つのSplitPromotionJournalへまとめて記録することで、
// 「Cloud昇格後・Local昇格前にクラッシュ」のような中間状態も1つのジャーナルから復旧できる。
//
// ProductionStorePromoter.ProductionPathsをそのまま再利用する(directory+storeNameだけの
// 単純な値型で、Cloud/Localどちらのストア名を渡しても同じ計算式でincoming/backupパスが
// 求まるため)。ファイル操作のアルゴリズム自体は既存の実装をそのまま流用したいが、
// 既存実装の該当関数はfile-privateであり、B1/B2の既存動作に一切影響を与えないよう
// 既存ファイルには手を入れず、同じアルゴリズムをこちらに複製する。

enum SplitPromotionError: Error, Equatable {
    case stagingFailed(String)
    case verificationFailed(String)
}

enum SplitStorePromoter {

    struct PairPaths {
        let directory: URL
        let cloudStoreName: String
        let localStoreName: String

        var cloud: ProductionStorePromoter.ProductionPaths {
            .init(directory: directory, storeName: cloudStoreName)
        }
        var local: ProductionStorePromoter.ProductionPaths {
            .init(directory: directory, storeName: localStoreName)
        }
    }

    // MARK: - 中断からの復旧

    static func recoverIfNeeded(paths: PairPaths) {
        guard let journal = SplitPromotionJournal.load(from: paths.directory) else { return }

        switch journal.phase {
        case .stagingReady:
            break

        case .legacyEvacuated:
            promoteIncomingToCanonicalBestEffort(paths.cloud)
            promoteIncomingToCanonicalBestEffort(paths.local)
            SplitPromotionJournal.delete(from: paths.directory)

        case .incomingPromoted:
            SplitPromotionJournal.delete(from: paths.directory)
        }
    }

    // MARK: - 昇格本体

    /// - Parameter reverify: 両ストアが本番パスへ昇格した後に呼ぶ最終検証。失敗したら例外を投げる。
    static func promote(
        tempCloudStoreURL: URL,
        tempLocalStoreURL: URL,
        paths: PairPaths,
        reverify: () throws -> Void
    ) -> Result<Void, SplitPromotionError> {
        recoverIfNeeded(paths: paths)

        do {
            try stageIncoming(tempStoreURL: tempCloudStoreURL, paths: paths.cloud)
            try stageIncoming(tempStoreURL: tempLocalStoreURL, paths: paths.local)
            try SplitPromotionJournal(
                phase: .stagingReady, startedAt: Date(),
                tempCloudStoreSourcePath: tempCloudStoreURL.path,
                tempLocalStoreSourcePath: tempLocalStoreURL.path
            ).write(to: paths.directory)

            try evacuateExistingProduction(paths: paths.cloud)
            try evacuateExistingProduction(paths: paths.local)
            try SplitPromotionJournal(
                phase: .legacyEvacuated, startedAt: Date(),
                tempCloudStoreSourcePath: tempCloudStoreURL.path,
                tempLocalStoreSourcePath: tempLocalStoreURL.path
            ).write(to: paths.directory)

            try promoteIncomingToCanonicalOrThrow(paths: paths.cloud)
            try promoteIncomingToCanonicalOrThrow(paths: paths.local)
            try SplitPromotionJournal(
                phase: .incomingPromoted, startedAt: Date(),
                tempCloudStoreSourcePath: tempCloudStoreURL.path,
                tempLocalStoreSourcePath: tempLocalStoreURL.path
            ).write(to: paths.directory)
        } catch {
            return .failure(.stagingFailed("\(error)"))
        }

        do {
            try reverify()
            SplitPromotionJournal.delete(from: paths.directory)
            return .success(())
        } catch {
            rollback(paths: paths.cloud)
            rollback(paths: paths.local)
            SplitPromotionJournal.delete(from: paths.directory)
            return .failure(.verificationFailed("\(error)"))
        }
    }

    // MARK: - Steps(単一ストア分。既存ProductionStorePromoterと同一アルゴリズム)

    private static func stageIncoming(tempStoreURL: URL, paths: ProductionStorePromoter.ProductionPaths) throws {
        let fm = FileManager.default
        for url in [paths.incomingStore, paths.incomingWal, paths.incomingShm] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.copyItem(at: tempStoreURL, to: paths.incomingStore)

        let tempWal = URL(fileURLWithPath: tempStoreURL.path + "-wal")
        let tempShm = URL(fileURLWithPath: tempStoreURL.path + "-shm")
        if fm.fileExists(atPath: tempWal.path) {
            try fm.copyItem(at: tempWal, to: paths.incomingWal)
        }
        if fm.fileExists(atPath: tempShm.path) {
            try fm.copyItem(at: tempShm, to: paths.incomingShm)
        }
    }

    private static func evacuateExistingProduction(paths: ProductionStorePromoter.ProductionPaths) throws {
        let fm = FileManager.default
        let pairs: [(URL, URL)] = [
            (paths.store, paths.backupStore),
            (paths.wal, paths.backupWal),
            (paths.shm, paths.backupShm),
        ]
        for (source, backup) in pairs where fm.fileExists(atPath: source.path) {
            if fm.fileExists(atPath: backup.path) {
                try fm.removeItem(at: backup)
            }
            try fm.moveItem(at: source, to: backup)
        }
    }

    private static func promoteIncomingToCanonicalOrThrow(paths: ProductionStorePromoter.ProductionPaths) throws {
        let fm = FileManager.default
        let pairs: [(URL, URL)] = [
            (paths.incomingStore, paths.store),
            (paths.incomingWal, paths.wal),
            (paths.incomingShm, paths.shm),
        ]
        for (incoming, canonical) in pairs where fm.fileExists(atPath: incoming.path) {
            if fm.fileExists(atPath: canonical.path) {
                try fm.removeItem(at: canonical)
            }
            try fm.moveItem(at: incoming, to: canonical)
        }
        guard fm.fileExists(atPath: paths.store.path) else {
            throw SplitPromotionError.stagingFailed("昇格後に本番sqliteが存在しない: \(paths.storeName)")
        }
    }

    /// recoverIfNeeded専用(ベストエフォート。失敗しても例外化しない)。
    private static func promoteIncomingToCanonicalBestEffort(_ paths: ProductionStorePromoter.ProductionPaths) {
        try? promoteIncomingToCanonicalOrThrow(paths: paths)
    }

    private static func rollback(paths: ProductionStorePromoter.ProductionPaths) {
        let fm = FileManager.default
        for url in [paths.store, paths.wal, paths.shm] where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        let pairs: [(URL, URL)] = [
            (paths.backupStore, paths.store),
            (paths.backupWal, paths.wal),
            (paths.backupShm, paths.shm),
        ]
        for (backup, canonical) in pairs where fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: canonical)
        }
    }
}
