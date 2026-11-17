import CoreData

// MARK: - Cloud/Local分割移行のオーケストレーション入口(Step 2B)
//
// 既存MigrationBootstrap(SwiftData→Core Data、B1/B2)と同じ設計パターンを踏襲する:
// 1. 旧ストアの有無を確認(無ければ.notNeeded)
// 2. 前回中断した昇格があれば復旧してからCase A/B/C判定
// 3. Case Cなら「既に今回の移行結果と確認できる場合のみ.alreadyMigrated」、それ以外は
//    自動上書きせずに失敗として返す
// 4. 安全な一時領域で読み取り→書き込み→検証→close→reopen→再検証まで完結させる
//    (ここまでは本番パスに一切触れない)
// 5. ジャーナル付きでCloud/Local2ストアへアトミックに昇格し、昇格後に本番URLを
//    開き直して最終検証する
// 6. 検証成功後にのみ旧Kakeibo3.sqliteをstore/wal/shm一体で退避する
// 7. SplitMigrationManifestの永続保存とUserDefaults完了フラグの保存
//
// 【重要】この時点ではまだKakeibo3App.swiftへの接続やCloudKit remote change処理は
// 実装しない。この型はCoreDataStack.sharedを一切参照せず、独立してテスト可能な
// パイプラインとして完結させる(既存MigrationBootstrapと同じ制約)。

enum SplitMigrationFailure: Error, Equatable {
    case sourceReadFailed(String)
    case tempStoreWriteFailed(String)
    case verificationFailed(String)
    case reopenVerificationFailed(String)
    case productionStoreHasExistingData(String)
    case promotionFailed(String)
    case legacyStoreEvacuationFailed(String)
    case manifestSaveFailed(String)
}

enum SplitMigrationOutcome {
    /// 旧Kakeibo3.sqliteが存在しない(新規インストール、または既に移行済みで退避済み)
    case notNeeded
    /// 一時Cloud/Localストアへの書き込み・検証・再オープン検証まで成功した
    case tempStoreVerified(manifest: SplitMigrationManifest, tempCloudURL: URL, tempLocalURL: URL)
    /// 本番ストアに既に実データがあり、それが今回の移行と同一のものだと確認できた(再実行時の正常系)
    case alreadyMigrated(manifest: SplitMigrationManifest)
    /// 本番Cloud/Localストアへの昇格・旧ストア退避・記録まで全て成功した
    case promoted(manifest: SplitMigrationManifest)
    case failed(SplitMigrationFailure)
}

enum SplitMigrationBootstrap {

    // MARK: - 本番の起動経路から呼ぶ入口

