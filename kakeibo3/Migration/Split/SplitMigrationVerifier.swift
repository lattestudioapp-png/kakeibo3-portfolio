import CoreData

// MARK: - Cloud/Local分割移行の検証(件数・チェックサム・帳簿別集計・混在なし)

enum SplitMigrationVerificationError: Error, Equatable {
    case countMismatch(entity: String, expected: Int, actual: Int)
    case checksumMismatch(entity: String)
    case crossContamination(entity: String, foundInWrongStore: Int)
    case bookSummaryMismatch(bookId: UUID)
}

struct SplitMigrationVerificationResult {
    let cloudEntityCounts: [String: Int]
    let localEntityCounts: [String: Int]
    let checksums: [String: String]
    let bookSummaries: [SplitMigrationBookSummary]
}

enum SplitMigrationVerifier {

    // MARK: - 書き込み直後の検証(元Snapshotとの内容一致まで確認してManifest材料を作る)

    static func verify(
        snapshot: SplitMigrationSourceSnapshot,
        context: NSManagedObjectContext,
        model: NSManagedObjectModel
    ) throws -> SplitMigrationVerificationResult {
        var cloudCounts: [String: Int] = [:]
        var localCounts: [String: Int] = [:]
        var checksums: [String: String] = [:]

        for entityName in SplitEntityConfiguration.cloudEntityNames(model: model) {
            let expectedRows = snapshot.cloudRowsByEntity[entityName] ?? []
            let actualRows = try SplitCoreDataRowCopier.fetchAllRows(entityName: entityName, context: context)
            guard actualRows.count == expectedRows.count else {
                throw SplitMigrationVerificationError.countMismatch(entity: entityName, expected: expectedRows.count, actual: actualRows.count)
            }
            let expectedChecksum = SplitCoreDataRowCopier.checksum(for: expectedRows)
            let actualChecksum = SplitCoreDataRowCopier.checksum(for: actualRows)
            guard expectedChecksum == actualChecksum else {
                throw SplitMigrationVerificationError.checksumMismatch(entity: entityName)
            }
            cloudCounts[entityName] = actualRows.count
            checksums[checksumKey(store: .cloud, entityName: entityName)] = actualChecksum
        }

        for entityName in SplitEntityConfiguration.localEntityNames(model: model) {
            let expectedRows = snapshot.localRowsByEntity[entityName] ?? []
            let actualRows = try SplitCoreDataRowCopier.fetchAllRows(entityName: entityName, context: context)
            guard actualRows.count == expectedRows.count else {
                throw SplitMigrationVerificationError.countMismatch(entity: entityName, expected: expectedRows.count, actual: actualRows.count)
            }
            let expectedChecksum = SplitCoreDataRowCopier.checksum(for: expectedRows)
            let actualChecksum = SplitCoreDataRowCopier.checksum(for: actualRows)
            guard expectedChecksum == actualChecksum else {
                throw SplitMigrationVerificationError.checksumMismatch(entity: entityName)
            }
            localCounts[entityName] = actualRows.count
            checksums[checksumKey(store: .local, entityName: entityName)] = actualChecksum
        }

        let bookSummaries = try snapshot.bookIDs.map { bookId -> SplitMigrationBookSummary in
            let fromSnapshot = bookSummaryFromSnapshot(bookId: bookId, snapshot: snapshot)
            let fromContext = try computeBookSummary(bookId: bookId, context: context, model: model)
            guard fromSnapshot == fromContext else {
                throw SplitMigrationVerificationError.bookSummaryMismatch(bookId: bookId)
            }
            return fromContext
        }

        return SplitMigrationVerificationResult(
            cloudEntityCounts: cloudCounts, localEntityCounts: localCounts,
            checksums: checksums, bookSummaries: bookSummaries
        )
    }

    // MARK: - close→reopen後の再検証(件数+チェックサムの一致のみ。軽量)

    static func reverify(manifest: SplitMigrationManifest, context: NSManagedObjectContext, model: NSManagedObjectModel) throws {
        for entityName in SplitEntityConfiguration.cloudEntityNames(model: model) {
            try reverifyOne(entityName: entityName, store: .cloud, manifest: manifest, context: context)
        }
        for entityName in SplitEntityConfiguration.localEntityNames(model: model) {
            try reverifyOne(entityName: entityName, store: .local, manifest: manifest, context: context)
        }
        for summary in manifest.bookSummaries {
            let recomputed = try computeBookSummary(bookId: summary.bookId, context: context, model: model)
            guard recomputed == summary else {
                throw SplitMigrationVerificationError.bookSummaryMismatch(bookId: summary.bookId)
            }
        }
    }

