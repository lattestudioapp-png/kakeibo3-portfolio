import Foundation

// MARK: - 同名項目の重複チェック
//
// 複数帳簿対応後、現金・クレジットカード・電子マネー・銀行口座・デビットカード・証券口座・
// 暗号資産・その他・受け取り方法の各Edit Viewで「同じ帳簿内・同じ種類・同じ名前」の
// 項目を重複作成できてしまう問題への対応。
//
// 判定は必ず bookId + 種類 + 名前（前後空白trim）で行い、名前だけでの検索はしない。
// 削除済み（isActive=false）の項目は重複判定の対象外にする
// （削除後に同じ名前で作り直せるようにするため）。

enum DuplicateNameChecker {

    static let errorMessage = "同じ名前の項目がすでに存在します。"

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /**
     PaymentMethodSettingData（現金/クレカ/電子マネー/デビットカード/証券口座/暗号資産/その他/受け取り方法）
     の同名重複を判定する。
     */
    static func isDuplicatePaymentMethodName(
        _ name: String,
        type: String,
        bookId: UUID?,
        excluding excludingId: UUID? = nil
    ) -> Bool {
        let trimmed = normalize(name)
        guard !trimmed.isEmpty else { return false }

        let all = PaymentMethodSettingDataSync.fetchAll()
        return all.contains {
            $0.id != excludingId &&
            $0.bookId == bookId &&
            $0.type == type &&
            $0.isActive &&
            normalize($0.methodName) == trimmed
        }
    }

    /**
     BankAccountData の同名重複を判定する。
     */
    static func isDuplicateBankAccountName(
        _ name: String,
        bookId: UUID?,
        excluding excludingId: UUID? = nil
    ) -> Bool {
        let trimmed = normalize(name)
        guard !trimmed.isEmpty else { return false }

        let all = BankAccountDataSync.fetchAll()
        return all.contains {
            $0.id != excludingId &&
            $0.bookId == bookId &&
            $0.isActive &&
            normalize($0.accountName) == trimmed
        }
    }

    // MARK: - 帳簿名の重複チェック

    static let duplicateBookNameErrorMessage = "同じ名前の帳簿が既に存在します"

    /**
     帳簿名の比較用正規化。前後の空白除去に加え、全角スペースを半角スペースに統一し、
     大文字小文字を無視することで「Main」「main」「Main　」のような表記ゆれも同名として扱う。
     */
    static func normalizeBookName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(of: "\u{3000}", with: " ").lowercased()
    }

    /**
     BookData の同名重複を判定する。帳簿は帳簿ごとの入れ子構造を持たないため、
     bookIdスコープではなく全帳簿の中で重複を判定する。
     */
    static func isDuplicateBookName(
        _ name: String,
        excluding excludingId: UUID? = nil,
        in books: [BookData]
    ) -> Bool {
        let normalized = normalizeBookName(name)
        guard !normalized.isEmpty else { return false }
        return books.contains {
            $0.id != excludingId && normalizeBookName($0.name) == normalized
        }
    }
}
