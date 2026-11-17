import SwiftUI
import os

private let bankAccountSettingLogger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "BankAccountSettingView")

struct BankAccountSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()

    private var allAccounts: [BankAccountData] { bankAccountDataObserver.items }
    @State private var editingAccount: BankAccountData? = nil
    @State private var isAdding = false

    private var activeAccounts: [BankAccountData] {
        allAccounts
            .filter { $0.isActive && $0.bookId == currentBookId }
            .sorted {
                $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
            }
    }

    var body: some View {
        let bodyStart = CFAbsoluteTimeGetCurrent()

        // accountsをbody内で1回だけ計算して使い回す。計算プロパティのまま参照すると、
        // ForEach・空判定・ヘッダー表示のそれぞれで毎回フィルタ・ソートが走ってしまう
        // （データ件数が増えるほど負荷が積み重なる）。
        let accounts = activeAccounts
        let _ = bankAccountSettingLogger.debug("body evaluated: \(accounts.count) accounts")

        let content = NavigationStack {
            List {
                Section {
                    if accounts.isEmpty {
                        Text("登録されていません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                    } else {
                        ForEach(accounts) { account in
                            BankAccountRow(account: account, onTapRow: { editingAccount = account })
                        }
                    }
                    Button {
                        isAdding = true
                    } label: {
                        Label("銀行口座を追加", systemImage: "plus")
                            .font(AppFonts.button)
                            .foregroundStyle(AppColors.main)
                    }
                } header: {
                    Text("登録済み銀行口座")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("銀行口座")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        TimingDebugLog.mark("parent body construction (\(accounts.count) accounts)", since: bodyStart)

        return content
            .sheet(item: $editingAccount) { account in
                BankAccountEditView(existing: account)
            }
            .sheet(isPresented: $isAdding) {
                BankAccountEditView(existing: nil)
            }
    }
}

// MARK: - 口座1行分（専用View。対象口座と必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct BankAccountRow: View {
    let account: BankAccountData
    let onTapRow: () -> Void

    var body: some View {
        let rowStart = CFAbsoluteTimeGetCurrent()
        let _ = bankAccountSettingLogger.debug("row evaluated: \(account.accountName)")

        let content = Button(action: onTapRow) {
            HStack {
                Circle()
                    .fill(ColorHexConverter.color(from: account.colorHex))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.accountName)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    if let memo = account.memo, !memo.isEmpty {
                        Text(memo)
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .frame(maxWidth: .infinity, minHeight: AppLayout.selectionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        TimingDebugLog.mark("row(\(account.accountName)) construction", since: rowStart)
        return content
    }
}