    static func migrateAndPromoteIfNeeded(
        workDirectory: URL = FileManager.default.temporaryDirectory,
        productionDirectory: URL,
        userDefaults: UserDefaults = .standard
    ) -> SplitMigrationOutcome {
        guard let legacyPaths = LegacyUnifiedStoreLocator.paths(directory: productionDirectory, requireExists: true) else {
            return .notNeeded
        }
        return migrateAndPromote(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
    }

    // MARK: - テスト用:旧ストア・本番ディレクトリを直接指定して実行する

    static func migrateAndPromote(
        legacyPaths: LegacyUnifiedStoreLocator.Paths,
        workDirectory: URL,
        productionDirectory: URL,
        userDefaults: UserDefaults = .standard
    ) -> SplitMigrationOutcome {
        let pairPaths = SplitStorePromoter.PairPaths(
            directory: productionDirectory,
            cloudStoreName: CoreDataStack.cloudStoreFileName,
            localStoreName: CoreDataStack.localStoreFileName
        )
        let cloudURL = CoreDataStack.cloudStoreURL(baseDirectory: productionDirectory)
        let localURL = CoreDataStack.localStoreURL(baseDirectory: productionDirectory)

        // 前回中断した昇格が残っていれば、Case判定の前に必ず復旧しておく。
        SplitStorePromoter.recoverIfNeeded(paths: pairPaths)

        switch SplitProductionCaseClassifier.classify(cloudStoreURL: cloudURL, localStoreURL: localURL) {
        case .hasRealData:
            return handleCaseC(pairPaths: pairPaths, userDefaults: userDefaults)
        case .absent, .empty:
            break
        }

        let tempResult: (manifest: SplitMigrationManifest, tempCloudURL: URL, tempLocalURL: URL, tempDirectory: URL)
        switch runTempPipeline(legacyPaths: legacyPaths, workDirectory: workDirectory) {
        case .success(let result):
            tempResult = result
        case .failure(let failure):
            return .failed(failure)
        }

        let promotionResult = SplitStorePromoter.promote(
            tempCloudStoreURL: tempResult.tempCloudURL,
            tempLocalStoreURL: tempResult.tempLocalURL,
            paths: pairPaths
        ) {
            let reopened = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false)
            defer { try? reopened.releasePersistentStoresForMigration() }
            try SplitMigrationVerifier.reverify(
                manifest: tempResult.manifest,
                context: reopened.container.viewContext,
                model: reopened.container.managedObjectModel
            )
        }

        switch promotionResult {
        case .failure(let error):
            try? FileManager.default.removeItem(at: tempResult.tempDirectory)
            return .failed(.promotionFailed("\(error)"))

        case .success:
            var finalManifest = tempResult.manifest
            do {
                let (cloudId, localId) = try storeIdentifiers(productionDirectory: productionDirectory)
                finalManifest.cloudStoreIdentifier = cloudId
                finalManifest.localStoreIdentifier = localId
            } catch {
                return .failed(.reopenVerificationFailed("\(error)"))
            }
            finalManifest.migrationState = .promoted

            do {
                try SplitLegacyStoreEvacuator.evacuate(paths: legacyPaths)
            } catch {
                return .failed(.legacyStoreEvacuationFailed("\(error)"))
            }
            guard SplitLegacyStoreEvacuator.isFullyEvacuated(paths: legacyPaths) else {
                return .failed(.legacyStoreEvacuationFailed("退避後も旧ストアの一部が本来の場所に残っている"))
            }

            do {
                try SplitMigrationCompletionRecorder.savePersistedManifest(finalManifest, to: productionDirectory)
            } catch {
                return .failed(.manifestSaveFailed("\(error)"))
            }
            SplitMigrationCompletionRecorder.markCompleted(in: userDefaults)

            try? FileManager.default.removeItem(at: tempResult.tempDirectory)

            return .promoted(manifest: finalManifest)
        }
    }

    // MARK: - Case C(本番ストアに実データあり)

    private static func handleCaseC(
        pairPaths: SplitStorePromoter.PairPaths, userDefaults: UserDefaults
    ) -> SplitMigrationOutcome {
        let identifiers = try? storeIdentifiers(productionDirectory: pairPaths.directory)

        if SplitMigrationCompletionRecorder.isAlreadyCompleted(
            manifestDirectory: pairPaths.directory,
            currentCloudStoreIdentifier: identifiers?.0,
            currentLocalStoreIdentifier: identifiers?.1,
            userDefaults: userDefaults
        ), let manifest = SplitMigrationCompletionRecorder.loadPersistedManifest(from: pairPaths.directory) {
            return .alreadyMigrated(manifest: manifest)
        }

        return .failed(.productionStoreHasExistingData(
            "本番Cloud/Localストアに実データが存在し、かつ今回の移行結果であると確認できないため自動上書きしない"
        ))
    }

