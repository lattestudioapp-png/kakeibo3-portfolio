import Foundation
import CoreData

// MARK: - 移行オーケストレーションの入口(Phase B1 + B2)
//
// 重要な制約:MigrationBootstrapはCoreDataStack.sharedを一切参照しない。
// 「CoreDataStack.shared初期化 → migrateIfNeeded() → ストア差し替え」という
// 順序を禁止する方針のため、本番Core Dataスタックが生成される前に、
// この型だけで「移行が必要か」「旧ストアから読み取れるか」「一時ストアへ正しく
// 書き込めるか」「本番ストアへ安全に昇格できるか」を完結させる。
//
// Phase B1(読み取り〜一時ストア検証)は runB1Pipeline に集約し、
// migrate(legacyPaths:workDirectory:) から引き続き単体で呼べるようにしてある。
//
// Phase B2で追加したこと:
//   - 本番ストアの状態をCase A/B/Cで判定(実データがあれば自動上書きしない)
//   - 本番ストアへの昇格をジャーナル付きでアトミックに行う(ProductionStorePromoter)
//   - 昇格後、本番URLを開き直してManifest(件数・帳簿UUID・帳簿別チェックサム)を再検証
//   - 検証成功後にのみ旧SwiftDataストアを退避(store/wal/shmを一体で確認)
//   - MigrationManifestの永続保存とUserDefaults完了フラグの保存
//
// Phase B2でもまだ行わないこと(Phase B3で追加):
//   - Kakeibo3Appへの接続 / CoreDataStack.sharedを通常起動で使うこと / CloudKit関連の変更

enum MigrationFailure: Error, Equatable {
    case legacyReadFailed(String)
    case criticalReferenceIssues([MigrationReferenceIssue])
    case tempStoreWriteFailed(String)
    case verificationFailed(String)
    case reopenVerificationFailed(String)
    case productionStoreHasExistingData(String)
    case promotionFailed(String)
    case legacyStoreEvacuationFailed(String)
    case manifestSaveFailed(String)
}

enum MigrationOutcome {
    /// 旧SwiftDataストアが存在しない(新規インストール、または移行済みで退避済み)
    case notNeeded
    /// 一時Core Dataストアへの書き込み・検証・再オープン検証まで成功した(Phase B1単体のゴール)
    case tempStoreWriteSucceeded(
        manifest: MigrationManifest,
        warnings: [MigrationReferenceIssue],
        tempStoreURL: URL
    )
    /// 本番ストアに既に実データがあり、それが今回の移行と同一のものだと確認できた(再実行時の正常系)
    case alreadyMigrated(manifest: MigrationManifest)
    /// 本番ストアへの昇格・退避・記録まで全て成功した(Phase B2のゴール)
    case promoted(manifest: MigrationManifest, warnings: [MigrationReferenceIssue])
    case failed(MigrationFailure)
}

enum MigrationBootstrap {

    // MARK: - Phase B1単体(引き続き利用可能)

    static func migrateIfNeeded(workDirectory: URL = FileManager.default.temporaryDirectory) -> MigrationOutcome {
        guard let legacyPaths = SwiftDataLegacyReader.legacyStorePaths() else {
            return .notNeeded
        }
        return migrate(legacyPaths: legacyPaths, workDirectory: workDirectory)
    }

    /// テスト用:旧ストアのパスを直接指定して実行する(一時ストアの書き込み・検証まで)。
    static func migrate(legacyPaths: SwiftDataLegacyReader.LegacyStorePaths, workDirectory: URL) -> MigrationOutcome {
        switch runB1Pipeline(legacyPaths: legacyPaths, workDirectory: workDirectory) {
        case .success(let result):
            return .tempStoreWriteSucceeded(manifest: result.manifest, warnings: result.warnings, tempStoreURL: result.tempStoreURL)
        case .failure(let failure):
            return .failed(failure)
        }
    }

    // MARK: - Phase B2:本番ストアへの昇格まで含めた完全パイプライン

    static func migrateAndPromoteIfNeeded(
        workDirectory: URL = FileManager.default.temporaryDirectory,
        productionDirectory: URL,
        productionStoreName: String = "Kakeibo3.sqlite",
        userDefaults: UserDefaults = .standard
    ) -> MigrationOutcome {
        guard let legacyPaths = SwiftDataLegacyReader.legacyStorePaths() else {
            return .notNeeded
        }
        return migrateAndPromote(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, productionStoreName: productionStoreName,
            userDefaults: userDefaults
        )
    }

