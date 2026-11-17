import SwiftUI

// MARK: - 設定 > 一般 > 帳簿の共有
//
// 現在選択中の帳簿を対象にした共有管理画面。CKShare本体の実装はまだ行っていない
// （Phase 6: CloudKit同期有効化 / CKShare帳簿共有で実装する）。
// 現時点ではBookSharingViewModel/BookSharingServiceの枠組みを通して状態を表示するが、
// BookSharingServiceが常に「未共有」を返すスタブのため、共有中の見た目・操作は
// 実データが揃うまでは基本的に到達しない（開始/管理/停止/参加離脱は「準備中」エラーを表示する）。

struct BookSharingSettingView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var bookDataObserver = BookDataSync.observer()
    @StateObject private var viewModel = BookSharingViewModel()
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    @State private var isBookPickerPresented = false
    @State private var isStopConfirmPresented = false

    private var bookDataList: [BookData] { bookDataObserver.items }
    private var visibleBooks: [BookData] { bookDataList.filter { !$0.isArchived } }

    private var targetBook: BookData? {
        guard let targetBookId = viewModel.targetBookId else { return nil }
        return visibleBooks.first(where: { $0.id == targetBookId })
    }

    var body: some View {
        NavigationStack {
            List {
                targetBookSection

                if viewModel.isLoadingStatus {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("共有状態を確認しています")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } else if viewModel.isShared {
                    sharedStatusContent
                } else {
                    notSharedContent
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("帳簿の共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .onAppear {
            viewModel.resolveInitialTarget(availableBooks: bookDataList, selectedBookIdString: selectedBookIdString)
        }
        .task(id: viewModel.targetBookId) {
            await viewModel.loadShareStatus()
        }
        .sheet(isPresented: $isBookPickerPresented) {
            BookSharingTargetPickerView(
                books: visibleBooks,
                selectedBookId: viewModel.targetBookId
            ) { book in
                viewModel.selectTargetBook(book.id)
                isBookPickerPresented = false
            }
        }
        .alert("エラー", isPresented: errorAlertBinding) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay {
            if isStopConfirmPresented {
                DestructiveConfirmationDialogView(
                    title: "この帳簿の共有を停止しますか？",
                    message: "共有を停止すると、参加者はこの帳簿を表示・編集できなくなります。あなたの端末にある帳簿のデータは削除されません。",
                    destructiveLabel: "共有を停止",
                    onCancel: { isStopConfirmPresented = false },
                    onDestructive: {
                        isStopConfirmPresented = false
                        Task { await viewModel.stopSharing() }
                    }
                )
                .transition(.opacity)
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    // MARK: - 共有する家計簿

    @ViewBuilder
    private var targetBookSection: some View {
        Section {
            Button {
                if visibleBooks.count > 1 {
                    isBookPickerPresented = true
                }
            } label: {
                HStack {
                    Text(targetBook?.name ?? "-")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Spacer()
                    if visibleBooks.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.gray.opacity(0.4))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(visibleBooks.count <= 1)
        } header: {
            Text("共有する家計簿")
        } footer: {
            Text("この家計簿のデータのみ共有されます")
        }
    }

    // MARK: - 未共有

    @ViewBuilder
    private var notSharedContent: some View {
        Section {
            Text("この帳簿は共有されていません")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.7))
            Text("家族やパートナーを招待すると、同じ家計簿を一緒に編集できます。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.45))

            Button {
                Task { await viewModel.startSharing() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isProcessingAction {
                        ProgressView()
                    } else {
                        Text("共有を開始")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(viewModel.isProcessingAction || viewModel.targetBookId == nil)
        }
    }

    // MARK: - 共有中

    @ViewBuilder
    private var sharedStatusContent: some View {
        if case .shared(let detail) = viewModel.shareStatus {
            Section {
                HStack {
                    Text("共有状態")
                    Spacer()
                    Text("共有中")
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                HStack {
                    Text("所有者")
                    Spacer()
                    Text(detail.ownerName ?? "-")
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                HStack {
                    Text("自分の役割")
                    Spacer()
                    Text(detail.isOwner ? "所有者" : "参加者")
                        .foregroundStyle(Color.black.opacity(0.5))
                }
            } header: {
                Text("この帳簿は共有中です")
            }

            Section {
                if detail.participantsUnavailable {
                    Text("参加者情報を取得できません")
                        .foregroundStyle(Color.black.opacity(0.4))
                } else if detail.participants.isEmpty {
                    Text("参加者はいません")
                        .foregroundStyle(Color.black.opacity(0.4))
                } else {
                    ForEach(detail.participants) { participant in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(participant.name)
                                .font(AppFonts.rowTitle)
                                .foregroundStyle(Color.black.opacity(0.8))
                            HStack {
                                if let contact = participant.contact {
                                    Text(contact)
                                        .font(AppFonts.caption)
                                        .foregroundStyle(Color.black.opacity(0.45))
                                }
                                Spacer()
                                Text(participant.roleOrStatusLabel)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.black.opacity(0.45))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("参加者")
            }

            Section {
                Button {
                    Task { await viewModel.manageSharing() }
                } label: {
                    Text("共有を管理する")
                }
                .disabled(viewModel.isProcessingAction)

                if detail.isOwner {
                    Button(role: .destructive) {
                        isStopConfirmPresented = true
                    } label: {
                        Text("共有を停止する")
                    }
                    .disabled(viewModel.isProcessingAction)
                } else {
                    Button(role: .destructive) {
                        Task { await viewModel.leaveSharing() }
                    } label: {
                        Text("共有から抜ける")
                    }
                    .disabled(viewModel.isProcessingAction)
                }
            }
        }
    }
}

// MARK: - 共有対象の帳簿を選ぶピッカー

private struct BookSharingTargetPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let books: [BookData]
    let selectedBookId: UUID?
    let onSelect: (BookData) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(books) { book in
                    Button {
                        onSelect(book)
                    } label: {
                        HStack {
                            Text(book.name)
                                .font(AppFonts.rowTitle)
                                .foregroundStyle(Color.black.opacity(0.8))
                            Spacer()
                            if book.id == selectedBookId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.main)
                            }
                        }
                        .frame(minHeight: AppLayout.selectionRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("共有する帳簿を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
    }
}
