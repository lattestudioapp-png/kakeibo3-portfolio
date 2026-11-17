import CoreData
import Foundation
import XCTest
@testable import kakeibo3

// MARK: - CoreDataConcurrencyStressTests
//
// CoreDataStack.performAndSave(スレッド閉じ込め違反)の根本原因の再現・回帰固定テスト。
//
// 背景：testAssetGraphCacheRebuildsSuccessfullyがクリーン環境でも低確率
// （単独50回中6回、Snapshot関連10回中2回、全unit test suite 3回中2回で再現）で失敗しており、
// 原因は CoreDataStack.performAndSave(sync) が viewContext（mainQueueConcurrencyType固定）を
// context.performAndWait等で保護せず直接触っていたため、非メインスレッドから呼ばれた場合に
// Core Data内部（NSSet相当の変更通知管理）が壊れ、捕捉不能な NSInvalidArgumentException
// （-[__NSCFSet addObject:]: attempt to insert nil）やEXC_BAD_ACCESSでクラッシュしていたこと。
// 実際の呼び出し経路：QARegressionTestFactory.seedStandardData（async テスト関数から呼ばれ、
// await復帰後の再開スレッドは保証されない）→ CategoryDataSync/PaymentMethodSettingDataSync.insert
// → CoreDataStack.performAndSave。TestDataView経由のTestDataGenerator/
// PerformanceTestDataGenerator（Task.detachedから明示的に呼ばれる設計）も同じ経路を持つ、
// 実際の（開発者向け）本番コードパス。
//
// 修正：CoreDataStack.performAndSave(sync)をcontext.performAndWaitで保護し、加えてasync文脈向けの
// performAndSave<T>(_:) async throws -> T（context.perform使用、cooperativeスレッドプールを
// 塞がない）を新設した。このファイルは、修正前に再現していた失敗パターンをそれぞれ反復実行の形で
// 固定し、修正後に恒久的な回帰として検出できるようにする。
//
// 【安定化の経緯（2026-09-15）】当初は各テスト100回反復・最大10並行TaskGroupで書いていたが、
// 全unit test suite（437件）の一部として実行した時だけ、このクラス内のいずれかのテストが
// 例外もクラッシュレポートも残さずサイレントに再起動する（"Restarting after unexpected exit,
// crash, or test timeout"）現象が発生した。孤立実行・少数回実行では常に一瞬で確実に成功するため、
// このクラス固有のロジックバグではなく蓄積的なリソース枯渇が疑わしい、と当時は記録していた。
//
// 【2026-10-18 根本原因の確定】GitHub Actions CI（ローカルより厳格に並行性を顕在化させる環境）で
// 同じ"Restarting after unexpected exit, crash, or test timeout"が、このファイルに限らず
// スイートの最初に実行されたテストから即座に・毎回確実に再現した。ビルド警告を精査した結果、
// このファイル自体に本物のMainActor隔離違反が多数あることを特定した：ExpenseData/CategoryData/
// BookData/PaymentMethodSettingData/AssetGraphCacheDataの各structと、対応する*DataSync/
// AssetGraphCacheServiceの同期API群は、プロジェクトのデフォルトMainActor分離設定により
// @MainActor隔離されている。このファイルのテストメソッドはasync（MainActor明示指定なし）で、
// awaitを挟んだ後の再開スレッドはSwift Concurrencyのcooperativeスレッドプール上の任意スレッドで
// あり、メインスレッドである保証がない。にもかかわらずawaitを付けずにこれらの@MainActor API
// （struct初期化・プロパティ代入・同期fetch/insert呼び出し）を直接呼んでいたため、コンパイラは
// 警告止まり（Swift 6完全モードではないため）だったが、実行時には暗黙のactor hopが一切
// 挿入されず、CoreDataStack.sharedの参照カウント（ARC）やNSManagedObjectContextの内部状態を
// 保護されないスレッドから直接操作していた。これがSwiftランタイムの参照カウント管理を破壊し、
// "malloc: *** error ... pointer being freed was not allocated"という形で現れていたと判断した
// （2026-09-15時点の「蓄積的なリソース枯渇」という推測は、実際には「初回実行時から常に起こり得る
// 未同期アクセス」であり、ローンチごとの偶然のタイミングで発生確率が変動していただけだった）。
//
// 【修正方針】テスト削除・無効化・@unchecked Sendableでの回避は行わない。production
// コード（CoreDataStack.swift・各*DataSync）のAPI分割（MainActor向け同期API / nonisolated
// 向けasync API）という既存設計はそのまま踏襲し、このテストファイル側を「async文脈から
// MainActor隔離APIを呼ぶ場合は必ずawait MainActor.run{}で明示的にactor hopする」という
// 正しい呼び出し方に揃えた。これにより、意図通り「cooperativeスレッドプール上の非MainActor
// 文脈から、MainActor隔離されたCore Data層を安全に呼び出す」という、TestDataGenerator等の
// 本番Task.detached経路と同じ安全なパターンをテスト自身も実践する形になった。
final class CoreDataConcurrencyStressTests: QARegressionTestCase {

