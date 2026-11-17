// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// 全QARegressionUITestsの共通基底クラス。
// - テスト開始前に、前回までに残った QART_ / QARegression_ 接頭辞のデータを一掃する
// - テスト終了後（成功・失敗・途中終了を問わず）、そのテストが作成したデータを必ず削除する
//   addTeardownBlock はテストの成否に関わらず必ず実行されるため、後始末の主経路として使う
// - 削除は全てXCUIApplication経由のUI操作で行い、sqlite3や本番DBへの直接アクセスは行わない
// - メイン帳簿・既存の実データ（QART_ / QARegression_ 接頭辞を持たないデータ）は削除対象にしない

import XCTest

enum QARegressionCategoryType: String {
    case expense = "支出"
    case income = "収入"
}

class QARegressionUITestCase: XCTestCase {

    private(set) var app: XCUIApplication!

    private var createdBookNames: [String] = []
    private var createdCategoryNames: [(name: String, type: QARegressionCategoryType)] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let application = XCUIApplication()
        application.launch()
        app = application

        // テスト開始前: 前回までのテスト失敗・中断で残った QART_ / QARegression_ データを一掃する。
        // ここが失敗してもテスト自体は続行させる（後始末の事前掃除でテスト本体を巻き込まない）。
        QARegressionUICleanup.sweepLeftoverTestData(app: application)

        // addTeardownBlock は tearDown() より後、登録の逆順で必ず実行される。
        // テストが失敗・continueAfterFailureで中断しても実行されるため、
        // 「作成したデータを確実に消す」責務はここに集約する。
        addTeardownBlock { [weak self] in
            self?.performCleanup(app: application)
        }
    }

    // MARK: - データ作成の記録
    //
    // データを作成した直後（後続のアサーションが失敗する前）に呼ぶこと。
    // これにより、アサーション失敗でテストが中断しても後始末対象として記録される。

    func trackCreatedBook(_ name: String) {
        createdBookNames.append(name)
    }

    func trackCreatedCategory(_ name: String, type: QARegressionCategoryType) {
        createdCategoryNames.append((name, type))
    }

    // MARK: - 後始末

    private func performCleanup(app: XCUIApplication) {
        var failures: [String] = []

        // カテゴリー→帳簿の順で削除する（帳簿を先に消すと、帳簿に紐づくカテゴリーの
        // 編集画面遷移ができなくなる可能性があるため、作成と逆順に削除する）
        for (name, type) in createdCategoryNames.reversed() {
            guard QARegressionUICleanup.isTestData(name) else { continue }
            if !QARegressionUICleanup.deleteCategory(named: name, type: type, app: app) {
                failures.append("カテゴリー「\(name)」")
            }
        }

        for name in createdBookNames.reversed() {
            guard QARegressionUICleanup.isTestData(name), name != "メイン帳簿" else { continue }
            if !QARegressionUICleanup.deleteBook(named: name, app: app) {
                failures.append("帳簿「\(name)」")
            }
        }

        if !failures.isEmpty {
            XCTFail(
                "QARegressionUITestsの後始末に失敗しました。実データストアに残存している可能性があるため手動確認が必要です: "
                + failures.joined(separator: ", ")
            )
        }
    }
}
