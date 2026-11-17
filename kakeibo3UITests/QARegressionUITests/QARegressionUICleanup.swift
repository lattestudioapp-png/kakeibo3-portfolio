// MARK: - QARegressionTests
// このファイルは手動QA補助用の一時テストです。
// 不要になったら QARegressionUITests フォルダごと削除してください。
//
// QARegressionUITestCase から呼ばれる、テストデータ削除ヘルパー。
// 全てXCUIApplication経由のUI操作のみで完結させ、sqlite3や本番DBへの直接アクセスは行わない。
//
// 対応済み（実際に作成・削除フローを検証済み）:
//   - 帳簿（BookSwitchSettingView / BookEditView）
//   - カテゴリー（CategoryEditView / CategoryDetailEditView）
//
// 未対応（現状どのQARegressionUITestsも支払い方法・受け取り方法・銀行口座・カード・
// 予算・定期データ・取引を実際には作成していないため、UI削除フローを実装していない。
// 特に取引（支出/収入）は画面上に一意な識別用の名前が無く、後始末対象として
// 名前で特定する手段が無いため、後始末の実装には別途メモ欄への識別子付与など
// テスト側の作り込みが必要。今後これらのデータをテストが作成するようになった場合、
// 本ファイルに deletePaymentMethod / deleteBankAccount 等を同じパターンで追加すること）:
//   - 支払い方法（現金以外含む） / 受け取り方法 / 銀行口座 / カード / 予算 / 定期データ / 取引

import XCTest

enum QARegressionUICleanup {

    /// テストデータの識別に使う接頭辞。この接頭辞を持つデータだけを削除対象とする。
    static let testDataPrefixes = ["QART_", "QARegression_"]

    static func isTestData(_ name: String) -> Bool {
        testDataPrefixes.contains { name.hasPrefix($0) }
    }

    // MARK: - テスト開始前の一括掃除

    static func sweepLeftoverTestData(app: XCUIApplication) {
        sweepLeftoverBooks(app: app)
        sweepLeftoverCategories(app: app, type: .expense)
        sweepLeftoverCategories(app: app, type: .income)
    }

    // MARK: - 帳簿

    @discardableResult
    static func deleteBook(named name: String, app: XCUIApplication) -> Bool {
        guard name != "メイン帳簿" else { return true }
        guard openBookSwitcherInEditMode(app: app) else { return false }

        let bookRow = button(labeled: name, in: app)
        guard bookRow.waitForExistence(timeout: 5) else {
            // 対象が見つからない = 既に削除済みとみなす
            closeBookSwitcher(app: app)
            return true
        }

        let result = deleteBookRow(bookRow, app: app)
        closeBookSwitcher(app: app)
        return result
    }

    static func sweepLeftoverBooks(app: XCUIApplication) {
        guard openBookSwitcherInEditMode(app: app) else { return }

        var consecutiveMisses = 0
        for _ in 0..<20 {
            if let target = findLeftoverButton(app: app) {
                _ = deleteBookRow(target, app: app)
                consecutiveMisses = 0
            } else {
                consecutiveMisses += 1
                if consecutiveMisses > 2 { break }
                app.swipeUp()
            }
        }

        closeBookSwitcher(app: app)
    }

