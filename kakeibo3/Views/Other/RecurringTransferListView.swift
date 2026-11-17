import SwiftUI

struct RecurringTransferListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var recurringTransferDataObserver = RecurringTransferSettingDataSync.observer()
    private var recurringTransfers: [RecurringTransferSettingData] { recurringTransferDataObserver.items }

    @State private var isAdding = false
    @State private var editingItem: RecurringTransferSettingData? = nil

    private var activeTransfers: [RecurringTransferSettingData] {
        recurringTransfers.filter { $0.isActive && $0.bookId == currentBookId }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let items = activeTransfers

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        RecurringTransferRow(item: item, onTapRow: { editingItem = item })
                    }

                    if items.isEmpty {
                        Text("定期振替が登録されていません")
                            .font(AppFonts.body)
                            .foregroundStyle(Color.black.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }

                    addButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("定期振替")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .sheet(isPresented: $isAdding) { RecurringTransferEditView(existing: nil) }
        .sheet(item: $editingItem) { RecurringTransferEditView(existing: $0) }
    }

    // MARK: - 追加ボタン

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("定期振替を追加", systemImage: "plus")
                .font(AppFonts.button)
                .foregroundStyle(AppColors.main)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: AppLayout.selectionRowHeight)
                .padding(.horizontal, 20)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 1行分

private struct RecurringTransferRow: View {
    let item: RecurringTransferSettingData
    let onTapRow: () -> Void

    var body: some View {
        Button(action: onTapRow) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(item.fromMethodName) → \(item.toMethodName)")
                        .font(AppFonts.sectionTitle)
                        .foregroundStyle(Color.black.opacity(0.82))

                    Text(formattedAmount)
                        .font(AppFonts.body)
                        .foregroundStyle(Color.black.opacity(0.6))

                    Text(item.day == 31 ? "毎月末" : "毎月\(item.day)日")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.22))
                    .padding(.top, 3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var formattedAmount: String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        return (n.string(from: NSNumber(value: item.amount)) ?? "\(item.amount)") + "円"
    }
}