    private static func storeIdentifiers(productionDirectory: URL) throws -> (String?, String?) {
        let stack = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false)
        defer { try? stack.releasePersistentStoresForMigration() }
        let coordinator = stack.container.persistentStoreCoordinator
        let cloudStore = coordinator.persistentStores.first { $0.url?.lastPathComponent == CoreDataStack.cloudStoreFileName }
        let localStore = coordinator.persistentStores.first { $0.url?.lastPathComponent == CoreDataStack.localStoreFileName }
        let cloudId = cloudStore.flatMap { coordinator.metadata(for: $0)[NSStoreUUIDKey] as? String }
        let localId = localStore.flatMap { coordinator.metadata(for: $0)[NSStoreUUIDKey] as? String }
        return (cloudId, localId)
    }

    // MARK: - 一時ストアパイプライン(読み取り→書き込み→検証→close→reopen→再検証)

    private static func runTempPipeline(
        legacyPaths: LegacyUnifiedStoreLocator.Paths, workDirectory: URL
    ) -> Result<(manifest: SplitMigrationManifest, tempCloudURL: URL, tempLocalURL: URL, tempDirectory: URL), SplitMigrationFailure> {
        let snapshot: SplitMigrationSourceSnapshot
        do {
            snapshot = try SplitMigrationSourceReader.readSnapshot(paths: legacyPaths, workDirectory: workDirectory)
        } catch {
            return .failure(.sourceReadFailed("\(error)"))
        }

        let tempDir = workDirectory.appendingPathComponent("SplitMigrationTemp-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.tempStoreWriteFailed("\(error)"))
        }
        let tempCloudURL = CoreDataStack.cloudStoreURL(baseDirectory: tempDir)
        let tempLocalURL = CoreDataStack.localStoreURL(baseDirectory: tempDir)

        do {
            let stack = try CoreDataStack(cloudLocalDirectory: tempDir, enableCloudKit: false)
            try SplitMigrationTempWriter.write(snapshot, context: stack.container.viewContext)

            let model = stack.container.managedObjectModel
            let verifyResult = try SplitMigrationVerifier.verify(
                snapshot: snapshot, context: stack.container.viewContext, model: model
            )

            let coordinator = stack.container.persistentStoreCoordinator
            guard let cloudStore = coordinator.persistentStores.first(where: { $0.url?.lastPathComponent == CoreDataStack.cloudStoreFileName }),
                  let localStore = coordinator.persistentStores.first(where: { $0.url?.lastPathComponent == CoreDataStack.localStoreFileName })
            else {
                throw SplitMigrationVerificationError.countMismatch(entity: "(store)", expected: 2, actual: 0)
            }
            try SplitMigrationVerifier.verifyNoCrossContamination(
                cloudStore: cloudStore, localStore: localStore, context: stack.container.viewContext, model: model
            )

            let manifest = SplitMigrationManifest(
                migrationVersion: SplitMigrationManifest.currentVersion,
                completedAt: Date(),
                sourceStoreIdentifier: snapshot.sourceStoreIdentifier,
                sourceStoreFileSize: snapshot.sourceFileSize,
                sourceStoreModifiedAt: snapshot.sourceModifiedAt,
                cloudEntityCounts: verifyResult.cloudEntityCounts,
                localEntityCounts: verifyResult.localEntityCounts,
                sourceBookIDs: snapshot.bookIDs,
                bookSummaries: verifyResult.bookSummaries,
                cloudStoreIdentifier: nil,
                localStoreIdentifier: nil,
                checksums: verifyResult.checksums,
                migrationWarnings: [],
                migrationState: .tempStoreVerified
            )

            // 一時ストアを閉じて再オープンし、永続化を再検証する
            try stack.releasePersistentStoresForMigration()
            let reopened = try CoreDataStack(cloudLocalDirectory: tempDir, enableCloudKit: false)
            do {
                try SplitMigrationVerifier.reverify(
                    manifest: manifest, context: reopened.container.viewContext, model: reopened.container.managedObjectModel
                )
            } catch {
                return .failure(.reopenVerificationFailed("\(error)"))
            }
            try reopened.releasePersistentStoresForMigration()

            return .success((manifest: manifest, tempCloudURL: tempCloudURL, tempLocalURL: tempLocalURL, tempDirectory: tempDir))
        } catch let error as SplitMigrationVerificationError {
            try? FileManager.default.removeItem(at: tempDir)
            return .failure(.verificationFailed("\(error)"))
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return .failure(.tempStoreWriteFailed("\(error)"))
        }
    }
}
