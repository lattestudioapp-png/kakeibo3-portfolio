import CoreData
import Foundation
import XCTest
@testable import kakeibo3

// MARK: - CoreDataConcurrencyHeavyStressTests
//
// CoreDataConcurrencyStressTestsの深掘り版。同じ再現シナリオを100回反復・最大10並行
// TaskGroupという、通常の回帰確認には過剰な規模で流す。
//
// 【このクラスは通常のフルスイート実行に含めないこと】
// 通常の回帰確認は軽量な`CoreDataConcurrencyStressTests`（20回反復・4並行）に任せ、
// このクラスはCore Data並行処理まわりを深く調査する時だけ明示的に単体指定して実行する
// （例: `xcodebuild test -only-testing:kakeibo3Tests/CoreDataConcurrencyHeavyStressTests`）。
// フルスイートを回す際は `-skip-testing:kakeibo3Tests/CoreDataConcurrencyHeavyStressTests` を
// 付けること。
//
// 【2026-10-18 根本原因の確定・CoreDataConcurrencyStressTests.swiftと同一の修正】
// このファイルも、ExpenseData/CategoryData/BookData/PaymentMethodSettingData/
// AssetGraphCacheDataの各structとCore Data層の同期APIが@MainActor隔離されているのに、
// async（MainActor指定なし）のテストメソッドから awaitを付けずに直接触っていた。
// 詳細な経緯はCoreDataConcurrencyStressTests.swiftの冒頭コメント参照。
final class CoreDataConcurrencyHeavyStressTests: QARegressionTestCase {

    private let stressIterations = 100

    func testCategoryInsertFromAsyncTaskRepeatedly() async throws {
        let book = await MainActor.run { QARegressionTestFactory.makeBook(name: "HeavyStressCategory") }
        for i in 0..<stressIterations {
            let category = await MainActor.run { () -> CategoryData in
                var category = CategoryData(name: "cat\(i)", colorHex: "#6FA58C", type: "支出", sortOrder: i)
                category.bookId = book.id
                return category
            }
            try await CategoryDataSync.insertAsync(category)
        }
        let count = await MainActor.run { CategoryDataSync.fetchAll(bookId: book.id).count }
        XCTAssertEqual(count, stressIterations)
    }

    func testPaymentMethodInsertFromAsyncTaskRepeatedly() async throws {
        let book = await MainActor.run { QARegressionTestFactory.makeBook(name: "HeavyStressPaymentMethod") }
        for i in 0..<stressIterations {
            let method = await MainActor.run { () -> PaymentMethodSettingData in
                var method = PaymentMethodSettingData(methodName: "pm\(i)", type: PaymentMethodType.other.rawValue)
                method.bookId = book.id
                return method
            }
            try await PaymentMethodSettingDataSync.insertAsync(method)
        }
        let count = await MainActor.run { PaymentMethodSettingDataSync.fetchAll(bookId: book.id).count }
        XCTAssertEqual(count, stressIterations)
    }

    func testSeedStandardDataRepeatedlyFromAsyncTest() async throws {
        for i in 0..<stressIterations {
            let (bookId, fixtureBookId) = await MainActor.run { () -> (UUID, UUID) in
                let book = QARegressionTestFactory.makeBook(name: "HeavySeedStress\(i)")
                let fixture = QARegressionTestFactory.seedStandardData(book: book)
                return (book.id, fixture.book.id)
            }
            XCTAssertEqual(fixtureBookId, bookId, "iteration \(i)")
        }
    }

    func testSeedStandardDataAsyncRepeatedlyFromAsyncTest() async throws {
        for i in 0..<stressIterations {
            let book = try await QARegressionTestFactory.makeBookAsync(name: "HeavySeedStressAsync\(i)")
            let fixture = try await QARegressionTestFactory.seedStandardDataAsync(book: book)
            let (bookId, fixtureBookId) = await MainActor.run { (book.id, fixture.book.id) }
            XCTAssertEqual(fixtureBookId, bookId, "iteration \(i)")
        }
    }

    func testConcurrentInsertsAcrossMultipleBooks() async throws {
        let bookCount = 10
        let perBookInserts = 20
        let books = await MainActor.run {
            (0..<bookCount).map { QARegressionTestFactory.makeBook(name: "HeavyConcurrentBook\($0)") }
        }
        let bookIds = await MainActor.run { books.map(\.id) }
        let bookNames = await MainActor.run { books.map(\.name) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for bookId in bookIds {
                group.addTask {
                    for i in 0..<perBookInserts {
                        let category = await MainActor.run { () -> CategoryData in
                            var category = CategoryData(name: "c\(i)", colorHex: "#5A9ED8", type: "支出", sortOrder: i)
                            category.bookId = bookId
                            return category
                        }
                        try await CategoryDataSync.insertAsync(category)
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            CoreDataStack.shared.container.viewContext.performAndWait {}
        }

        for (bookId, bookName) in zip(bookIds, bookNames) {
            let count = await MainActor.run { CategoryDataSync.fetchAll(bookId: bookId).count }
            XCTAssertEqual(count, perBookInserts, "book \(bookName)")
        }
    }

    func testAssetGraphCacheRebuildImmediatelyAfterInsertRepeatedly() async throws {
        for i in 0..<stressIterations {
            let bookId = await MainActor.run { () -> UUID in
                let book = QARegressionTestFactory.makeBook(name: "HeavyAssetStress\(i)")
                let fixture = QARegressionTestFactory.seedStandardData(book: book)
                var expense = ExpenseData(
                    amount: 250, date: Date(), paymentMethod: fixture.cash.methodName,
                    category: fixture.expenseCategory.name, memo: ""
                )
                expense.bookId = book.id
                ExpenseDataSync.insert(expense)
                return book.id
            }

            try await AssetGraphCacheService.rebuildTotalAssetsCache(bookId: bookId, maxPoints: 100)

            let (cacheExists, pointsIsEmpty) = await MainActor.run { () -> (Bool, Bool) in
                let cache = AssetGraphCacheService.fetchTotalAssetsCache(bookId: bookId)
                return (cache != nil, cache?.points.isEmpty ?? true)
            }
            XCTAssertTrue(cacheExists, "iteration \(i)")
            XCTAssertFalse(pointsIsEmpty, "iteration \(i)")
        }
    }

    func testFetchImmediatelyAfterAsyncInsertRepeatedly() async throws {
        let book = await MainActor.run { QARegressionTestFactory.makeBook(name: "HeavyFetchStress") }
        for i in 0..<stressIterations {
            let category = await MainActor.run { () -> CategoryData in
                var category = CategoryData(name: "fetchcat\(i)", colorHex: "#B0785A", type: "支出", sortOrder: i)
                category.bookId = book.id
                return category
            }
            try await CategoryDataSync.insertAsync(category)
            let fetched = await MainActor.run { CategoryDataSync.fetch(id: category.id) }
            XCTAssertNotNil(fetched, "iteration \(i)")
        }
    }
}
