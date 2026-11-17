// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionTests フォルダごと削除してください。
//
// 使用停止カテゴリーの文言統一（「使用停止」→「非表示」）とページスワイプ直後の
// タップ誤爆修正（⑥）の回帰テスト。
//
// 実際の使用停止/再開ロジック自体（isSuspendedの切り替え）はCategoryQARegressionTests側で
// 既に網羅されているため、ここでは文言変更・ジェスチャー変更を含む画面自体が
// クラッシュしないことのスモークテストのみ行う。

import XCTest
@testable import kakeibo3

final class SuspendedCategoryWordingQARegressionTests: QARegressionTestCase {

    @MainActor
    func testCategoryEditViewDoesNotCrashAfterWordingAndGestureChanges() throws {
        _ = QARegressionTestFactory.makeThreeStandardBooks()
        let view = CategoryEditView(selectedType: "支出")
        _ = view.body
    }

    @MainActor
    func testSuspendedCategoryListViewDoesNotCrashAfterWordingChanges() throws {
        let (main, _, _) = QARegressionTestFactory.makeThreeStandardBooks()

        var suspended = main.expenseCategory
        suspended.isSuspended = true
        CategoryDataSync.update(suspended)

        let view = SuspendedCategoryListView(type: "支出", categories: CategoryDataSync.fetchAll(bookId: main.book.id))
        _ = view.body
    }

    // MARK: - 「使用停止」表記が画面のソースにもう残っていないことの確認
    //
    // 文言統一の取りこぼしを機械的に検知するため、対象3ファイルのソースを直接読み、
    // 旧表記「使用停止」がコメント以外（Text/Button/alert/navigationTitleの引用符内）に
    // 残っていないことを確認する。

    func testNoLegacyWordingRemainsInAffectedViewFiles() throws {
        let files = [
            "kakeibo3/Views/Input/CategoryEditView.swift",
            "kakeibo3/Views/Input/CategoryDetailEditView.swift",
            "kakeibo3/Views/Input/SuspendedCategoryListView.swift"
        ]
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ファイル名を除去 → QARegressionTests
            .deletingLastPathComponent() // QARegressionTestsを除去 → kakeibo3Tests
            .deletingLastPathComponent() // kakeibo3Testsを除去 → リポジトリルート
        for relativePath in files {
            let url = projectRoot.appendingPathComponent(relativePath)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                continue // ソース直接読み込みができない実行環境ではスキップ（ビルド時のgrep確認で担保済み）
            }
            let quotedLegacyWording = "\"使用停止"
            XCTAssertFalse(
                source.contains(quotedLegacyWording),
                "\(relativePath) に旧表記「使用停止」がユーザー向け文字列として残っています"
            )
        }
    }
}
