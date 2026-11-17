import Foundation

// MARK: - カテゴリー自動分類（① 学習履歴 → ③ 商品名キーワード → ④ 店舗名キーワード → ⑤ 未設定）
//
// ①過去に登録したカテゴリーと②ユーザーが修正した履歴は、同じ「学習辞書」に一本化して扱う
// （修正するたびに学習辞書へ記録するため、実質的に同じ仕組み）。
// ここで返すのはあくまで「候補」であり、呼び出し側は必ずユーザーが確認・変更できる形で提示すること。

enum ReceiptCategorySuggestionService {
    static let unsetCategory = "未設定"

    static func suggestCategory(
        productName: String,
        storeName: String?,
        availableCategories: [String]
    ) -> String {
        if let learned = ReceiptCategoryLearningStore.suggestedCategory(forProductName: productName),
           availableCategories.contains(learned) {
            return learned
        }
        if let byProduct = matchKeyword(productName, table: ReceiptCategoryKeywordRules.productKeywords),
           availableCategories.contains(byProduct) {
            return byProduct
        }
        if let storeName,
           let byStore = matchKeyword(storeName, table: ReceiptCategoryKeywordRules.storeKeywords),
           availableCategories.contains(byStore) {
            return byStore
        }
        return unsetCategory
    }

    private static func matchKeyword(
        _ text: String,
        table: [(keywords: [String], category: String)]
    ) -> String? {
        for entry in table where entry.keywords.contains(where: { text.contains($0) }) {
            return entry.category
        }
        return nil
    }
}