    private static func openBookSwitcherInEditMode(app: XCUIApplication) -> Bool {
        // 呼び出し元のテスト本体が「帳簿の切り替え」シートを開いたまま終了することがあり
        // （例: 長い帳簿名作成テストは作成後の一覧表示確認までしか行わずシートを閉じない）、
        // その後始末としてこの関数が呼ばれた時点で既にシートが開いている場合がある。
        // その状態で「設定」タブを再タップしても既存の.sheetは閉じないため、
        // 背後の「帳簿の切り替え」行は覆われたまま非hittableになる。
        // 既に開いているかどうかを先に確認し、開いていればナビゲーションをスキップする。
        if !app.navigationBars["帳簿の切り替え"].exists {
            let settingsTab = app.buttons["設定"].firstMatch
            guard settingsTab.waitForExistence(timeout: 5) else { return false }
            settingsTab.tap()

            let bookSwitchRow = app.buttons["帳簿の切り替え"].firstMatch
            scrollUntilHittable(bookSwitchRow, app: app)
            guard bookSwitchRow.waitForExistence(timeout: 5) else { return false }
            safeTap(bookSwitchRow)

            guard app.navigationBars["帳簿の切り替え"].waitForExistence(timeout: 5) else { return false }
        }

        let editToggle = app.buttons["編集"].firstMatch
        if editToggle.waitForExistence(timeout: 3) {
            editToggle.tap()
        }
        return true
    }

