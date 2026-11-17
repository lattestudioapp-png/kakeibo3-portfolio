import Foundation

// MARK: - 定期振替設定データ（Core Data移行 Phase 1）
//
// 永続化はCore Data（`CDRecurringTransferSettingData`）が担い、このstructは画面・ロジック層が
// 触るフレームワーク非依存のドメイン表現（`RecurringTransferSettingDataSync`が変換を担当する）。
struct RecurringTransferSettingData: Identifiable, Hashable {
    var id: UUID
    var fromMethodId: UUID
    var fromMethodName: String
    // "bank" or "payment" (TransferAccountType.rawValue)。既存レコードは "payment" がデフォルト
    var fromType: String = TransferAccountType.paymentMethod.rawValue
    var toMethodId: UUID
    var toMethodName: String
    var toType: String = TransferAccountType.paymentMethod.rawValue
    var amount: Int
    var day: Int          // 1〜30 が毎月X日、31 が月末
    var startDate: Date = Date()
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    // 無料版の上限超過によりロックされているか（データは保持したまま利用制限する）
    var isLocked: Bool = false
    var isTestData: Bool = false
    // 紐づく BookData の UUID（振替は帳簿をまたがない。nil = マイグレーション未実施）
    var bookId: UUID? = nil
    // 振替日が金融機関の休業日と重なった場合の調整方法（WeekendHolidayAdjustment.rawValue）。
    // 移動元・移動先のいずれかが銀行口座の場合のみ編集画面に表示・適用する。
    var holidayAdjustment: String = WeekendHolidayAdjustment.shiftLater.rawValue
    // 生成済みスケジュール月（"yyyy-M"）。休日調整で実際の反映日が前後の月にずれても、
    // TransferData.dateから逆算せずここで「本来の予定月」を追跡することで、
    // RecurringEntryGeneratorが同じ月を二重生成しないようにする。
    var generatedScheduleMonths: [String] = []

    init(
        id: UUID = UUID(),
        fromMethodId: UUID,
        fromMethodName: String,
        fromType: String = TransferAccountType.paymentMethod.rawValue,
        toMethodId: UUID,
        toMethodName: String,
        toType: String = TransferAccountType.paymentMethod.rawValue,
        amount: Int,
        day: Int,
        startDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id              = id
        self.fromMethodId   = fromMethodId
        self.fromMethodName = fromMethodName
        self.fromType       = fromType
        self.toMethodId     = toMethodId
        self.toMethodName   = toMethodName
        self.toType         = toType
        self.amount         = amount
        self.day            = day
        self.startDate      = startDate
        self.createdAt      = createdAt
        self.updatedAt      = updatedAt
    }
}
