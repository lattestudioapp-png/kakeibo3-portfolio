import CoreData

// MARK: - 本番ストアへの安全な昇格(アトミック性の確保)
//
// 「途中でクラッシュ・電源断・アプリ強制終了が起きても、旧ストアまたは新ストアの
// どちらかが必ず残る」を満たすため、以下の3段階＋ジャーナルで進める。
// 各段階の入れ替え自体は同一ボリューム内の単一ファイルrename(アトミック)であり、
// 複数ファイルにまたがる「途中状態」はジャーナルのphaseで検出・復旧できるようにする。
//
//   .stagingReady     : .incoming一式を本番ディレクトリに置いただけ。本番パス未変更。
//   .legacyEvacuated  : 既存の本番ファイル(あれば)を.pre-migration-backupへ退避。
//                       本番パスは一時的に空だが、.incomingは健在。
//   .incomingPromoted : .incomingを本番名へrename。新ストアが本番パスに存在する。
//                       最終検証(Manifest突合)だけが残っている。
//
// sqlite/wal/shmは常に3点セットとして扱う(存在するものだけを対象にする)。

enum ProductionPromotionError: Error, Equatable {
    case stagingFailed(String)
    case verificationFailed(String)
}

enum ProductionStorePromoter {

    struct ProductionPaths {
        let directory: URL
        let storeName: String

        var store: URL { directory.appendingPathComponent(storeName) }
        var wal: URL { directory.appendingPathComponent(storeName + "-wal") }
        var shm: URL { directory.appendingPathComponent(storeName + "-shm") }

        var incomingStore: URL { directory.appendingPathComponent(storeName + ".incoming") }
        var incomingWal: URL { directory.appendingPathComponent(storeName + "-wal.incoming") }
        var incomingShm: URL { directory.appendingPathComponent(storeName + "-shm.incoming") }

        var backupStore: URL { directory.appendingPathComponent(storeName + ".pre-migration-backup") }
        var backupWal: URL { directory.appendingPathComponent(storeName + "-wal.pre-migration-backup") }
        var backupShm: URL { directory.appendingPathComponent(storeName + "-shm.pre-migration-backup") }
    }

    // MARK: - 中断からの復旧
    //
    // 昇格処理を始める前に必ず呼ぶ。前回の昇格がどこかのphaseで中断されたまま
    // ジャーナルが残っていれば、本番パスが必ず「旧ストアまたは新ストアのどちらか」に
    // なるよう復旧してからジャーナルを消す。
    static func recoverIfNeeded(paths: ProductionPaths) {
        guard let journal = PromotionJournal.load(from: paths.directory) else { return }

        switch journal.phase {
        case .stagingReady:
            // 本番パスはまだ触っていない。.incomingは次のpromote()にそのまま使わせる。
            break

        case .legacyEvacuated:
            // 本番パスが空(または一部欠落)。.incomingを本番名へ昇格し直す。
            promoteIncomingToCanonical(paths: paths)
            PromotionJournal.delete(from: paths.directory)

        case .incomingPromoted:
            // 本番パスは既に新ストア。ジャーナルを消し、呼び出し側の再検証に委ねる
            // (再検証に失敗すれば、その時点で改めてrollbackされる)。
            PromotionJournal.delete(from: paths.directory)
        }
    }

    // MARK: - 昇格本体

    static func promote(
        tempStoreURL: URL,
        manifest: MigrationManifest,
        paths: ProductionPaths
    ) -> Result<MigrationManifest, ProductionPromotionError> {
        recoverIfNeeded(paths: paths)

        do {
            try stageIncoming(tempStoreURL: tempStoreURL, paths: paths)
            try PromotionJournal(phase: .stagingReady, startedAt: Date(), tempStoreSourcePath: tempStoreURL.path)
                .write(to: paths.directory)

            try evacuateExistingProduction(paths: paths)
            try PromotionJournal(phase: .legacyEvacuated, startedAt: Date(), tempStoreSourcePath: tempStoreURL.path)
                .write(to: paths.directory)

            try promoteIncomingToCanonicalOrThrow(paths: paths)
            try PromotionJournal(phase: .incomingPromoted, startedAt: Date(), tempStoreSourcePath: tempStoreURL.path)
                .write(to: paths.directory)
        } catch {
            return .failure(.stagingFailed("\(error)"))
        }

        do {
            let stack = try CoreDataStack(throwingStoreURL: paths.store)
            defer { try? stack.releasePersistentStoresForMigration() }
            try MigrationVerifier.reverify(manifest: manifest, context: stack.container.viewContext)
            try MigrationVerifier.verifyBookIdsExist(manifest: manifest, context: stack.container.viewContext)

            var finalManifest = manifest
            finalManifest.targetStoreIdentifier = storeIdentifier(for: stack)

            PromotionJournal.delete(from: paths.directory)
            return .success(finalManifest)
        } catch {
            rollback(paths: paths)
            PromotionJournal.delete(from: paths.directory)
            return .failure(.verificationFailed("\(error)"))
        }
    }

    static func storeIdentifier(for stack: CoreDataStack) -> String? {
        guard let store = stack.container.persistentStoreCoordinator.persistentStores.first else { return nil }
        return stack.container.persistentStoreCoordinator.metadata(for: store)[NSStoreUUIDKey] as? String
    }

    // MARK: - Steps

    private static func stageIncoming(tempStoreURL: URL, paths: ProductionPaths) throws {
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

    private static func evacuateExistingProduction(paths: ProductionPaths) throws {
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

    private static func promoteIncomingToCanonicalOrThrow(paths: ProductionPaths) throws {
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
            throw ProductionPromotionError.stagingFailed("昇格後に本番sqliteが存在しない")
        }
    }

    /// recoverIfNeeded専用(ベストエフォート。失敗しても例外化しない)。
    private static func promoteIncomingToCanonical(paths: ProductionPaths) {
        try? promoteIncomingToCanonicalOrThrow(paths: paths)
    }

    private static func rollback(paths: ProductionPaths) {
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
