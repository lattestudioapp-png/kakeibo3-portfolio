import XCTest
import CoreData
@testable import kakeibo3

// MARK: - Step 2B: Cloud/Local分割移行の回帰テスト
//
// この段階でもKakeibo3App / CoreDataStack.shared(通常起動での使用) / CloudKit同期ロジックには
// 一切触れない。productionDirectoryは実際のApplication Supportではなく、テストごとに
// 独立した一時ディレクトリを渡す。UserDefaultsも専用スイートを使い、実際の
// UserDefaults.standardを汚染しない。CoreDataStack(cloudLocalDirectory:)は必ず
// enableCloudKit: false, enableHistoryTracking: trueで呼ぶ(移行パイプライン自体が
// 実CloudKit接続を必要としないこと、および同一プロセス内で実CloudKit接続を繰り返し
// 生成すると無関係な別テストを不安定化させることを実測で確認したため)。

final class SplitMigrationBootstrapTests: XCTestCase {

    private var workDirectory: URL!
    private var productionDirectory: URL!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SplitMigrationBootstrapTests-\(UUID().uuidString)", isDirectory: true)
        workDirectory = root.appendingPathComponent("work", isDirectory: true)
        productionDirectory = root.appendingPathComponent("production", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: productionDirectory, withIntermediateDirectories: true)

        suiteName = "SplitMigrationBootstrapTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        if let root = workDirectory?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    private var pairPaths: SplitStorePromoter.PairPaths {
        SplitStorePromoter.PairPaths(
            directory: productionDirectory,
            cloudStoreName: CoreDataStack.cloudStoreFileName,
            localStoreName: CoreDataStack.localStoreFileName
        )
    }

    // MARK: - 旧Kakeibo3.sqlite(分割前の単一ストア)構築ヘルパー

    @discardableResult
    private func makeLegacyUnifiedStore(
        name: String = "legacy",
        _ build: (NSManagedObjectContext) -> Void
    ) throws -> LegacyUnifiedStoreLocator.Paths {
        let dir = workDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent(LegacyUnifiedStoreLocator.storeFileName)
        let stack = try CoreDataStack(throwingStoreURL: storeURL)
        let context = stack.container.viewContext
        build(context)
        try context.save()
        try stack.releasePersistentStoresForMigration()
        return LegacyUnifiedStoreLocator.paths(directory: dir)
    }

    @discardableResult
    private func insert(_ entityName: String, into context: NSManagedObjectContext, _ attributes: [String: Any?]) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
        for (key, value) in attributes {
            object.setValue(value, forKey: key)
        }
        return object
    }

    /// 1帳簿ぶんの標準的なデータ(Cloud13 Entity一式+Local4 Entity一式)を作る。
    @discardableResult
    private func makeStandardBook(
        _ context: NSManagedObjectContext, name: String = "帳簿A", expenseAmount: Int64 = 500, incomeAmount: Int64 = 800, transferAmount: Int64 = 300
    ) -> UUID {
        let bookId = UUID()
        insert("BookData", into: context, ["id": bookId, "name": name, "isMain": true, "createdAt": Date()])
        insert("CategoryData", into: context, ["id": UUID(), "bookId": bookId, "name": "食費", "colorHex": "#FF0000", "type": "expense", "createdAt": Date()])
        insert("CategoryData", into: context, ["id": UUID(), "bookId": bookId, "name": "給料", "colorHex": "#00FF00", "type": "income", "createdAt": Date()])
        insert("PaymentMethodSettingData", into: context, ["id": UUID(), "bookId": bookId, "methodName": "現金", "type": "cash", "createdAt": Date(), "updatedAt": Date()])
        insert("ReceiveMethodData", into: context, ["id": UUID(), "bookId": bookId, "methodName": "現金", "createdAt": Date()])
        insert("BankAccountData", into: context, ["id": UUID(), "bookId": bookId, "accountName": "三井住友銀行", "createdAt": Date(), "updatedAt": Date()])
        insert("ExpenseData", into: context, ["id": UUID(), "bookId": bookId, "amount": expenseAmount, "category": "食費", "paymentMethod": "現金", "memo": "", "date": Date(), "createdAt": Date()])
        insert("IncomeData", into: context, ["id": UUID(), "bookId": bookId, "amount": incomeAmount, "category": "給料", "receiveMethod": "現金", "memo": "", "date": Date(), "createdAt": Date()])
        insert("TransferData", into: context, ["id": UUID(), "bookId": bookId, "amount": transferAmount, "feeAmount": Int64(0), "fromType": "method", "fromName": "現金", "toType": "method", "toName": "現金", "memo": "", "date": Date(), "createdAt": Date(), "updatedAt": Date()])
        insert("BudgetData", into: context, ["id": UUID(), "bookId": bookId, "amount": Int64(10000), "categoryName": "食費", "year": Int64(2026), "month": Int64(1), "createdAt": Date(), "updatedAt": Date()])
        insert("RecurringBudgetData", into: context, ["id": UUID(), "bookId": bookId, "amount": Int64(10000), "categoryName": "食費", "isEnabled": true, "createdAt": Date(), "updatedAt": Date()])
        insert("FixedExpenseData", into: context, ["id": UUID(), "bookId": bookId, "name": "固定費", "amount": Int64(3000), "categoryName": "食費", "dayOfMonth": Int64(1), "startDate": Date(), "createdAt": Date(), "updatedAt": Date()])
        insert("RecurringIncomeData", into: context, ["id": UUID(), "bookId": bookId, "name": "定期収入", "amount": Int64(3000), "categoryName": "給料", "dayOfMonth": Int64(1), "startDate": Date(), "createdAt": Date(), "updatedAt": Date()])
        insert("RecurringTransferSettingData", into: context, ["id": UUID(), "bookId": bookId, "amount": Int64(1000), "day": Int64(1), "fromType": "method", "fromMethodName": "現金", "toType": "method", "toMethodName": "現金", "startDate": Date(), "createdAt": Date(), "updatedAt": Date()])
        insert("DailySnapshot", into: context, ["bookId": bookId, "date": Calendar.current.startOfDay(for: Date()), "expenseTotal": expenseAmount, "incomeTotal": incomeAmount, "updatedAt": Date()])
        insert("MonthlySnapshot", into: context, ["bookId": bookId, "yearMonth": "2026-01", "year": Int64(2026), "month": Int64(1), "expenseTotal": expenseAmount, "incomeTotal": incomeAmount, "updatedAt": Date()])
        insert("AnalysisMonthlySnapshot", into: context, ["bookId": bookId, "yearMonth": "2026-01", "year": Int64(2026), "month": Int64(1), "expenseTotal": expenseAmount, "incomeTotal": incomeAmount, "updatedAt": Date()])
        insert("AssetGraphCacheData", into: context, ["id": "totalAssets_\(bookId.uuidString)", "bookId": bookId, "granularityUsed": "daily", "firstDate": Date(), "lastDate": Date(), "updatedAt": Date()])
        return bookId
    }

    private func migrate(_ legacyPaths: LegacyUnifiedStoreLocator.Paths) -> SplitMigrationOutcome {
        SplitMigrationBootstrap.migrateAndPromote(
            legacyPaths: legacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
    }

    private func fetchCount(_ entityName: String, at directory: URL) throws -> Int {
        let stack = try CoreDataStack(cloudLocalDirectory: directory, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? stack.releasePersistentStoresForMigration() }
        return try stack.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
    }

    /// 注意: releasePersistentStoresForMigration()をdeferすると、呼び出し元がまだ返り値の
    /// NSManagedObjectから属性を読み取っていない時点でストアが切り離され、フェッチ済み
    /// オブジェクトがフォルト化されて値がnilになる(B2で実際に踏んだ実装ミスと同じ)。
    /// 呼び出し元が読み終わるまでstackを生かしたままにする。
    private func fetchAll(_ entityName: String, at directory: URL) throws -> (stack: CoreDataStack, objects: [NSManagedObject]) {
        let stack = try CoreDataStack(cloudLocalDirectory: directory, enableCloudKit: false, enableHistoryTracking: true)
        let objects = try stack.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: entityName))
        return (stack, objects)
    }

    // MARK: - 1. 旧storeなし

    func testNoLegacyStoreReturnsNotNeeded() {
        let outcome = SplitMigrationBootstrap.migrateAndPromoteIfNeeded(
            workDirectory: workDirectory, productionDirectory: productionDirectory, userDefaults: userDefaults
        )
        guard case .notNeeded = outcome else {
            return XCTFail("旧storeが無い場合はnotNeededであるべき: \(outcome)")
        }
    }

    // MARK: - 2. 空旧store

    func testEmptyLegacyStoreMigratesSuccessfully() throws {
        let legacyPaths = try makeLegacyUnifiedStore { _ in }
        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("空の旧storeでも移行自体は成功するべき")
        }
        XCTAssertTrue(manifest.sourceBookIDs.isEmpty)
        XCTAssertEqual(manifest.migrationState, .promoted)
    }

    // MARK: - 3. 単一帳簿

    func testSingleBookMigratesSuccessfully() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context)
        }
        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("単一帳簿の移行は成功するべき")
        }
        XCTAssertEqual(manifest.sourceBookIDs, [bookId])
        XCTAssertEqual(try fetchCount("BookData", at: productionDirectory), 1)
    }

    // MARK: - 4. 複数帳簿

    func testMultipleBooksMigrateAndStaySeparated() throws {
        var bookA: UUID!
        var bookB: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookA = self.makeStandardBook(context, name: "帳簿A", expenseAmount: 100, incomeAmount: 200, transferAmount: 10)
            bookB = self.makeStandardBook(context, name: "帳簿B", expenseAmount: 300, incomeAmount: 400, transferAmount: 20)
        }
        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("複数帳簿の移行は成功するべき")
        }
        XCTAssertEqual(Set(manifest.sourceBookIDs), Set([bookA, bookB]))
        XCTAssertEqual(try fetchCount("BookData", at: productionDirectory), 2)

        let bookASummary = try XCTUnwrap(manifest.bookSummaries.first { $0.bookId == bookA })
        let bookBSummary = try XCTUnwrap(manifest.bookSummaries.first { $0.bookId == bookB })
        XCTAssertEqual(bookASummary.expenseTotal, 100)
        XCTAssertEqual(bookBSummary.expenseTotal, 300)
    }

    // MARK: - 5. 支出/収入/振替、8. 予算、9. 固定費、10. 定期収入、11. 定期振替(すべてmakeStandardBookで一括カバー)
    // MARK: - 6. カテゴリー、7. 支払い/受け取り方法

    func testAllCloudEntityTypesMigrate() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }
        for entityName in [
            "BookData", "ExpenseData", "IncomeData", "TransferData",
            "PaymentMethodSettingData", "BankAccountData", "ReceiveMethodData", "BudgetData",
            "RecurringBudgetData", "FixedExpenseData", "RecurringIncomeData", "RecurringTransferSettingData",
        ] {
            XCTAssertEqual(manifest.cloudEntityCounts[entityName], 1, "\(entityName)が1件Cloud側へ移行されているはず")
        }
        // makeStandardBookは支出用/収入用の2カテゴリーを作るため、CategoryDataだけ2件が正しい。
        XCTAssertEqual(manifest.cloudEntityCounts["CategoryData"], 2, "CategoryDataが2件(支出/収入)Cloud側へ移行されているはず")
    }

    // MARK: - 12. ゴミ箱状態

    func testTrashedExpenseSurvivesMigration() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context)
            self.insert("ExpenseData", into: context, [
                "id": UUID(), "bookId": bookId, "amount": Int64(9999), "category": "食費",
                "paymentMethod": "現金", "memo": "", "date": Date(), "createdAt": Date(),
                "isInTrash": true, "trashedAt": Date(),
            ])
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("ゴミ箱データを含む移行は成功するべき")
        }
        let (stack, expenses) = try fetchAll("ExpenseData", at: productionDirectory)
        XCTAssertEqual(expenses.count, 2, "ゴミ箱の支出も削除せずそのまま移行すること")
        XCTAssertTrue(expenses.contains { ($0.value(forKey: "isInTrash") as? Bool) == true })
        _ = stack
    }

    // MARK: - 13. 使用停止/保護/ロック

    func testSuspendedProtectedLockedStateSurvivesMigration() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            let bookId = self.makeStandardBook(context)
            self.insert("CategoryData", into: context, [
                "id": UUID(), "bookId": bookId, "name": "使わないカテゴリー", "colorHex": "#000000",
                "type": "expense", "createdAt": Date(), "isSuspended": true, "isProtected": true,
            ])
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("使用停止/保護状態を含む移行は成功するべき")
        }
        let (stack, categories) = try fetchAll("CategoryData", at: productionDirectory)
        XCTAssertTrue(categories.contains { ($0.value(forKey: "isSuspended") as? Bool) == true && ($0.value(forKey: "isProtected") as? Bool) == true })
        _ = stack
    }

    // MARK: - 14. 休日調整情報

    func testHolidayAdjustmentSurvivesMigration() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            let bookId = self.makeStandardBook(context)
            self.insert("FixedExpenseData", into: context, [
                "id": UUID(), "bookId": bookId, "name": "休日調整固定費", "amount": Int64(1000),
                "categoryName": "食費", "dayOfMonth": Int64(1), "startDate": Date(), "createdAt": Date(),
                "updatedAt": Date(), "holidayAdjustment": "shiftLater",
            ])
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("休日調整情報を含む移行は成功するべき")
        }
        let (stack, fixedExpenses) = try fetchAll("FixedExpenseData", at: productionDirectory)
        XCTAssertTrue(fixedExpenses.contains { ($0.value(forKey: "holidayAdjustment") as? String) == "shiftLater" })
        _ = stack
    }

    // MARK: - 15. receiptImagePath

    func testReceiptImagePathSurvivesMigration() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            let bookId = self.makeStandardBook(context)
            self.insert("ExpenseData", into: context, [
                "id": UUID(), "bookId": bookId, "amount": Int64(100), "category": "食費",
                "paymentMethod": "現金", "memo": "", "date": Date(), "createdAt": Date(),
                "receiptImagePath": "receipt-abc123.jpg",
            ])
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("receiptImagePathを含む移行は成功するべき")
        }
        let (stack, expenses) = try fetchAll("ExpenseData", at: productionDirectory)
        XCTAssertTrue(expenses.contains { ($0.value(forKey: "receiptImagePath") as? String) == "receipt-abc123.jpg" })
        _ = stack
    }

    // MARK: - 16. Cloud13 Entity件数一致、17. Local4 Entity件数一致

    func testCloudAndLocalEntityCountsMatchManifest() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }
        for entityName in ["DailySnapshot", "MonthlySnapshot", "AnalysisMonthlySnapshot", "AssetGraphCacheData"] {
            XCTAssertEqual(manifest.localEntityCounts[entityName], 1, "\(entityName)が1件Local側へ移行されているはず")
            XCTAssertEqual(try fetchCount(entityName, at: productionDirectory), 1)
        }
        for entityName in manifest.cloudEntityCounts.keys {
            XCTAssertEqual(try fetchCount(entityName, at: productionDirectory), manifest.cloudEntityCounts[entityName])
        }
    }

    // MARK: - 18. UUID維持

    func testUUIDsArePreservedAfterMigration() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context)
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }
        let (stack, books) = try fetchAll("BookData", at: productionDirectory)
        XCTAssertEqual(books.first?.value(forKey: "id") as? UUID, bookId)
        _ = stack
    }

    // MARK: - 19. 帳簿別金額チェックサム一致

    func testBookAmountsMatchAfterMigration() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context, expenseAmount: 1234, incomeAmount: 5678, transferAmount: 90)
        }
        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }
        let summary = try XCTUnwrap(manifest.bookSummaries.first { $0.bookId == bookId })
        XCTAssertEqual(summary.expenseTotal, 1234)
        XCTAssertEqual(summary.incomeTotal, 5678)
        XCTAssertEqual(summary.transferTotal, 90)

        let (stack, expenses) = try fetchAll("ExpenseData", at: productionDirectory)
        XCTAssertEqual(expenses.reduce(0) { $0 + (($1.value(forKey: "amount") as? Int64) ?? 0) }, 1234)
        _ = stack
    }

    // MARK: - 20. 同名カテゴリーの帳簿分離

    func testSameNameCategoryStaysSeparatedAcrossBooks() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context, name: "帳簿A")
            self.makeStandardBook(context, name: "帳簿B")
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }
        let (stack, categories) = try fetchAll("CategoryData", at: productionDirectory)
        let foodCategories = categories.filter { ($0.value(forKey: "name") as? String) == "食費" }
        XCTAssertEqual(foodCategories.count, 2, "同名カテゴリーが帳簿ごとに別行として残ること")
        XCTAssertEqual(Set(foodCategories.compactMap { $0.value(forKey: "bookId") as? UUID }).count, 2, "bookIdで正しく分離されていること")
        _ = stack
    }

    // MARK: - 21. WAL未checkpointデータ維持

    func testUncheckpointedWALDataSurvivesMigration() throws {
        let dir = workDirectory.appendingPathComponent("legacy-wal", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent(LegacyUnifiedStoreLocator.storeFileName)

        var bookId: UUID!
        do {
            let stack = try CoreDataStack(throwingStoreURL: storeURL)
            bookId = makeStandardBook(stack.container.viewContext, expenseAmount: 4242)
            try stack.container.viewContext.save()
            // stackをreleaseせずスコープを抜ける(WALが本体へcheckpointされない状態を作る)。
        }

        let legacyPaths = LegacyUnifiedStoreLocator.paths(directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPaths.wal.path), "-walファイルが残っていること(前提条件)")

        guard case .promoted(let manifest) = migrate(legacyPaths) else {
            return XCTFail("WAL未checkpointの旧storeでも移行は成功するべき")
        }
        let summary = try XCTUnwrap(manifest.bookSummaries.first { $0.bookId == bookId })
        XCTAssertEqual(summary.expenseTotal, 4242, "WALにしか無かった値も読み取れていること")
    }

    // MARK: - 22. Case Cで上書きしない

    func testCaseCRefusesAutomaticOverwrite() throws {
        // 本番Cloud/Localへ実データを直接作る(移行を経由しないCase C再現)。
        let stack = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false, enableHistoryTracking: true)
        let context = stack.container.viewContext
        insert("ExpenseData", into: context, ["id": UUID(), "bookId": UUID(), "amount": Int64(12345), "category": "食費", "paymentMethod": "現金", "memo": "", "date": Date(), "createdAt": Date()])
        try context.save()
        try stack.releasePersistentStoresForMigration()

        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }

        let outcome = migrate(legacyPaths)
        guard case .failed(.productionStoreHasExistingData) = outcome else {
            return XCTFail("Case C(本番に実データあり)では自動上書きせず失敗として返すべき: \(outcome)")
        }
        // 旧storeも本番も変更されていないこと
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPaths.store.path), "失敗時は旧storeを必ず残すこと")
        XCTAssertEqual(try fetchCount("ExpenseData", at: productionDirectory), 1, "既存の本番データが変更されていないこと")
    }

    // MARK: - 23. Manifest欠落

    func testMissingManifestDoesNotCountAsAlreadyMigrated() throws {
        // Case Cを作るが、Manifest/フラグは無い状態(=移行済みと確認できない)。
        let stack = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false, enableHistoryTracking: true)
        let context = stack.container.viewContext
        insert("ExpenseData", into: context, ["id": UUID(), "bookId": UUID(), "amount": Int64(1), "category": "食費", "paymentMethod": "現金", "memo": "", "date": Date(), "createdAt": Date()])
        try context.save()
        try stack.releasePersistentStoresForMigration()

        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        guard case .failed(.productionStoreHasExistingData) = migrate(legacyPaths) else {
            return XCTFail("Manifestが無ければalreadyMigrated扱いにしてはいけない")
        }
    }

    // MARK: - 24. Manifest破損

    func testCorruptManifestDoesNotCountAsAlreadyMigrated() throws {
        let stack = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false, enableHistoryTracking: true)
        let context = stack.container.viewContext
        insert("ExpenseData", into: context, ["id": UUID(), "bookId": UUID(), "amount": Int64(1), "category": "食費", "paymentMethod": "現金", "memo": "", "date": Date(), "createdAt": Date()])
        try context.save()
        try stack.releasePersistentStoresForMigration()

        try "not valid json".write(
            to: productionDirectory.appendingPathComponent(SplitMigrationCompletionRecorder.manifestFileName),
            atomically: true, encoding: .utf8
        )
        SplitMigrationCompletionRecorder.markCompleted(in: userDefaults)

        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        guard case .failed(.productionStoreHasExistingData) = migrate(legacyPaths) else {
            return XCTFail("Manifestが破損していればalreadyMigrated扱いにしてはいけない")
        }
    }

    // MARK: - 25. 昇格途中クラッシュ

    func testCrashDuringLegacyEvacuatedPhaseRecoversToPromotedState() throws {
        // stagingReady→legacyEvacuatedまで進めたところでクラッシュしたのを再現する:
        // .incomingファイルを本番ディレクトリへ直接置き、ジャーナルをlegacyEvacuatedにして
        // recoverIfNeededを呼ぶ。
        let cloudIncoming = pairPaths.cloud.incomingStore
        let localIncoming = pairPaths.local.incomingStore
        try "CLOUD-INCOMING".write(to: cloudIncoming, atomically: true, encoding: .utf8)
        try "LOCAL-INCOMING".write(to: localIncoming, atomically: true, encoding: .utf8)
        try SplitPromotionJournal(
            phase: .legacyEvacuated, startedAt: Date(),
            tempCloudStoreSourcePath: "/dummy-cloud", tempLocalStoreSourcePath: "/dummy-local"
        ).write(to: productionDirectory)

        SplitStorePromoter.recoverIfNeeded(paths: pairPaths)

        XCTAssertEqual(try String(contentsOf: pairPaths.cloud.store, encoding: .utf8), "CLOUD-INCOMING")
        XCTAssertEqual(try String(contentsOf: pairPaths.local.store, encoding: .utf8), "LOCAL-INCOMING")
        XCTAssertNil(SplitPromotionJournal.load(from: productionDirectory), "復旧後はジャーナルを消すこと")
    }

    func testCrashDuringStagingReadyPhaseLeavesProductionUntouched() throws {
        try "OLD-CLOUD".write(to: pairPaths.cloud.store, atomically: true, encoding: .utf8)
        try "OLD-LOCAL".write(to: pairPaths.local.store, atomically: true, encoding: .utf8)
        try "INCOMING-CLOUD".write(to: pairPaths.cloud.incomingStore, atomically: true, encoding: .utf8)
        try SplitPromotionJournal(
            phase: .stagingReady, startedAt: Date(),
            tempCloudStoreSourcePath: "/dummy-cloud", tempLocalStoreSourcePath: "/dummy-local"
        ).write(to: productionDirectory)

        SplitStorePromoter.recoverIfNeeded(paths: pairPaths)

        XCTAssertEqual(try String(contentsOf: pairPaths.cloud.store, encoding: .utf8), "OLD-CLOUD", "stagingReady中断時は本番パスへ一切手を付けていないはず")
        XCTAssertEqual(try String(contentsOf: pairPaths.local.store, encoding: .utf8), "OLD-LOCAL")
    }

    // MARK: - 26. 退避途中クラッシュ

    func testPartialLegacyEvacuationThrowsPartialEvacuationError() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        do {
            try SplitLegacyStoreEvacuator.evacuate(paths: legacyPaths, move: { source, destination in
                if source.lastPathComponent == LegacyUnifiedStoreLocator.storeFileName {
                    throw NSError(domain: "test", code: 1)
                }
                try FileManager.default.moveItem(at: source, to: destination)
            })
            XCTFail("一部のファイルの移動が失敗したらpartialEvacuationを投げるべき")
        } catch SplitLegacyStoreEvacuator.EvacuationError.partialEvacuation {
            // 期待通り
        }
        XCTAssertFalse(SplitLegacyStoreEvacuator.isFullyEvacuated(paths: legacyPaths))
    }

    // MARK: - 27. 二重実行

    func testRunningTwiceDoesNotDuplicateData() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("1回目の移行は成功するべき")
        }
        XCTAssertEqual(try fetchCount("BookData", at: productionDirectory), 1)

        // 2回目: 旧storeは既に退避済みなので、IfNeeded経由ではnotNeededになるはず
        // (=重複移行が起きない)。
        let secondOutcome = SplitMigrationBootstrap.migrateAndPromoteIfNeeded(
            workDirectory: workDirectory, productionDirectory: productionDirectory, userDefaults: userDefaults
        )
        guard case .notNeeded = secondOutcome else {
            return XCTFail("旧storeが既に退避済みなら2回目はnotNeededであるべき: \(secondOutcome)")
        }
        XCTAssertEqual(try fetchCount("BookData", at: productionDirectory), 1, "2回目の実行でデータが重複していないこと")
    }

    func testRerunAfterPromotionRecognizesAlreadyMigrated() throws {
        let legacyPaths = try makeLegacyUnifiedStore { context in
            self.makeStandardBook(context)
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("1回目の移行は成功するべき")
        }

        // 旧storeを人為的に復元し、同じproductionDirectoryへ直接migrateAndPromoteを
        // もう一度呼ぶ(Case C + 既に今回の移行結果と同一と確認できるケース)。
        let secondLegacyPaths = try makeLegacyUnifiedStore(name: "legacy2") { context in
            self.makeStandardBook(context)
        }
        let outcome = SplitMigrationBootstrap.migrateAndPromote(
            legacyPaths: secondLegacyPaths, workDirectory: workDirectory,
            productionDirectory: productionDirectory, userDefaults: userDefaults
        )
        guard case .alreadyMigrated = outcome else {
            return XCTFail("既に移行済みの本番ストアに対しては、alreadyMigratedとして安全に扱うべき: \(outcome)")
        }
        XCTAssertEqual(try fetchCount("BookData", at: productionDirectory), 1, "再実行で重複・上書きが起きていないこと")
    }

    // MARK: - 28. 本番2ストア再起動

    func testProductionStoresSurviveRealRestartAfterMigration() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context)
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }

        let reopened = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? reopened.releasePersistentStoresForMigration() }
        let request = NSFetchRequest<NSManagedObject>(entityName: "BookData")
        request.predicate = NSPredicate(format: "id == %@", bookId as CVarArg)
        let books = try reopened.container.viewContext.fetch(request)
        XCTAssertEqual(books.count, 1, "昇格後、本番2ストアを再オープンしてもデータが残っていること")
    }

    // MARK: - 29. Local派生データ再生成

    func testLocalDataCanBeRegeneratedFromCloudDataAfterMigration() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context, expenseAmount: 700, incomeAmount: 0, transferAmount: 0)
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }

        CoreDataStack.shared = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? CoreDataStack.shared.releasePersistentStoresForMigration() }

        // Local側(DailySnapshot等)を全て削除しても、Cloud側の元データから再生成できることを確認する。
        try SnapshotManager.rebuildAll(bookId: bookId)
        let monthly = MonthlySnapshotSync.fetchAll(bookId: bookId)
        XCTAssertFalse(monthly.isEmpty, "移行後の帳簿でもSnapshotの再生成が正常に動くこと")
        XCTAssertEqual(monthly.reduce(0) { $0 + $1.expenseTotal }, 700)
    }

    // MARK: - 30. バックアップ/復元継続動作

    func testBackupAndRestoreContinueToWorkAfterMigration() throws {
        var bookId: UUID!
        let legacyPaths = try makeLegacyUnifiedStore { context in
            bookId = self.makeStandardBook(context, expenseAmount: 250, incomeAmount: 0, transferAmount: 0)
        }
        guard case .promoted = migrate(legacyPaths) else {
            return XCTFail("移行は成功するべき")
        }

        CoreDataStack.shared = try CoreDataStack(cloudLocalDirectory: productionDirectory, enableCloudKit: false, enableHistoryTracking: true)
        defer { try? CoreDataStack.shared.releasePersistentStoresForMigration() }

        // 移行後の帳簿に対して、既存のCloud対象*DataSync経路(ExpenseDataSync等)が
        // そのまま正常に読み書きできることを確認する(バックアップ/復元が内部で使うのと
        // 同じ経路)。
        let expenses = ExpenseDataSync.fetchAll(bookId: bookId)
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.amount, 250)

        var newExpense = ExpenseData(amount: 999, date: Date(), paymentMethod: "現金", category: "食費", memo: "復元テスト")
        newExpense.bookId = bookId
        ExpenseDataSync.insert(newExpense)
        XCTAssertEqual(ExpenseDataSync.fetchAll(bookId: bookId).count, 2, "移行後の帳簿への新規書き込みが正常に行えること")
    }
}
