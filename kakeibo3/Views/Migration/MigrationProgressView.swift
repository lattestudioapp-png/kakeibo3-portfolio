import SwiftUI

// MARK: - 移行中画面(checking / migrating)
//
// 通常の家計簿画面は表示しない。バックグラウンド実行はせず、この画面を
// 表示している間はアプリ起動シーケンスが完了するまでユーザー操作を進めさせない。

struct MigrationProgressView: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.4)
            Text("データを準備しています…")
                .font(.headline)
            Text("しばらくそのままお待ちください")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
