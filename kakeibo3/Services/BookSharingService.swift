import Foundation

// MARK: - 帳簿共有サービス（設定 > 一般 > 帳簿の共有）
//
// CKShareの作成・招待・管理・停止・参加はまだ実装しない（CLAUDE.mdの段階リストのPhase 6以降）。
// このファイルはBookSharingViewModelがCloudKitの型を直接知らずに済むようにする窓口で、
// 現段階では「帳簿ごとに何も共有されていない」という正しい状態を返すだけのスタブ実装。
// NSPersistentCloudKitContainer化・CKShare実装時は、このファイルの中身だけを
// 実際のCloudKit呼び出しに差し替える想定（呼び出し側のAPIは変えない）。
protocol BookSharingServicing {
    func fetchShareStatus(for bookId: UUID) async -> ShareStatus
    func startSharing(for bookId: UUID) async throws
    func presentManageSharing(for bookId: UUID) async throws
    func stopSharing(for bookId: UUID) async throws
    func leaveSharing(for bookId: UUID) async throws
}

final class BookSharingService: BookSharingServicing {
    static let shared = BookSharingService()

    private init() {}

    /// 帳簿の共有状態を取得する。CloudKit未実装のため、現時点では常に「未共有」を返す
    /// （嘘の共有中状態を出さないための、正しい形のスタブ）。
    func fetchShareStatus(for bookId: UUID) async -> ShareStatus {
        .notShared
    }

    func startSharing(for bookId: UUID) async throws {
        throw BookSharingError.notImplementedYet
    }

    func presentManageSharing(for bookId: UUID) async throws {
        throw BookSharingError.notImplementedYet
    }

    func stopSharing(for bookId: UUID) async throws {
        throw BookSharingError.notImplementedYet
    }

    func leaveSharing(for bookId: UUID) async throws {
        throw BookSharingError.notImplementedYet
    }
}
