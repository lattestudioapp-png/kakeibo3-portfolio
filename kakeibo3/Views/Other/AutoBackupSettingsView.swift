import SwiftUI
import UniformTypeIdentifiers

// MARK: - 自動バックアップ設定画面

struct AutoBackupSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var backupManager = BackupManager.shared

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    // バックアップ／復元は常に「今開いている帳簿」だけを対象にする。他の帳簿には一切触れない。
    private var currentBook: BookData? {
        BookResolver.resolveCurrentBook(from: BookDataSync.fetchAll(), selectedIdString: selectedBookIdString)
    }

    // MARK: - State

    @State private var showsFolderPicker      = false
    @State private var showsFilePicker        = false
    @State private var showsRestoreConfirmation = false
    @State private var pendingRestoreURL: URL? = nil
    @State private var showsShareSheet        = false
    @State private var shareURL: URL?         = nil

    @State private var alertTitle   = ""
    @State private var alertMessage = ""
    @State private var showsAlert   = false

    // restore()が資産グラフキャッシュの再生成も含めて完了するまでボタンを無効化し、
    // 進行中であることを表示する（UIが固まって見えないようにする。処理自体は非同期で
    // メインスレッドを塞がない）。
    @State private var isRestoring = false

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.sheetBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        autoBackupSection
                        statusSection
                        actionsSection
                        noteView
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        // フォルダ選択
        .sheet(isPresented: $showsFolderPicker) {
            FolderPickerView { url in
                BackupManager.shared.saveBackupFolderBookmark(from: url)
                showsFolderPicker = false
            } onCancel: {
                showsFolderPicker = false
            }
        }
        // 復元ファイル選択
        .fileImporter(
            isPresented: $showsFilePicker,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                pendingRestoreURL = url
                showsRestoreConfirmation = true
            case .failure(let error):
                showAlert(title: "エラー", message: "ファイルの選択に失敗しました。\(error.localizedDescription)")
            }
        }
        // 復元確認アラート
        .alert("復元の確認", isPresented: $showsRestoreConfirmation) {
            Button("キャンセル", role: .cancel) { pendingRestoreURL = nil }
            Button("復元する", role: .destructive) { performRestore() }
        } message: {
            Text("「\(currentBook?.name ?? "この帳簿")」のデータをバックアップデータで置き換えます。他の帳簿のデータは変更されません。よろしいですか？")
        }
        // 汎用アラート
        .alert(alertTitle, isPresented: $showsAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        // 共有シート
        .sheet(isPresented: $showsShareSheet) {
            if let url = shareURL {
                ActivityShareView(url: url)
            }
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppHeaderTitleView(title: "バックアップ")
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - 自動バックアップ ON/OFF（無料版ではONにできない）

    private var autoBackupEnabledBinding: Binding<Bool> {
        Binding(
            get: { backupManager.autoBackupEnabled },
            set: { newValue in backupManager.autoBackupEnabled = newValue }
        )
    }

    // MARK: - 自動バックアップ ON/OFF & 頻度

    private var autoBackupSection: some View {
        sectionCard(header: "自動バックアップ") {
            HStack(spacing: 14) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.main)
                    .frame(width: 32)
                Text("自動バックアップ")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Toggle("", isOn: autoBackupEnabledBinding)
                    .labelsHidden()
                    .tint(AppColors.main)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)

            if backupManager.autoBackupEnabled {
                Divider().padding(.leading, 66)

                HStack(spacing: 14) {
                    Image(systemName: "clock")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.main)
                        .frame(width: 32)
                    Text("頻度")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Spacer()
                    Picker("", selection: $backupManager.autoBackupFrequency) {
                        Text("毎日").tag("daily")
                        Text("毎週").tag("weekly")
                        Text("毎月").tag("monthly")
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.main)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: 56)

                Divider().padding(.leading, 66)

                Button { showsFolderPicker = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "folder")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppColors.main)
                            .frame(width: 32)
                        Text("バックアップ先")
                            .font(AppFonts.rowTitle)
                            .foregroundStyle(Color.black.opacity(0.8))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.gray.opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 64)
                    .background(Color.white)
                }
                .buttonStyle(.plain)

                if backupManager.hasCustomBackupFolder {
                    Divider().padding(.leading, 66)

                    // 保存先を解除
                    Button {
                        BackupManager.shared.clearBackupFolder()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.red)
                                .frame(width: 32)
                            Text("保存先を解除")
                                .font(AppFonts.rowTitle)
                                .foregroundStyle(Color.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.gray.opacity(0.4))
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 64)
                        .background(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - バックアップ状況

    private var statusSection: some View {
        sectionCard(header: "バックアップ状況") {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.main)
                    .frame(width: 32)
                Text("最終バックアップ")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Spacer()
                Text(lastBackupText)
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.45))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
        }
    }

    private var lastBackupText: String {
        guard let date = backupManager.lastBackupDate else { return "未実行" }
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: date)
    }

    // MARK: - 操作ボタン

    private var actionsSection: some View {
        sectionCard(header: "操作") {
            Button { performBackupNow() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.main)
                        .frame(width: 32)
                    Text("今すぐバックアップ")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.gray.opacity(0.4))
                }
                .padding(.horizontal, 20)
                .frame(height: 64)
                .background(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)

            Divider().padding(.leading, 66)

            Button { showsFilePicker = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.red)
                        .frame(width: 32)
                    Text(isRestoring ? "復元中..." : "バックアップから復元")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.red)
                    Spacer()
                    if isRestoring {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.gray.opacity(0.4))
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 64)
                .background(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
        }
    }

    // MARK: - 注意文

    private var noteView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)
            Text("バックアップには家計簿データが含まれます。大切に管理してください。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 4)
    }

    // MARK: - 共通セクションカード

    private func sectionCard<C: View>(header: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.line, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - アクション

    private func performBackupNow() {
        guard let bookId = currentBook?.id else { return }
        do {
            let url = try BackupManager.shared.createBackup(bookId: bookId)
            // カスタムフォルダへの保存は共有シート不要。ローカルは共有を提供。
            if backupManager.hasCustomBackupFolder {
                showAlert(title: "バックアップ完了", message: "\(url.lastPathComponent)\n保存先：\(backupManager.backupFolderDisplayName)")
            } else {
                shareURL = url
                showsShareSheet = true
            }
        } catch let e as BackupError {
            showAlert(title: "バックアップ失敗", message: e.errorDescription ?? e.localizedDescription)
        } catch {
            showAlert(title: "バックアップ失敗", message: error.localizedDescription)
        }
    }

    private func performRestore() {
        guard let url = pendingRestoreURL, let bookId = currentBook?.id else { return }
        let bookName = currentBook?.name ?? "この帳簿"
        isRestoring = true
        Task {
            do {
                try await BackupManager.shared.restore(from: url, targetBookId: bookId)
                showAlert(title: "復元完了", message: "「\(bookName)」のデータをバックアップから復元しました。他の帳簿のデータは変更されていません。")
            } catch {
                showAlert(title: "復元失敗", message: error.localizedDescription)
            }
            isRestoring = false
            pendingRestoreURL = nil
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle   = title
        alertMessage = message
        showsAlert   = true
    }
}

// MARK: - フォルダ選択ピッカー

private struct FolderPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - UIActivityViewController ラッパー

private struct ActivityShareView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