    private static func closeBookSwitcher(app: XCUIApplication) {
        // 編集モード中なら「完了」で抜けてから「閉じる」でシートを閉じる。
        // どちらもテキストラベル付きButtonのため、ラベル指定で確実に取得できる。
        let doneButton = app.buttons["完了"].firstMatch
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        }
        let closeButton = app.buttons["閉じる"].firstMatch
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        }
    }

    @discardableResult
    private static func deleteBookRow(_ bookRow: XCUIElement, app: XCUIApplication) -> Bool {
        guard bookRow.exists else { return false }
        safeTap(bookRow)

        guard app.navigationBars["帳簿を編集"].waitForExistence(timeout: 5) else { return false }

        // メイン帳簿には削除ボタン自体が表示されない（本番側のガード）。
        // 万一メイン帳簿がここに来ても、削除ボタンが無ければキャンセルして安全側に倒す。
        let deleteButton = app.buttons["削除する"].firstMatch
        guard deleteButton.waitForExistence(timeout: 3) else {
            app.buttons["キャンセル"].firstMatch.tap()
            return true
        }
        deleteButton.tap()

        let confirmButton = app.buttons["削除する"].firstMatch
        guard confirmButton.waitForExistence(timeout: 5) else { return false }
        confirmButton.tap()

        return app.navigationBars["帳簿の切り替え"].waitForExistence(timeout: 5)
    }

    // MARK: - カテゴリー

    @discardableResult
    static func deleteCategory(named name: String, type: QARegressionCategoryType, app: XCUIApplication) -> Bool {
        guard openCategoryEditView(app: app, type: type) else { return false }

        let categoryRow = button(labeled: name, in: app)
        guard categoryRow.waitForExistence(timeout: 5) else {
            // 対象が見つからない = 既に削除済みとみなす
            closeCategoryEditView(app: app)
            return true
        }

        let result = deleteCategoryRow(categoryRow, app: app)
        closeCategoryEditView(app: app)
        return result
    }

    static func sweepLeftoverCategories(app: XCUIApplication, type: QARegressionCategoryType) {
        guard openCategoryEditView(app: app, type: type) else { return }

        var consecutiveMisses = 0
        for _ in 0..<20 {
            if let target = findLeftoverButton(app: app) {
                _ = deleteCategoryRow(target, app: app)
                consecutiveMisses = 0
            } else {
                consecutiveMisses += 1
                if consecutiveMisses > 2 { break }
                app.swipeUp()
            }
        }

        closeCategoryEditView(app: app)
    }

    private static func openCategoryEditView(app: XCUIApplication, type: QARegressionCategoryType) -> Bool {
        let settingsTab = app.buttons["設定"].firstMatch
        guard settingsTab.waitForExistence(timeout: 5) else { return false }
        settingsTab.tap()

        let categoryRow = app.buttons["カテゴリー"].firstMatch
        scrollUntilHittable(categoryRow, app: app)
        guard categoryRow.waitForExistence(timeout: 5) else { return false }
        safeTap(categoryRow)

        // 支出/収入タブもAppSegmentControl(Button)のため、buttonsで指定する
        let typeTab = app.buttons[type.rawValue].firstMatch
        if typeTab.waitForExistence(timeout: 3) {
            typeTab.tap()
        }
        return true
    }

    private static func closeCategoryEditView(app: XCUIApplication) {
        // CategoryEditViewは.fullScreenCoverで表示されており、iOSの仕様上スワイプでは
        // 閉じられない（以前はswipeDown()に頼っていたが実際には何も起きておらず、
        // 後続の「設定」ボタンのwaitForExistenceはタブバー自体が背後に常に存在するため
        // シートが閉じたかどうかに関わらずtrueを返す偽陽性チェックだった）。
        // ヘッダーの閉じるボタン(headerCloseButton)を直接タップして確実に閉じる。
        let closeButton = app.buttons["headerCloseButton"].firstMatch
        if closeButton.waitForExistence(timeout: 5) {
            closeButton.tap()
        }
        let addCategoryLabel = app.buttons["カテゴリー追加"]
        _ = QARegressionUICleanup.waitForAbsence(of: addCategoryLabel, timeout: 5)
    }

    /// 要素が画面から消えるまで待つ（sheet/fullScreenCoverが閉じたことの確認用）。
    private static func waitForAbsence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @discardableResult
    private static func deleteCategoryRow(_ categoryRow: XCUIElement, app: XCUIApplication) -> Bool {
        guard categoryRow.exists else { return false }
        safeTap(categoryRow)

        let deleteButton = app.buttons["このカテゴリーを削除"].firstMatch
        guard deleteButton.waitForExistence(timeout: 5) else {
            // 初期残高等の保護カテゴリー、または想定外の画面遷移。安全側に倒して失敗扱いにする。
            return false
        }
        deleteButton.tap()
        return true
    }

    // MARK: - 共通

    /// 要素がhittableになるまでスワイプでスクロールする。
    /// スワイプ直後は慣性・バウンスでまだ座標が安定していないことがあり、
    /// isHittableが一瞬trueを返した直後にtap()すると"not hittable"で失敗することがあるため、
    /// ループ終了後にNSPredicateベースの待機を挟んでスクロールの静定を待ってから返す。
    static func scrollUntilHittable(_ element: XCUIElement, app: XCUIApplication, maxAttempts: Int = 8) {
        var attempts = 0
        while !element.isHittable && attempts < maxAttempts {
            app.swipeUp()
            attempts += 1
        }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        _ = XCTWaiter().wait(for: [hittable], timeout: 3)
    }

    /// isHittableチェックとtap()の間に一瞬だけ座標が不安定になり、"not hittable"で
    /// 失敗することがある（スクロールの慣性/バウンス由来）。isHittableがfalseの場合は
    /// 通常のtap()（XCTestが直前に再度hittability検証する）ではなく、要素の中心座標へ
    /// 直接タップすることでその再検証をバイパスする。
    static func safeTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// ラベル文字列でボタンを取得する。`app.buttons[name]`の文字列識別子クエリは
    /// 128文字を超えるとXCTestが例外を投げるため（テストが作成する超長い帳簿名/
    /// カテゴリー名の後始末で実際に踏んだ）、NSPredicateでlabel完全一致を指定して
    /// 文字数制限を回避する。
    private static func button(labeled name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private static func findLeftoverButton(app: XCUIApplication) -> XCUIElement? {
        let all = app.buttons.allElementsBoundByIndex
        for element in all where element.exists {
            // 編集モードの行には、内容と同じ接頭辞を持つ並べ替えハンドルが別ボタンとして
            // 存在する（システムが自動生成するアクセシビリティラベルで「{行の内容}を並べ替え」
            // という形式になる）。これは行そのものではないため、タップ対象から除外する。
            guard !element.label.hasSuffix("を並べ替え") else { continue }
            if isTestData(element.label) {
                return element
            }
        }
        return nil
    }
}
