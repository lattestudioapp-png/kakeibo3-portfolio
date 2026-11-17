import Foundation

// MARK: - 全帳簿の完全初期化(将来、重複した36帳簿を整理する際に使う想定の機能)
//
// 【重要】この関数自体はUIからは一切呼ばれていない。実行はこのenumを呼び出す
// 専用のUI操作(未実装)が明示的なユーザー確認を取った上で初めて行う想定で、
// 「安易な自動削除・自動再作成」を避けるため、起動シーケンスや通知等から
// 自動的に呼ばれることは無い(呼び出し元が無い＝現時点では一切実行されない)。
//
// 【establishedMainBookIdKeyとの関係・今回の変更で新たに必須になった手順】
// BookMigrationService.decideMainBookCreationは、一度でもメイン帳簿を確立済みの
// 端末では「existingBooksが0件」を二度と新規作成の根拠にしない(CloudKit内部resetへの
// 対策)。そのため、全帳簿を削除してもestablishedMainBookIdKeyをクリアし忘れると、
// 次回のBookMigrationService.migrateIfNeeded()が永久にwaitAndRetryし続け、
// 新しいメイン帳簿を二度と作れなくなる(詰み)。この関数はBookData等の削除と
// establishedMainBookIdKey/selectedBookIdのクリアを必ず同じ操作としてまとめて行うことで、
// この手順の抜け漏れを防ぐ。
//
// このservice自体は「全帳簿を消す」までしか行わない。削除後の新しいメイン帳簿1件の
// 再作成は、既存の安全なBookMigrationService.migrateIfNeeded()に委ねる
// (重複防止ロジックを重複実装しないため。呼び出し元は削除後、通常の起動シーケンスと
// 同じ経路でmigrateIfNeeded()を呼ぶこと)。
enum BookFactoryResetService {

    /// 全帳簿・全帳簿ぶんの家計簿データ(支出・収入・振替・カテゴリー・支払い方法・口座・
    /// 固定費・定期収入/振替・各種snapshot)を削除し、selectedBookId・establishedMainBookIdKeyを
    /// クリアする。
    ///
    /// 【呼び出し元の責務】この関数はdestructiveな操作であり、実行前に呼び出し元が
    /// 必ず明示的なユーザー確認を取ること。この関数自体はユーザー確認を行わない。
    static func eraseAllBooksAndResetAnchors() {
        for book in BookDataSync.fetchAll() {
            DataResetService.deleteAllData(bookId: book.id)
            BookDataSync.delete(id: book.id)
        }
        UserDefaults.standard.removeObject(forKey: BookSettings.storageKey)
        UserDefaults.standard.removeObject(forKey: BookMigrationService.establishedMainBookIdKey)
    }
}
