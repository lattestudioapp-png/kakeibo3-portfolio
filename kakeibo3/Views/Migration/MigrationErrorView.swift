import SwiftUI

// MARK: - 移行失敗画面
//
// 「初期化して続行」のような既存データを破壊する選択肢は用意しない。
// 再試行だけを提供し、既存データ(旧SwiftDataストア・本番Core Dataストアどちらも)は
// 変更していないことを明示する。

struct MigrationErrorView: View {
    let detail: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("データ移行に失敗しました")
                .font(.title3)
                .fontWeight(.semibold)

            Text("既存のデータは削除・変更されていません。もう一度お試しください。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onRetry) {
                Text("再試行")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            #if DEBUG
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 12)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
