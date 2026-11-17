import Foundation
import Combine

struct IncomeInputSetting: TransactionInputSetting {
    let typeName = "収入"
    let methodTitle = "受け取り"
    let defaultCategory = "給料"
    let defaultMethod = "現金"

    // SwiftData が空の時だけ使うフォールバック（通常は ReceiveMethodData を参照）
    let methods = ["現金"]

    // 初回インストール時に作成する最小カテゴリー
    let categories = ["給料"]
}