    /// テスト用:旧ストア・本番ディレクトリを直接指定して実行する。
    static func migrateAndPromote(
        legacyPaths: SwiftDataLegacyReader.LegacyStorePaths,
        workDirectory: URL,
        productionDirectory: URL,
        productionStoreName: String = "Kakeibo3.sqlite",
        userDefaults: UserDefaults = .standard
    ) -> MigrationOutcome {
        let productionPaths = ProductionStorePromoter.ProductionPaths(directory: productionDirectory, storeName: productionStoreName)

        // 前回中断した昇格が残っていれば、Case判定の前に必ず復旧しておく
        // (本番パスが「旧ストアまたは新ストアのどちらか」の正しい状態になっている前提を作る)。
        ProductionStorePromoter.recoverIfNeeded(paths: productionPaths)

        switch ProductionStoreCaseClassifier.classify(storeURL: productionPaths.store) {
        case .hasRealData:
            return handleCaseC(productionPaths: productionPaths, userDefaults: userDefaults)
        case .absent, .empty:
            break
        }

        let b1Result: (manifest: MigrationManifest, warnings: [MigrationReferenceIssue], tempStoreURL: URL)
        switch runB1Pipeline(legacyPaths: legacyPaths, workDirectory: workDirectory) {
        case .success(let result):
            b1Result = result
        case .failure(let failure):
            return .failed(failure)
        }

        switch ProductionStorePromoter.promote(tempStoreURL: b1Result.tempStoreURL, manifest: b1Result.manifest, paths: productionPaths) {
        case .failure(let error):
            try? FileManager.default.removeItem(at: b1Result.tempStoreURL)
            return .failed(.promotionFailed("\(error)"))

        case .success(let promotedManifest):
            do {
                try LegacyStoreEvacuator.evacuate(paths: legacyPaths)
            } catch {
                return .failed(.legacyStoreEvacuationFailed("\(error)"))
            }
            guard LegacyStoreEvacuator.isFullyEvacuated(paths: legacyPaths) else {
                return .failed(.legacyStoreEvacuationFailed("退避後も旧SwiftDataストアの一部が本来の場所に残っている"))
            }

            do {
                try MigrationCompletionRecorder.savePersistedManifest(promotedManifest, to: productionDirectory)
            } catch {
                return .failed(.manifestSaveFailed("\(error)"))
            }
            MigrationCompletionRecorder.markCompleted(in: userDefaults)

            try? FileManager.default.removeItem(at: b1Result.tempStoreURL)

            return .promoted(manifest: promotedManifest, warnings: b1Result.warnings)
        }
    }

    // MARK: - Case C(本番ストアに実データあり)

    private static func handleCaseC(
        productionPaths: ProductionStorePromoter.ProductionPaths,
        userDefaults: UserDefaults
    ) -> MigrationOutcome {
        let currentIdentifier: String? = {
            guard let stack = try? CoreDataStack(throwingStoreURL: productionPaths.store) else { return nil }
            defer { try? stack.releasePersistentStoresForMigration() }
            return ProductionStorePromoter.storeIdentifier(for: stack)
        }()

        if MigrationCompletionRecorder.isAlreadyCompleted(
            manifestDirectory: productionPaths.directory,
            currentStoreIdentifier: currentIdentifier,
            userDefaults: userDefaults
        ), let manifest = MigrationCompletionRecorder.loadPersistedManifest(from: productionPaths.directory) {
            return .alreadyMigrated(manifest: manifest)
        }

        return .failed(.productionStoreHasExistingData(
            "本番Core Dataストアに実データが存在し、かつ今回の移行結果であると確認できないため自動上書きしない"
        ))
    }

    // MARK: - Phase B1パイプライン(内部共有)

    private static func runB1Pipeline(
        legacyPaths: SwiftDataLegacyReader.LegacyStorePaths,
        workDirectory: URL
    ) -> Result<(manifest: MigrationManifest, warnings: [MigrationReferenceIssue], tempStoreURL: URL), MigrationFailure> {
        let snapshot: LegacySnapshot
        do {
            snapshot = try SwiftDataLegacyReader.readSnapshot(paths: legacyPaths)
        } catch {
            return .failure(.legacyReadFailed("\(error)"))
        }

        // 第2段階:UUID辞書による参照検証。重大エラーがあれば、一時ストアには一切触れずに中断する
        // (「一時ストア生成失敗時に旧ストア無傷」を、そもそも一時ストアを作らないことで保証する)。
        let issues = MigrationReferenceValidator.validate(snapshot: snapshot)
        let criticalIssues = issues.filter { $0.severity == .critical }
        guard criticalIssues.isEmpty else {
            return .failure(.criticalReferenceIssues(criticalIssues))
        }
        let warnings = issues.filter { $0.severity == .warning }

        let tempStoreURL = workDirectory.appendingPathComponent("Migration-\(UUID().uuidString).sqlite")
        let sourceAttributes = try? FileManager.default.attributesOfItem(atPath: legacyPaths.store.path)
        let sourceFileSize = (sourceAttributes?[.size] as? Int64) ?? 0
        let sourceModifiedAt = (sourceAttributes?[.modificationDate] as? Date) ?? .distantPast

        do {
            let stack = try CoreDataStack(throwingStoreURL: tempStoreURL)
            try TempCoreDataWriter.write(snapshot, into: stack.container.viewContext)

            let manifest = try MigrationVerifier.verify(
                snapshot: snapshot,
                context: stack.container.viewContext,
                sourceStoreFileSize: sourceFileSize,
                sourceStoreModifiedAt: sourceModifiedAt
            )

            // 一時ストアを閉じて再オープンし、永続化を再検証する
            try stack.releasePersistentStoresForMigration()
            let reopened = try CoreDataStack(throwingStoreURL: tempStoreURL)
            do {
                try MigrationVerifier.reverify(manifest: manifest, context: reopened.container.viewContext)
            } catch {
                return .failure(.reopenVerificationFailed("\(error)"))
            }
            try reopened.releasePersistentStoresForMigration()

            return .success((manifest: manifest, warnings: warnings, tempStoreURL: tempStoreURL))
        } catch let error as MigrationVerificationError {
            try? FileManager.default.removeItem(at: tempStoreURL)
            return .failure(.verificationFailed("\(error)"))
        } catch {
            try? FileManager.default.removeItem(at: tempStoreURL)
            return .failure(.tempStoreWriteFailed("\(error)"))
        }
    }
}
