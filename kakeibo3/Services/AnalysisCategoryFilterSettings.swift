import Foundation

// MARK: - 分析タブ「集計対象」フィルターの永続化
//
// 分析の支出/収入タブで「集計対象」ボタンから選んだカテゴリー名の集合を、
// 帳簿ごと・支出/収入ごとに分けてUserDefaultsへ保存する。
// nil（未保存 or 空集合）＝絞り込みなし＝すべて対象、として扱う。
// カテゴリー名はnull文字(\u{0})区切りで1つの文字列に連結して保存する
// （カテゴリー名自体にカンマが含まれても壊れないようにするため）。

enum AnalysisCategoryFilterSettings {

    private static let separator = "\u{0}"

    private static func key(bookId: UUID, categoryType: String) -> String {
        "analysisCategoryFilter_\(bookId.uuidString)_\(categoryType)"
    }

    static func load(bookId: UUID, categoryType: String) -> Set<String>? {
        guard let raw = UserDefaults.standard.string(forKey: key(bookId: bookId, categoryType: categoryType)),
              !raw.isEmpty else { return nil }
        let names = raw.split(separator: separator).map(String.init)
        return names.isEmpty ? nil : Set(names)
    }

    static func save(_ names: Set<String>?, bookId: UUID, categoryType: String) {
        let storageKey = key(bookId: bookId, categoryType: categoryType)
        if let names, !names.isEmpty {
            UserDefaults.standard.set(names.joined(separator: separator), forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
}
