import Foundation

// MARK: - 移行の進行状態
//
// Kakeibo3App側での画面切り替え(移行中/失敗/通常)に使う想定の状態。
// このEnum自体はCore Data/SwiftDataのどちらにも依存しない。
// Kakeibo3Appへの実際の組み込みは後続コミットで行う(この時点ではまだ未接続)。

enum MigrationState: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}