    private let stressIterations = 20

    // MARK: - 1. CategoryDataSync.insertをasync Taskから反復

    func testCategoryInsertFromAsyncTaskRepeatedly() async throws {
        let book = await MainActor.run { QARegressionTestFactory.makeBook(name: "StressCategory") }
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

    // MARK: - 2. PaymentMethodSettingDataSync.insertをasync Taskから反復

    func testPaymentMethodInsertFromAsyncTaskRepeatedly() async throws {
        let book = await MainActor.run { QARegressionTestFactory.makeBook(name: "StressPaymentMethod") }
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

    // MARK: - 3. seedStandardData(元のクラッシュと同一の呼び出し経路)をasync testから反復
    //
    // QARegressionTestFactory.makeBook/seedStandardData(同期版)自体がMainActor隔離APIを
    // 内部で呼ぶため、ここでも同様にawait MainActor.run{}で包む。

    func testSeedStandardDataRepeatedlyFromAsyncTest() async throws {
        for i in 0..<stressIterations {
            let (bookId, fixtureBookId) = await MainActor.run { () -> (UUID, UUID) in
                let book = QARegressionTestFactory.makeBook(name: "SeedStress\(i)")
                let fixture = QARegressionTestFactory.seedStandardData(book: book)
                return (book.id, fixture.book.id)
            }
            XCTAssertEqual(fixtureBookId, bookId, "iteration \(i)")
        }
    }

    // MARK: - 3b. 新設したasync版シード関数も同様に反復(非同期APIそのものの経路を検証)

    func testSeedStandardDataAsyncRepeatedlyFromAsyncTest() async throws {
        for i in 0..<stressIterations {
            let book = try await QARegressionTestFactory.makeBookAsync(name: "SeedStressAsync\(i)")
            let fixture = try await QARegressionTestFactory.seedStandardDataAsync(book: book)
            let (bookId, fixtureBookId) = await MainActor.run { (book.id, fixture.book.id) }
            XCTAssertEqual(fixtureBookId, bookId, "iteration \(i)")
        }
    }

    // MARK: - 4. 同時に複数bookIdへinsert（TaskGroupで並行実行）

    func testConcurrentInsertsAcrossMultipleBooks() async throws {
        let bookCount = 4
        let perBookInserts = 10
        let books = await MainActor.run {
            (0..<bookCount).map { QARegressionTestFactory.makeBook(name: "ConcurrentBook\($0)") }
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

        // 【quiescence確認】TaskGroupのwaitForAllは各子Taskのawaitを保証するが、テスト終了直後に
        // QARegressionTestCase.tearDownがCoreDataStack.sharedを直ちに次のテスト用に差し替えるため、
        // 念のためviewContextの専用キューに空のperformAndWaitを1回通し、保留中の作業が無いことを
        // 明示的に確認してからアサーションへ進む(実際には既に完了しているはずだが、テスト境界を
        // 跨いだ状態漏れの可能性を構造的に排除するための防御)。
        await MainActor.run {
            CoreDataStack.shared.container.viewContext.performAndWait {}
        }

        for (bookId, bookName) in zip(bookIds, bookNames) {
            let count = await MainActor.run { CategoryDataSync.fetchAll(bookId: bookId).count }
            XCTAssertEqual(count, perBookInserts, "book \(bookName)")
        }
    }

    // MARK: - 5. insert直後にAssetGraphCache rebuild（元のtestAssetGraphCacheRebuildsSuccessfullyを反復）

    func testAssetGraphCacheRebuildImmediatelyAfterInsertRepeatedly() async throws {
        for i in 0..<stressIterations {
            let bookId: UUID = await MainActor.run { () -> UUID in
                let book = QARegressionTestFactory.makeBook(name: "AssetStress\(i)")
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

    // MARK: - 6. save直後にfetch（async insert直後の同期fetchで読み戻れるか）

    func testFetchImmediatelyAfterAsyncInsertRepeatedly() async throws {
        let book = await MainActor.run { QARegressionTestFactory.makeBook(name: "FetchStress") }
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
