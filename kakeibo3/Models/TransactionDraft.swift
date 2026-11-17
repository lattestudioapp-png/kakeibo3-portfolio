import Foundation

// MARK: - 収支保存用下書きデータ

/**
 入力フォームや編集フォームから、保存処理へ渡すためのデータ。
 SwiftDataモデルを直接ViewModel内で組み立てすぎないために使う。
 */
struct TransactionDraft {
    let type: String
    let amount: Int
    let date: Date
    let method: String
    let category: String
    let memo: String
    let bankAccountId: UUID?
    let receiptImagePaths: [String]
    /// 紐づく BookData の UUID。新規保存時は選択中の帳簿、編集時は元の取引の帳簿を引き継ぐ
    /// （編集で帳簿間を移動することはない）。
    let bookId: UUID
}
