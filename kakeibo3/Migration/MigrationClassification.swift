import Foundation

// MARK: - 17 SwiftDataモデル → 13 Core Data Entity の分類
//
// 移行漏れをモデル数の違いで隠さないため、旧SwiftDataの全17モデルそれぞれについて
// 「直接移行」か「再生成する派生データ」のいずれかに機械的に分類できることをコードで
// 保証する(このEnumがLegacySnapshotの各配列と1:1対応している)。
// 「別Entityへ統合」「UserDefaultsへ移行」「廃止データ」「移行不要」に該当するモデルはない
// (調査報告の通り、全モデルが以下いずれかに明確に分類される)。

enum LegacyModelClassification: String, CaseIterable {
    // MARK: - 直接移行(13モデル。Core Data本番ストアへ1:1で書き込む)
    case bookData
    case categoryData
    case expenseData
    case incomeData
    case transferData
    case bankAccountData
    case receiveMethodData
    case paymentMethodSettingData
    case budgetData
    case recurringBudgetData
    case fixedExpenseData
    case recurringIncomeData
    case recurringTransferSettingData

    // MARK: - 再生成する派生データ(4モデル。移行せず、既存の自己修復機構で作り直す)
    case dailySnapshot
    case monthlySnapshot
    case analysisMonthlySnapshot
    case assetGraphCacheData

    enum Disposition {
        /// Core Data本番ストアへ1:1で移行する
        case migrateDirectly
        /// 移行せず、既存の再生成機構に任せる(理由を添える)
        case regenerate(reason: String)
    }

    var disposition: Disposition {
        switch self {
        case .bookData, .categoryData, .expenseData, .incomeData, .transferData,
             .bankAccountData, .receiveMethodData, .paymentMethodSettingData,
             .budgetData, .recurringBudgetData, .fixedExpenseData,
             .recurringIncomeData, .recurringTransferSettingData:
            return .migrateDirectly

        case .dailySnapshot, .monthlySnapshot, .analysisMonthlySnapshot:
            return .regenerate(reason: "SnapshotManager.backfillIfNeeded() / AnalysisSnapshotManager.backfillIfNeeded() が起動時に自動再構築する(該当Entityの件数が0件であることをゲートにしている)")

        case .assetGraphCacheData:
            return .regenerate(reason: "自動バックフィル機構がなく、分析>資産の「更新」ボタン押下でのみ再生成される既存仕様。移行直後に空のままで良い")
        }
    }

    var isMigratedDirectly: Bool {
        if case .migrateDirectly = disposition { return true }
        return false
    }

    static var directlyMigratedCases: [LegacyModelClassification] {
        allCases.filter { $0.isMigratedDirectly }
    }

    static var regeneratedCases: [LegacyModelClassification] {
        allCases.filter { !$0.isMigratedDirectly }
    }
}
