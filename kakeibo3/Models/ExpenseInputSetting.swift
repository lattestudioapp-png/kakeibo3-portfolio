import Foundation
import Combine

struct ExpenseInputSetting: TransactionInputSetting {
    let typeName = "支出"
    let methodTitle = "支払い"
    let defaultCategory = "食費"
    let defaultMethod = "現金"

    // SwiftData が空の時だけ使うフォールバック（通常は PaymentMethodSettingData を参照）
    let methods = ["現金"]

    // 初回インストール時に作成する最小カテゴリー
    let categories = ["食費"]
}
