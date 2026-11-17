import SwiftUI

// MARK: - CSVエクスポート設定画面

struct CSVExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    // MARK: - 出力条件

    @State private var selectedEncoding: CSVExportEncoding = .utf8
    @State private var selectedTarget: CSVExportTarget = .all
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil

    // MARK: - 日付選択シート

    @State private var showsStartDatePicker = false
    @State private var showsEndDatePicker = false

    // MARK: - 共有シート

    @State private var showsShareSheet = false
    @State private var shareURL: URL? = nil

    // MARK: - アラート

    @State private var alertMessage = ""
    @State private var showsAlert = false

    // MARK: - エクスポート処理中フラグ（連打・初回race condition対策）

    @State private var isExporting = false

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.sheetBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        noteView
                        encodingSection
                        periodSection
                        targetSection
                        exportSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showsStartDatePicker) { startDatePickerSheet }
        .sheet(isPresented: $showsEndDatePicker) { endDatePickerSheet }
        .sheet(isPresented: $showsShareSheet) {
            if let url = shareURL {
                CSVExportShareSheetView(url: url)
            }
        }
        .alert(alertMessage, isPresented: $showsAlert) {
            Button("OK") {}
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            AppHeaderTitleView(title: "CSVエクスポート")
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

    // MARK: - 注意文

    private var noteView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)
            Text("メモに絵文字が含まれる場合、Shift_JISでは正しく出力できない事があります。その場合はUTF-8での出力をお試しください。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 4)
    }

    // MARK: - 文字コード選択

    private var encodingSection: some View {
        sectionCard(header: "文字コード") {
            encodingRow(title: "UTF-8", badge: "デフォルト", encoding: .utf8)
            Divider().padding(.leading, 20)
            encodingRow(title: "Shift_JIS", badge: "Excel等で利用", encoding: .shiftJIS)
        }
    }

    private func encodingRow(title: String, badge: String, encoding: CSVExportEncoding) -> some View {
        Button {
            selectedEncoding = encoding
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Text(badge)
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.4))
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.mainColor)
                    .opacity(selectedEncoding == encoding ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 期間指定

    private var periodSection: some View {
        sectionCard(header: "期間") {
            periodRow(title: "開始日", date: startDate) { showsStartDatePicker = true }
            Divider().padding(.leading, 20)
            periodRow(title: "終了日", date: endDate) { showsEndDatePicker = true }
        }
    }

    private func periodRow(title: String, date: Date?, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Text(date.map(formatDate) ?? "指定しない")
                    .font(AppFonts.body)
                    .foregroundStyle(Color.black.opacity(0.4))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    // MARK: - 開始日ピッカー

    private var startDatePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: Binding(
                    get: { startDate ?? Date() },
                    set: { newDate in
                        startDate = newDate
                        if let end = endDate, newDate > end { endDate = nil }
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .padding(.horizontal, 16)
            .navigationTitle("開始日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("指定しない") {
                        startDate = nil
                        showsStartDatePicker = false
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        if startDate == nil { startDate = Date() }
                        showsStartDatePicker = false
                    }
                }
            }
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.medium])
    }

    // MARK: - 終了日ピッカー

    private var endDatePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: Binding(
                    get: { endDate ?? Date() },
                    set: { newDate in
                        endDate = newDate
                        if let start = startDate, newDate < start { startDate = nil }
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .padding(.horizontal, 16)
            .navigationTitle("終了日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("指定しない") {
                        endDate = nil
                        showsEndDatePicker = false
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        if endDate == nil { endDate = Date() }
                        showsEndDatePicker = false
                    }
                }
            }
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.medium])
    }

    // MARK: - 出力対象

    private var targetSection: some View {
        sectionCard(header: "出力対象") {
            targetRow(title: "すべて", target: .all)
            Divider().padding(.leading, 20)
            targetRow(title: "支出のみ", target: .expenseOnly)
            Divider().padding(.leading, 20)
            targetRow(title: "収入のみ", target: .incomeOnly)
        }
    }

    private func targetRow(title: String, target: CSVExportTarget) -> some View {
        Button {
            selectedTarget = target
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.mainColor)
                    .opacity(selectedTarget == target ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - エクスポート実行

    private var exportSection: some View {
        sectionCard(header: "エクスポート") {
            Button {
                performExport()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(themeManager.mainColor)
                        .frame(width: 32)
                    Text("エクスポートする")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(themeManager.mainColor)
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 64)
                .background(Color.white)
                .contentShape(Rectangle())
                .opacity(isExporting ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
    }

    private func performExport() {
        guard !isExporting else { return }
        isExporting = true

        do {
            let url = try CSVExportService.exportCSV(
                bookId: currentBookId,
                encoding: selectedEncoding,
                target: selectedTarget,
                startDate: startDate,
                endDate: endDate
            )
            // shareURL の反映を確実にコミットさせてから isPresented を true にする。
            // 同一フレーム内で両方を更新すると、起動後最初の1回だけ .sheet の
            // content クロージャが古い（nilの）shareURL を参照し、
            // シートが開かない/空になることがあるため、次のランループへ回す。
            shareURL = url
            DispatchQueue.main.async {
                isExporting = false
                guard shareURL != nil else { return }
                showsShareSheet = true
            }
        } catch let error as CSVExportError {
            isExporting = false
            showAlert(error.errorDescription ?? "エクスポートに失敗しました。")
        } catch {
            isExporting = false
            showAlert(error.localizedDescription)
        }
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showsAlert = true
    }

    // MARK: - 共通セクションカード

    private func sectionCard<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
}

// MARK: - 共有シート

private struct CSVExportShareSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
