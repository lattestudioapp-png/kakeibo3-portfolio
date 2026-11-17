import Foundation

// MARK: - データリセット（その他 > データリセット）
//
// 現在選択中の帳簿ぶんの家計簿データ（取引・カテゴリー・支払い方法・口座・固定費・
// 定期収入/振替・各種snapshot）だけを削除し、その帳簿を初回作成時と同じ初期状態
// （現金の支払い方法・デフォルトカテゴリー）に戻す。他の帳簿のデータは一切変更しない。
// テーマ・パスコード・分析の並び順・グラフ設定などのアプリ設定（UserDefaults）は対象外
// （「データ」のリセットであって「設定」のリセットではないため）。

enum DataResetService {

    static func resetAll(bookId: UUID) {
        deleteAllData(bookId: bookId)

        // 初回インストール時と同じ初期データをこの帳簿ぶんだけ再投入する
        DataInitializerService.createDefaultPaymentMethodsIfNeeded(existing: [], bookId: bookId)
        DataInitializerService.createDefaultReceiveMethodsIfNeeded(existing: [], bookId: bookId)
        try? SwiftDataCategoryRepository().createDefaultCategoriesIfNeeded(existingCategories: [], bookId: bookId)

        // migrateReceiveMethodsIfNeeded はアプリ全体で一度きりのフラグでガードされているため、
        // 初回移行が済んだ後にリセットされた帳簿には効かず、上の2つがどちらも「現金」を
        // 作ることで支払い・受け取り・振替候補に現金が重複表示されてしまう。
        // フラグに関係なくこの帳簿ぶんだけ即座に再整合させる。
        DataInitializerService.reconcileReceiveMethodsForBook(bookId: bookId)
    }

    // 指定した帳簿ぶんの家計簿データをすべて削除する（初期データの再投入はしない）。
    // BookDeletionService（帳簿そのものの削除）とresetAll（データリセット）の両方から使う。
    static func deleteAllData(bookId: UUID) {
        ExpenseDataSync.deleteAll(bookId: bookId)
        IncomeDataSync.deleteAll(bookId: bookId)
        TransferDataSync.deleteAll(bookId: bookId)
        RecurringTransferSettingDataSync.deleteAll(bookId: bookId)
        FixedExpenseDataSync.deleteAll(bookId: bookId)
        RecurringIncomeDataSync.deleteAll(bookId: bookId)
        BudgetDataSync.deleteAll(bookId: bookId)
        RecurringBudgetDataSync.deleteAll(bookId: bookId)
        PaymentMethodSettingDataSync.deleteAll(bookId: bookId)
        BankAccountDataSync.deleteAll(bookId: bookId)
        ReceiveMethodDataSync.deleteAll(bookId: bookId)
        CategoryDataSync.deleteAll(bookId: bookId)
        DailySnapshotSync.deleteAll(bookId: bookId)
        MonthlySnapshotSync.deleteAll(bookId: bookId)
        AnalysisMonthlySnapshotSync.deleteAll(bookId: bookId)
        AssetGraphCacheDataSync.deleteAll(bookId: bookId)
    }
}
