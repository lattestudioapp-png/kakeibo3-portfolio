import Foundation

enum TransferAccountType: String {
    case bank          = "bank"
    case receive       = "receive"
    case paymentMethod = "payment"
}

struct TransferParticipant: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: String  // TransferAccountType.rawValue
    var isLocked: Bool = false
    var colorHex: String? = nil
}

// MARK: - 振替データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDTransferData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`TransferDataSync`が変換を担当する）。
struct TransferData: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var fromType: String
    var fromId: UUID?
    var fromName: String
    var toType: String
    var toId: UUID?
    var toName: String
    var amount: Int
    var feeAmount: Int = 0
    var memo: String
    var receiptImagePath: String? = nil
    var createdAt: Date
    var updatedAt: Date
    var isTestData: Bool = false
    // 定期振替から自動生成された場合の定期振替設定ID（nil = 手動入力）
    var recurringTransferSettingId: UUID? = nil
    // 紐づく BookData の UUID（振替は帳簿をまたがない。nil = マイグレーション未実施）
    var bookId: UUID? = nil
    // ゴミ箱（ソフトデリート）。trueの間は通常画面・集計から除外され、30日後に完全削除される
    var isInTrash: Bool = false
    var trashedAt: Date? = nil

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        fromType: String,
        fromId: UUID? = nil,
        fromName: String,
        toType: String,
        toId: UUID? = nil,
        toName: String,
        amount: Int,
        feeAmount: Int = 0,
        memo: String = "",
        receiptImagePath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id        = id
        self.date      = date
        self.fromType  = fromType
        self.fromId    = fromId
        self.fromName  = fromName
        self.toType    = toType
        self.toId      = toId
        self.toName    = toName
        self.amount    = amount
        self.feeAmount = feeAmount
        self.memo      = memo
        self.receiptImagePath = receiptImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