    private static func reverifyOne(
        entityName: String, store: StoreKind, manifest: SplitMigrationManifest, context: NSManagedObjectContext
    ) throws {
        let expectedCount = store == .cloud ? (manifest.cloudEntityCounts[entityName] ?? 0) : (manifest.localEntityCounts[entityName] ?? 0)
        let actualRows = try SplitCoreDataRowCopier.fetchAllRows(entityName: entityName, context: context)
        guard actualRows.count == expectedCount else {
            throw SplitMigrationVerificationError.countMismatch(entity: entityName, expected: expectedCount, actual: actualRows.count)
        }
        let expectedChecksum = manifest.checksums[checksumKey(store: store, entityName: entityName)]
        let actualChecksum = SplitCoreDataRowCopier.checksum(for: actualRows)
        guard actualChecksum == expectedChecksum else {
            throw SplitMigrationVerificationError.checksumMismatch(entity: entityName)
        }
    }

    // MARK: - Cloud/Local混在なしの確認(逆側のstoreに、来るはずのないEntityが0件であること)

    static func verifyNoCrossContamination(
        cloudStore: NSPersistentStore, localStore: NSPersistentStore,
        context: NSManagedObjectContext, model: NSManagedObjectModel
    ) throws {
        for entityName in SplitEntityConfiguration.localEntityNames(model: model) {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [cloudStore]
            let count = try context.count(for: request)
            guard count == 0 else {
                throw SplitMigrationVerificationError.crossContamination(entity: entityName, foundInWrongStore: count)
            }
        }
        for entityName in SplitEntityConfiguration.cloudEntityNames(model: model) {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [localStore]
            let count = try context.count(for: request)
            guard count == 0 else {
                throw SplitMigrationVerificationError.crossContamination(entity: entityName, foundInWrongStore: count)
            }
        }
    }

    // MARK: - Helpers

    private enum StoreKind { case cloud, local }

    private static func checksumKey(store: StoreKind, entityName: String) -> String {
        "\(store == .cloud ? "cloud" : "local").\(entityName)"
    }

    private static func bookSummaryFromSnapshot(bookId: UUID, snapshot: SplitMigrationSourceSnapshot) -> SplitMigrationBookSummary {
        func matchingRows(_ dict: [String: [SplitMigrationRow]], entityName: String) -> [SplitMigrationRow] {
            (dict[entityName] ?? []).filter { SplitCoreDataRowCopier.bookId(of: $0) == bookId }
        }

        var cloudCounts: [String: Int] = [:]
        for entityName in snapshot.cloudRowsByEntity.keys where entityName != "BookData" {
            cloudCounts[entityName] = matchingRows(snapshot.cloudRowsByEntity, entityName: entityName).count
        }
        var localCounts: [String: Int] = [:]
        for entityName in snapshot.localRowsByEntity.keys {
            localCounts[entityName] = matchingRows(snapshot.localRowsByEntity, entityName: entityName).count
        }

        let expenseTotal = matchingRows(snapshot.cloudRowsByEntity, entityName: "ExpenseData").reduce(0) { $0 + SplitCoreDataRowCopier.amount(of: $1) }
        let incomeTotal = matchingRows(snapshot.cloudRowsByEntity, entityName: "IncomeData").reduce(0) { $0 + SplitCoreDataRowCopier.amount(of: $1) }
        let transferTotal = matchingRows(snapshot.cloudRowsByEntity, entityName: "TransferData").reduce(0) { $0 + SplitCoreDataRowCopier.amount(of: $1) }

        return SplitMigrationBookSummary(
            bookId: bookId, cloudEntityCounts: cloudCounts, localEntityCounts: localCounts,
            expenseTotal: expenseTotal, incomeTotal: incomeTotal, transferTotal: transferTotal
        )
    }

    private static func computeBookSummary(
        bookId: UUID, context: NSManagedObjectContext, model: NSManagedObjectModel
    ) throws -> SplitMigrationBookSummary {
        var cloudCounts: [String: Int] = [:]
        for entityName in SplitEntityConfiguration.cloudEntityNames(model: model) where entityName != "BookData" {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            cloudCounts[entityName] = try context.count(for: request)
        }
        var localCounts: [String: Int] = [:]
        for entityName in SplitEntityConfiguration.localEntityNames(model: model) {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            localCounts[entityName] = try context.count(for: request)
        }

        func sumAmount(entityName: String) throws -> Int {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
            let objects = try context.fetch(request)
            return objects.reduce(0) { $0 + Int(($1.value(forKey: "amount") as? Int64) ?? 0) }
        }

        return SplitMigrationBookSummary(
            bookId: bookId, cloudEntityCounts: cloudCounts, localEntityCounts: localCounts,
            expenseTotal: try sumAmount(entityName: "ExpenseData"),
            incomeTotal: try sumAmount(entityName: "IncomeData"),
            transferTotal: try sumAmount(entityName: "TransferData")
        )
    }
}
