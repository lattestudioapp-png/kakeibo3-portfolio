import SwiftUI

// MARK: - 「はじめに」確認画面(C1:複数端末の同時初回起動対策)
//
// CoreDataStartupCoordinator.state == .awaitingFreshInstallConfirmationの間だけ表示される。
// この状態は「ローカルにBookが1件も無く、このデバイスでもまだメイン帳簿を一度も確立していない」
// ＝本当に新規インストールの可能性が高い場合にのみ発生し、既存データのある端末やアップデートでは
// 一切表示されない。
//
// 「開始する」が押されるまでBookMigrationService.migrateIfNeeded()は呼ばれず、新しいメイン帳簿も
// 作られない。これにより、複数端末をほぼ同時に初めて起動した場合でも、競合の引き金が
// 「自動処理同士が数秒単位で競合する」ことから「人間が複数端末をほぼ同時に物理操作する」ことに
// 変わり、重複作成の確率を大きく下げる(ただし完全な保証ではない。詳細は設計resolve済み)。

struct FreshInstallConfirmationView: View {
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("はじめに")
                .font(.title3)
                .fontWeight(.semibold)

            Text("この端末でメイン帳簿を新しく作成します。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("複数の端末を同時にお使いの場合は、1台目の設定が終わってから2台目を開いてください。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onConfirm) {
                Text("開始する")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
