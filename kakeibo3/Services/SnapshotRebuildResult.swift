import Foundation

// MARK: - 全帳簿版rebuildAll()の結果
//
// 帳簿ごとに独立して成功・失敗する(1帳簿分の1トランザクションのため、他帳簿の結果には
// 一切影響しない)。呼び出し元が成功/失敗を帳簿単位で把握できるようにする。

struct SnapshotRebuildResult {
    struct FailedBook {
        let bookId: UUID
        let error: Error
    }

    private(set) var succeededBookIds: [UUID] = []
    private(set) var failedBooks: [FailedBook] = []

    var hasFailures: Bool { !failedBooks.isEmpty }

    mutating func recordSuccess(bookId: UUID) {
        succeededBookIds.append(bookId)
    }

    mutating func recordFailure(bookId: UUID, error: Error) {
        failedBooks.append(FailedBook(bookId: bookId, error: error))
    }
}
