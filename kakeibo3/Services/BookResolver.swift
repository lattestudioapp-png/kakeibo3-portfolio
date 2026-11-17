import Foundation

// MARK: - 現在の帳簿 / メイン帳簿の解決
//
// 「選択中の帳簿」はBookSettings.storageKeyにUUID文字列で保存されるが、
// 該当の帳簿が削除済みだったり初回起動直後で未設定だったりする場合に備え、
// フォールバック込みで解決するロジックをここに集約する。

enum BookResolver {
    // 保存済みのselectedBookIdで探し、見つからなければ（未設定・削除済み）
    // アーカイブされていない帳簿の先頭（sortOrder順）にフォールバックする。
    // それも無い（全帳簿がアーカイブ済みなど）場合は最後の手段としてメイン帳簿を返す
    // （currentBookIdが常にnon-nilで解決できるようにするため）。
    static func resolveCurrentBook(from books: [BookData], selectedIdString: String) -> BookData? {
        let visibleBooks = books.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        let resolved: BookData?
        if let uuid = UUID(uuidString: selectedIdString),
           let matched = visibleBooks.first(where: { $0.id == uuid }) {
            resolved = matched
        } else {
            resolved = visibleBooks.first ?? mainBook(from: books)
        }
        // 【調査用診断ログ】タブ切り替え等で呼ばれるたびに記録すると大量になるため、
        // 前回と結果が変わった時だけ記録する（調査内容6,10）。
        DiagnosticLog.logBookResolutionIfChanged(
            books: books, selectedIdString: selectedIdString, resolvedId: resolved?.id
        )
        return resolved
    }

    // 固定費/定期収入/定期振替からの自動生成は、選択中の帳簿に関わらず常にメイン帳簿へ記録する
    static func mainBook(from books: [BookData]) -> BookData? {
        books.first(where: \.isMain) ?? books.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    // 口座/支払い方法の初期残高収入など、選択中の帳簿と無関係にメイン帳簿へ記録したい箇所向けの簡易版。
    static func mainBookId() -> UUID? {
        mainBook(from: BookDataSync.fetchAll())?.id
    }
}
