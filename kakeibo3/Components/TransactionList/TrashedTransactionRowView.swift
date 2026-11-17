import SwiftUI

// MARK: - ゴミ箱画面の1行

struct TrashedTransactionRowView: View {
    let item: TransactionListItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var showsActionDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("元の日付: \(formatted(item.date))")
                Spacer()
                Text("削除日: \(item.trashedAt.map(formatted) ?? "-")")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.black.opacity(0.45))
            .padding(.horizontal, 20)

            TransactionRowComponent(item: item)
                .contentShape(Rectangle())
                .onTapGesture { showsActionDialog = true }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive, action: onDelete) {
                        Label("削除", systemImage: "trash")
                    }
                    Button(action: onRestore) {
                        Label("復元", systemImage: "arrow.uturn.backward")
                    }
                    .tint(AppColors.main)
                }
        }
        .padding(.vertical, 6)
        .confirmationDialog("この取引をどうしますか？", isPresented: $showsActionDialog, titleVisibility: .visible) {
            Button("復元", action: onRestore)
            Button("削除", role: .destructive, action: onDelete)
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
