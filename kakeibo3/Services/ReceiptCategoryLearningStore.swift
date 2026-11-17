import Foundation

// MARK: - 商品名→カテゴリーのローカル学習辞書
//
// ユーザーがレシート編集画面でカテゴリーを確定するたびに記録し、次回以降の同じ商品名に優先提案する。
// UserDefaultsにJSONで保存するのみで、クラウド同期は行わない
// （BackupManagerのバックアップ対象にも含めない＝端末ローカル限定）。

enum ReceiptCategoryLearningStore {
    private static let storageKey = "receiptCategoryLearningMap.v1"

    static func suggestedCategory(forProductName rawName: String) -> String? {
        load()[normalize(rawName)]
    }

    static func recordCorrection(productName rawName: String, category: String) {
        guard category != ReceiptCategorySuggestionService.unsetCategory else { return }
        var map = load()
        map[normalize(rawName)] = category
        persist(map)
    }

    private static func normalize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmed).lowercased()
    }

    private static func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private static func persist(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
