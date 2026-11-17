import Foundation
import Combine

// MARK: - 設定 > 一般 > 帳簿の共有 ViewModel
//
// 「共有対象の帳簿」はアプリ全体で選択中の帳簿（BookSettings.storageKey）とは別に管理する。
// 画面を開くたびにアプリの選択中帳簿へ合わせてしまうと、既に共有中の帳簿から別の帳簿へ
// 勝手に共有対象が切り替わってしまうため、明示的に選んだ帳簿をBookSettings.sharingTargetStorageKeyへ
// 保持し、次回以降はそちらを優先する。
@MainActor
final class BookSharingViewModel: ObservableObject {

    @Published private(set) var targetBookId: UUID?
    @Published private(set) var shareStatus: ShareStatus = .notShared
    @Published private(set) var isLoadingStatus = false
    @Published private(set) var isProcessingAction = false
    @Published var errorMessage: String?

    private let service: BookSharingServicing
    private let defaults: UserDefaults

    init(service: BookSharingServicing = BookSharingService.shared, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    var isShared: Bool {
        if case .shared = shareStatus { return true }
        return false
    }

    // MARK: - 対象帳簿の解決

    /// 画面表示のたびに呼ぶ。保存済みの共有対象帳簿があればそれを優先し、
    /// なければアプリの選択中帳簿を初期値として使う。
    func resolveInitialTarget(availableBooks: [BookData], selectedBookIdString: String) {
        let visible = availableBooks.filter { !$0.isArchived }
        if let savedIdString = defaults.string(forKey: BookSettings.sharingTargetStorageKey),
           let savedId = UUID(uuidString: savedIdString),
           visible.contains(where: { $0.id == savedId }) {
            targetBookId = savedId
            return
        }
        targetBookId = BookResolver.resolveCurrentBook(from: availableBooks, selectedIdString: selectedBookIdString)?.id
    }

    /// ユーザーが画面上で明示的に共有対象の帳簿を選び直した時に呼ぶ。
    func selectTargetBook(_ bookId: UUID) {
        targetBookId = bookId
        defaults.set(bookId.uuidString, forKey: BookSettings.sharingTargetStorageKey)
    }

    // MARK: - 状態取得

    func loadShareStatus() async {
        guard let targetBookId else { return }
        isLoadingStatus = true
        shareStatus = await service.fetchShareStatus(for: targetBookId)
        isLoadingStatus = false
    }

    // MARK: - アクション（CKShare本体はPhase 6で実装。現段階では「準備中」を返す）

    func startSharing() async {
        await runAction { try await self.service.startSharing(for: $0) }
    }

    func manageSharing() async {
        await runAction { try await self.service.presentManageSharing(for: $0) }
    }

    func stopSharing() async {
        await runAction { try await self.service.stopSharing(for: $0) }
    }

    func leaveSharing() async {
        await runAction { try await self.service.leaveSharing(for: $0) }
    }

    private func runAction(_ operation: @escaping (UUID) async throws -> Void) async {
        guard let targetBookId, !isProcessingAction else { return }
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            try await operation(targetBookId)
            await loadShareStatus()
        } catch {
            errorMessage = (error as? BookSharingError)?.errorDescription ?? BookSharingError.fetchShareInfoFailed.errorDescription
        }
    }
}
