import Foundation

// MARK: - 帳簿共有の状態（設定 > 一般 > 帳簿の共有）
//
// CKShare本体はまだ実装しておらず（Phase 6で着手）、ここは表示・状態管理の枠組みのみ。
// BookSharingServiceが将来CloudKitの実データからこれらの値を組み立てる想定で、
// View/ViewModelはCloudKitの型（CKShareやCKShare.Participant）を直接知らずに済むようにする。

/// 1つの帳簿（BookData）に対する共有状態
enum ShareStatus: Equatable {
    case notShared
    case shared(ShareDetail)
}

/// 共有中の帳簿の詳細
struct ShareDetail: Equatable {
    var isOwner: Bool
    var ownerName: String?
    var participants: [ShareParticipantInfo]
    // 参加者情報の取得に失敗した場合（クラッシュさせず「参加者情報を取得できません」を出すため）
    var participantsUnavailable: Bool = false
}

/// 共有参加者1人分の情報
struct ShareParticipantInfo: Identifiable, Equatable {
    enum Role: Equatable {
        case owner
        case participant
    }

    enum AcceptanceState: Equatable {
        case invited
        case accepted
        case declined
        case unknown

        var displayLabel: String {
            switch self {
            case .invited: return "招待済み"
            case .accepted: return "参加済み"
            case .declined: return "招待を辞退"
            case .unknown: return "状態不明"
            }
        }
    }

    let id: UUID
    let name: String
    // メールアドレスなど、共有先を識別する情報（取得できない場合はnil）
    let contact: String?
    let role: Role
    let acceptanceState: AcceptanceState

    var roleOrStatusLabel: String {
        role == .owner ? "所有者" : acceptanceState.displayLabel
    }
}

// MARK: - ユーザー向けエラー
//
// 技術的なエラー全文は画面に出さず、ここで日本語の定型メッセージへ変換する。
enum BookSharingError: LocalizedError, Equatable {
    case notSignedInToiCloud
    case iCloudDriveUnavailable
    case networkUnavailable
    case createShareFailed
    case presentInvitationFailed
    case fetchShareInfoFailed
    case stopSharingFailed
    case joinShareFailed
    case permissionDenied
    case shareAlreadyStopped
    // CloudKit本体（Phase 6）が未実装のため、現段階では実行できないアクションに使う
    case notImplementedYet

    var errorDescription: String? {
        switch self {
        case .notSignedInToiCloud: return "iCloudにサインインしていません。設定アプリからサインインしてください。"
        case .iCloudDriveUnavailable: return "iCloud Driveが使用できません。設定を確認してください。"
        case .networkUnavailable: return "通信できません。ネットワーク接続を確認してください。"
        case .createShareFailed: return "共有の作成に失敗しました。"
        case .presentInvitationFailed: return "招待画面の表示に失敗しました。"
        case .fetchShareInfoFailed: return "共有情報の取得に失敗しました。"
        case .stopSharingFailed: return "共有の停止に失敗しました。"
        case .joinShareFailed: return "共有への参加に失敗しました。"
        case .permissionDenied: return "この操作を行う権限がありません。"
        case .shareAlreadyStopped: return "この共有はすでに終了しています。"
        case .notImplementedYet: return "この機能は準備中です。CloudKitの設定が完了次第利用できます。"
        }
    }
}
