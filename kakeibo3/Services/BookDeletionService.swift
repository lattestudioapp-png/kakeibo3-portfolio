import Foundation

// MARK: - 帳簿そのものの削除
//
// 帳簿を「設定 > 一般 > 帳簿の切り替え」から削除する際に使う。メイン帳簿は削除不可。
// 対象帳簿のbookIdに紐づく家計簿データをすべて削除してから、BookData自体を削除する
// （他の帳簿のデータには一切触れない）。

enum BookDeletionService {

    static func deleteBook(_ book: BookData) {
        guard !book.isMain else { return }
        DataResetService.deleteAllData(bookId: book.id)
        BookDataSync.delete(id: book.id)
    }
}
