import SwiftUI

// MARK: - 設定 > 一般 > 帳簿の切り替え
//
// 現在の帳簿の確認、帳簿一覧の表示・切り替え・作成ができる画面。
// 右上の「編集」で編集モードに入り、各行タップで帳簿編集画面（名前変更・削除）を開く。
// メイン帳簿（固定費/定期収入/定期振替の自動生成先）は削除できない（名前変更は可能）。
// 削除時はその帳簿のデータをすべて削除する（BookDeletionService参照）。

struct BookSwitchSettingView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    @State private var isCreateAlertPresented = false
    @State private var newBookName = ""
    @State private var isDuplicateBookNameAlertPresented = false

    @State private var isEditMode = false
    @State private var editingBook: BookData?

    private var visibleBooks: [BookData] {
        bookDataList.filter { !$0.isArchived }
    }

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var currentBookName: String {
        visibleBooks.first(where: { $0.id == currentBookId })?.name ?? "-"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visibleBooks) { book in
                        bookRow(book)
                    }

                    if !isEditMode {
                        Button {
                            newBookName = ""
                            isCreateAlertPresented = true
                        } label: {
                            Label("新しい帳簿を作成", systemImage: "plus")
                                .font(AppFonts.button)
                                .foregroundStyle(AppColors.main)
                        }
                    }
                } header: {
                    Text("帳簿")
                } footer: {
                    Text("現在の帳簿：\(currentBookName)")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("帳簿の切り替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditMode ? "完了" : "編集") {
                        isEditMode.toggle()
                    }
                    .foregroundStyle(AppColors.main)
                }
            }
        }
        .alert("新しい帳簿を作成", isPresented: $isCreateAlertPresented) {
            TextField("帳簿名", text: $newBookName)
            Button("作成") { createBook() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("帳簿の名前を入力してください")
        }
        .alert("エラー", isPresented: $isDuplicateBookNameAlertPresented) {
            Button("OK") {}
        } message: {
            Text(DuplicateNameChecker.duplicateBookNameErrorMessage)
        }
        .sheet(item: $editingBook) { book in
            BookEditView(
                book: book,
                allBooks: bookDataList,
                selectedBookIdString: $selectedBookIdString
            )
            .id(book.id)
        }
    }

    // MARK: - 帳簿行

    @ViewBuilder
    private func bookRow(_ book: BookData) -> some View {
        Button {
            if isEditMode {
                editingBook = book
            } else {
                selectedBookIdString = book.id.uuidString
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.name)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    if book.isMain {
                        Text("メイン帳簿")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                }
                Spacer()
                if isEditMode {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.gray.opacity(0.4))
                } else if book.id == currentBookId {
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

    // MARK: - 作成

    private func createBook() {
        let trimmed = newBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !DuplicateNameChecker.isDuplicateBookName(trimmed, in: bookDataList) else {
            isDuplicateBookNameAlertPresented = true
            return
        }
        let nextSortOrder = (bookDataList.map(\.sortOrder).max() ?? -1) + 1
        let book = BookData(name: trimmed, sortOrder: nextSortOrder)
        BookDataSync.insert(book)
        selectedBookIdString = book.id.uuidString
    }
}

// MARK: - 帳簿編集画面（名前変更・削除）

private struct BookEditView: View {
    @Environment(\.dismiss) private var dismiss

    let book: BookData
    let allBooks: [BookData]
    @Binding var selectedBookIdString: String

    @State private var nameText: String
    @State private var isDeleteConfirmPresented = false

    private static let maxNameLength = 20

    init(book: BookData, allBooks: [BookData], selectedBookIdString: Binding<String>) {
        self.book = book
        self.allBooks = allBooks
        self._selectedBookIdString = selectedBookIdString
        self._nameText = State(initialValue: book.name)
    }

    private var trimmedName: String {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameEmpty: Bool {
        trimmedName.isEmpty
    }

    private var isDuplicateName: Bool {
        DuplicateNameChecker.isDuplicateBookName(trimmedName, excluding: book.id, in: allBooks)
    }

    private var canSave: Bool {
        !isNameEmpty && !isDuplicateName
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("帳簿名", text: $nameText)
                            .font(AppFonts.rowTitle)
                            .onChange(of: nameText) { _, newValue in
                                if newValue.count > Self.maxNameLength {
                                    nameText = String(newValue.prefix(Self.maxNameLength))
                                }
                            }
                        if isNameEmpty {
                            Text("帳簿名を入力してください")
                                .font(AppFonts.caption)
                                .foregroundStyle(Color.red.opacity(0.75))
                        } else if isDuplicateName {
                            Text("同じ名前の帳簿がすでにあります")
                                .font(AppFonts.caption)
                                .foregroundStyle(Color.red.opacity(0.75))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("帳簿名")
                }

                Section {
                    if book.isMain {
                        Text("メイン帳簿は削除できません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.4))
                    } else {
                        Button {
                            isDeleteConfirmPresented = true
                        } label: {
                            Text("削除する")
                                .foregroundStyle(Color.red.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("帳簿を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? AppColors.main : Color.gray.opacity(0.4))
                        .disabled(!canSave)
                }
            }
        }
        .overlay {
            if isDeleteConfirmPresented {
                DestructiveConfirmationDialogView(
                    title: "「\(book.name)」を削除しますか？",
                    message: "この帳簿と、この帳簿に保存されている家計簿データを削除します。\n他の帳簿は変更されません。\nこの操作は取り消せません。",
                    destructiveLabel: "削除する",
                    onCancel: { isDeleteConfirmPresented = false },
                    onDestructive: {
                        isDeleteConfirmPresented = false
                        deleteBook()
                    }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - 保存・削除

    private func save() {
        guard canSave else { return }
        var updated = book
        updated.name = trimmedName
        BookDataSync.update(updated)
        dismiss()
    }

    private func deleteBook() {
        guard !book.isMain else { return }
        let deletedId = book.id
        let wasSelected = UUID(uuidString: selectedBookIdString) == deletedId
        BookDeletionService.deleteBook(book)
        if wasSelected, let mainBook = allBooks.first(where: { $0.isMain }) {
            selectedBookIdString = mainBook.id.uuidString
        }
        dismiss()
    }
}
