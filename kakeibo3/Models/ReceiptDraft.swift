import UIKit

// MARK: - レシートOCR結果の画面内一時データ（@Modelではなく、確認・編集画面でのみ保持するメモリ上構造体）

struct ReceiptDraft {
    var capturedImage: UIImage
    var date: Date?
    var storeName: String?
    var paymentMethod: String?
    var receiptTotal: Int?
    var taxAmount: Int?
    var isTaxIncluded: Bool?
    var items: [ReceiptDraftItem]

    var itemsTotal: Int {
        items.reduce(0) { $0 + $1.amount }
    }

    var hasTotalMismatch: Bool {
        guard let receiptTotal else { return false }
        return receiptTotal != itemsTotal
    }

    var mismatchAmount: Int {
        (receiptTotal ?? 0) - itemsTotal
    }
}

struct ReceiptDraftItem: Identifiable {
    let id = UUID()
    var isIncluded: Bool = true
    var productName: String
    var amount: Int
    var category: String
    var suggestedCategory: String
}
