import SwiftUI
import Combine

// MARK: - 巨大なViewBuilder対策
//
// 実機のみ、本ViewをタブでopenするとEXC_BAD_ACCESSで落ちる不具合があった。
// Address Sanitizerでの調査の結果、bodyの中に大量のsectionGroup/groupRowを直接並べていたことで
// VStackのContent型（TupleView）が肥大化し、実機側でのSwiftUIの型メタデータ展開中にクラッシュしていた
// （swift::Demangle::__runtime::TypeDecoder / decodeGenericArgs 付近でクラッシュ）。
// そのため、各セクションを個別の@ViewBuilder computed propertyに分割し、
// bodyのVStackがopaqueな`some View`だけを受け取るようにして型を小さく保っている。
// 表示内容・遷移先・ロジックは変更していない。

struct OtherView: View {
    let resetTrigger: Int

    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private var currentBookName: String {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.name ?? "設定"
    }

    // 現在の帳簿のゴミ箱内データ件数（支出+収入+振替）。TrashViewと同じ帳簿単位表示に揃える。
    private var trashedCount: Int {
        guard let bookId = currentBookId else { return 0 }
        return ExpenseDataSync.fetchTrashed(bookId: bookId).count
            + IncomeDataSync.fetchTrashed(bookId: bookId).count
            + TransferDataSync.fetchTrashed(bookId: bookId).count
    }

    // MARK: - 実装済み画面への遷移

    @State private var showsCreditCardSetting = false
    @State private var showsBankAccountSetting = false
    @State private var showsOtherMethodSetting = false
    @State private var showsPaymentMethodSetting = false
    @State private var showsReceiveMethodSetting = false
    @State private var showsAnalysisOrderSetting = false
    @State private var showsAssetGraphSetting = false
    @State private var showsFixedExpenseSetting = false
    @State private var showsRecurringIncomeSetting = false
    @State private var showsThemeColorSetting = false
    @State private var showsCategoryEditView = false
    @State private var showsPasscodeSettings = false
    @State private var showsAutoBackupSettings = false
    @State private var showsCSVExportSettings = false
    @State private var showsListColorSetting = false
    @State private var showsBudgetSetting = false
    @State private var showsCashSetting = false
    @State private var showsElectronicMoneySetting = false
    @State private var showsDebitCardSetting = false
    @State private var showsSecuritiesSetting = false
    @State private var showsCryptoSetting = false
    @State private var showsBudgetNotebookSetting = false
    @State private var showsRecurringTransferSetting = false
    @State private var showsAccountingMonthSetting = false
    @State private var showsWeekStartWeekdayPicker = false
    @State private var showsBookSwitchSetting = false
    @State private var showsBookSharingSetting = false
    @State private var showsCloudSyncSettings = false

    // MARK: - お問い合わせ（mailto:でデフォルトメールアプリを起動）

    @Environment(\.openURL) private var openURL
    @State private var showsMailUnavailable = false

    private let contactEmail = "latte.studio.app@gmail.com"
    private let contactSubject = "【家計簿アプリ】不具合報告"

    private var contactBody: String {
        [
            "■不具合の内容",
            "",
            "",
            "■発生手順",
            "1.",
            "2.",
            "3.",
            "",
            "■期待していた動作",
            "",
            "",
            "■端末情報",
            "アプリバージョン：\(DeviceInfo.appVersion)",
            "iOSバージョン：\(DeviceInfo.iOSVersion)",
            "端末名：\(DeviceInfo.deviceModelName)"
        ].joined(separator: "\n")
    }

    private func openContactMail() {
        // URLComponents + URLQueryItemに値をそのまま渡すと、Foundationが
        // 改行(\n)や■・日本語を含め正しく一度だけパーセントエンコードしてくれる。
        // ここで手動addingPercentEncodingを重ねると、%0Aなどが二重エンコードされて
        // メールアプリ側の改行が消える／文字化けする原因になるため行わない。
        // GmailアプリのmailtoパーサーはLF単独(%0A)の改行を詰めて1行にしてしまうため、
        // メール本文の正式な行末であるCRLF(\r\n)に変換してから渡す。
        let crlfBody = contactBody.replacingOccurrences(of: "\n", with: "\r\n")

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = contactEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: contactSubject),
            URLQueryItem(name: "body", value: crlfBody)
        ]
        guard let url = components.url else {
            showsMailUnavailable = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                showsMailUnavailable = true
            }
        }
    }

    // MARK: - データリセット（危険操作。確認アラート必須）

    @State private var showsDataResetConfirm = false
    @State private var showsTrashView = false
    @State private var showsDataResetCompleteAlert = false

    @AppStorage("showPreviousMonthCarryover") private var showPreviousMonthCarryover = false
    @AppStorage(MemoCameraIconSettings.storageKey)
    private var showsCameraIconInMemo: Bool = MemoCameraIconSettings.defaultValue
    @AppStorage(CalendarWeekStartSettings.storageKey)
    private var weekStartWeekday: Int = CalendarWeekStartSettings.defaultValue

    private let weekdaySymbols = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]

    @EnvironmentObject private var themeManager: ThemeManager

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }

    var body: some View {
        let step1 = withSheetsGroup1(mainContent)
        let step2 = withSheetsGroup2(step1)
        let step3 = withSheetsGroup3(step2)
        let step4 = withSheetsGroup4(step3)
        let step5 = withSheetsGroup5(step4)
        let step6 = withSheetsGroup6(step5)
        withFinalModifiers(step6)
    }

    // MARK: - body本体（ヘッダー + スクロールする設定項目一覧）

    private var mainContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                AppHeaderBackground()
                AppHeaderTitleView(title: currentBookName)
                    .frame(height: AppLayout.headerButtonSize, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, AppLayout.headerContentTopPadding)
            }
            .frame(height: AppLayout.headerHeight)

            ScrollView {
                VStack(spacing: 20) {
                    generalSettingsSection
                    moneyManagementSection
                    inputSettingsSection
                    calendarSettingsSection
                    analysisSettingsSection
                    dataSettingsSection
                    helpSettingsSection
                }
                .padding(.top, 20)
                .padding(.bottom, AppLayout.bottomNavigationHeight + 40)
            }
            .background(themeManager.backgroundColor)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - .sheet / .fullScreenCover / .alert 等の修飾子チェーン対策
    //
    // bodyに.sheetなどの修飾子を20個以上直接チェーンすると、1つの巨大なModifiedContent型になり、
    // 実機でSwiftUIの型メタデータ解決（swift::SubstGenericParametersFromMetadata）が
    // 終わらなくなる（フリーズ）ことが分かった。数個ずつグループ化し、
    // 各グループの戻り値を`some View`にすることで型の境界を作り、肥大化を防ぐ。

    @ViewBuilder
    private func withSheetsGroup1<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showsCreditCardSetting) { CreditCardSettingView() }
            .sheet(isPresented: $showsBankAccountSetting) { BankAccountSettingView() }
            .sheet(isPresented: $showsOtherMethodSetting) { PaymentReceiveSettingView() }
            .sheet(isPresented: $showsPaymentMethodSetting) { PaymentMethodSettingView() }
            .sheet(isPresented: $showsReceiveMethodSetting) { ReceiveMethodSettingView() }
    }

    @ViewBuilder
    private func withSheetsGroup2<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showsAnalysisOrderSetting) { AnalysisOrderSettingView() }
            .sheet(isPresented: $showsFixedExpenseSetting) { FixedExpenseListView() }
            .sheet(isPresented: $showsRecurringIncomeSetting) { RecurringIncomeListView() }
            .sheet(isPresented: $showsThemeColorSetting) { ThemeColorSettingView() }
    }

    @ViewBuilder
    private func withSheetsGroup3<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showsPasscodeSettings) { PasscodeSettingsView() }
            .sheet(isPresented: $showsAutoBackupSettings) { AutoBackupSettingsView() }
            .sheet(isPresented: $showsCSVExportSettings) { CSVExportSettingsView() }
            .sheet(isPresented: $showsListColorSetting) { ListColorSettingView() }
    }

    @ViewBuilder
    private func withSheetsGroup4<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showsBudgetSetting) { BudgetSettingView(year: currentYear, month: currentMonth) }
            .sheet(isPresented: $showsCashSetting) { CashSettingView() }
            .sheet(isPresented: $showsElectronicMoneySetting) { ElectronicMoneySettingView() }
            .sheet(isPresented: $showsDebitCardSetting) { DebitCardSettingView() }
            .sheet(isPresented: $showsSecuritiesSetting) { SecuritiesSettingView() }
    }

    @ViewBuilder
    private func withSheetsGroup5<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showsCryptoSetting) { CryptoSettingView() }
            .sheet(isPresented: $showsBudgetNotebookSetting) { BudgetNotebookSettingView() }
            .sheet(isPresented: $showsRecurringTransferSetting) { RecurringTransferListView() }
            .sheet(isPresented: $showsAssetGraphSetting) { AssetGraphSettingView() }
    }

    @ViewBuilder
    private func withSheetsGroup6<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showsAccountingMonthSetting) { AccountingMonthSettingView() }
            .sheet(isPresented: $showsWeekStartWeekdayPicker) { WeekStartWeekdayPickerView() }
            .sheet(isPresented: $showsBookSwitchSetting) { BookSwitchSettingView() }
            .sheet(isPresented: $showsBookSharingSetting) { BookSharingSettingView() }
            .sheet(isPresented: $showsTrashView) { TrashView() }
            .sheet(isPresented: $showsCloudSyncSettings) { CloudSyncSettingsView() }
    }

    @ViewBuilder
    private func withFinalModifiers<V: View>(_ content: V) -> some View {
        content
            .fullScreenCover(isPresented: $showsCategoryEditView) {
                CategoryEditView(selectedType: "支出")
            }
            .overlay {
                if showsDataResetConfirm {
                    DestructiveConfirmationDialogView(
                        title: "「\(currentBookName)」をリセットしますか？",
                        message: "この帳簿の家計簿データを削除して初期状態に戻します。\n他の帳簿は変更されません。\nこの操作は取り消せません。",
                        destructiveLabel: "リセットする",
                        onCancel: { showsDataResetConfirm = false },
                        onDestructive: {
                            showsDataResetConfirm = false
                            if let bookId = currentBookId {
                                DataResetService.resetAll(bookId: bookId)
                            }
                            showsDataResetCompleteAlert = true
                        }
                    )
                    .transition(.opacity)
                } else if showsMailUnavailable {
                    ContactEmailFallbackView(
                        email: contactEmail,
                        onClose: { showsMailUnavailable = false }
                    )
                    .transition(.opacity)
                }
            }
            .alert("リセットしました", isPresented: $showsDataResetCompleteAlert) {
                Button("OK") {}
            } message: {
                Text("この帳簿の家計簿データを削除し、初期状態に戻しました。")
            }
            .onChange(of: resetTrigger) { _, _ in
                resetToInitialState()
            }
    }

    // MARK: - セクション（それぞれ小さく独立した`some View`にして、bodyのVStackのContent型を肥大化させない）

    @ViewBuilder
    private var generalSettingsSection: some View {
        sectionGroup(header: "一般") {
            themeColorRow
            Divider().padding(.leading, 66)
            groupRow(icon: "list.bullet.rectangle", title: "リスト背景色") { showsListColorSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "lock.fill", title: "パスコードロック") { showsPasscodeSettings = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "calendar.badge.clock", title: "月の開始日") { showsAccountingMonthSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "books.vertical", title: "帳簿の切り替え") { showsBookSwitchSetting = true }
            Divider().padding(.leading, 66)
            groupRow(
                icon: "person.2",
                title: "帳簿の共有",
            ) { showsBookSharingSetting = true }
        }
    }

    @ViewBuilder
    private var moneySettingsSection: some View {
        sectionGroup(header: "お金の設定") {
            groupRow(icon: "repeat", title: "定期支出") { showsFixedExpenseSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "arrow.down.circle", title: "定期収入") { showsRecurringIncomeSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "arrow.left.arrow.right.circle", title: "定期振替") { showsRecurringTransferSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "chart.pie", title: "予算") { showsBudgetSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "tag", title: "カテゴリー") { showsCategoryEditView = true }
        }
    }

    @ViewBuilder
    private var moneyManagementRowsSection: some View {
        sectionGroup(header: "お金の管理") {
            groupRow(icon: "yensign.circle", title: "現金") { showsCashSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "creditcard.fill", title: "クレジットカード") { showsCreditCardSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "wave.3.right.circle", title: "電子マネー") { showsElectronicMoneySetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "creditcard", title: "デビットカード") { showsDebitCardSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "building.columns", title: "銀行口座") { showsBankAccountSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "chart.line.uptrend.xyaxis", title: "証券口座") { showsSecuritiesSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "bitcoinsign.circle", title: "暗号資産") { showsCryptoSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "ellipsis.circle", title: "その他") { showsOtherMethodSetting = true }
        }
    }

    @ViewBuilder
    private var moneyManagementSection: some View {
        moneySettingsSection
        moneyManagementRowsSection
    }

    @ViewBuilder
    private var inputSettingsSection: some View {
        sectionGroup(header: "入力") {
            toggleRow(
                icon: "camera",
                title: "カメラマークの表示",
                isOn: $showsCameraIconInMemo
            )
            Divider().padding(.leading, 66)
            groupRow(icon: "arrow.up.circle", title: "支払いの追加・並び替え") { showsPaymentMethodSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "arrow.down.circle", title: "受け取りの追加・並び替え") { showsReceiveMethodSetting = true }
        }
    }

    @ViewBuilder
    private var calendarSettingsSection: some View {
        sectionGroup(header: "カレンダー") {
            toggleRow(
                icon: "arrow.uturn.left.circle",
                title: "繰越金の表示",
                isOn: $showPreviousMonthCarryover
            )
            Divider().padding(.leading, 66)
            groupRow(
                icon: "calendar",
                title: "カレンダーの開始曜日",
                value: weekdaySymbols[CalendarWeekStartSettings.clamped(weekStartWeekday) - 1]
            ) { showsWeekStartWeekdayPicker = true }
        }
    }

    @ViewBuilder
    private var analysisSettingsSection: some View {
        sectionGroup(header: "分析") {
            groupRow(icon: "chart.bar.xaxis", title: "タブの並び替え") { showsAnalysisOrderSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "chart.xyaxis.line", title: "グラフ設定") { showsAssetGraphSetting = true }
        }
    }

    @ViewBuilder
    private var dataSettingsSection: some View {
        sectionGroup(header: "データ") {
            groupRow(
                icon: "icloud", title: "iCloud同期",
                value: CloudSyncSettings.shared.isUserEnabled ? "ON" : "OFF"
            ) { showsCloudSyncSettings = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "icloud.and.arrow.up", title: "バックアップ") { showsAutoBackupSettings = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "tablecells", title: "CSVエクスポート") { showsCSVExportSettings = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "book.closed", title: "家計簿ノート作成") { showsBudgetNotebookSetting = true }
            Divider().padding(.leading, 66)
            groupRow(icon: "trash", title: "ゴミ箱", value: "\(trashedCount)件") { showsTrashView = true }
            Divider().padding(.leading, 66)
            destructiveRow(icon: "trash", title: "データリセット") { showsDataResetConfirm = true }
        }
    }

    @ViewBuilder
    private var helpSettingsSection: some View {
        sectionGroup(header: "ヘルプ") {
            groupRow(icon: "envelope", title: "お問い合わせ") { openContactMail() }
        }
    }

    // MARK: - タブ再タップ時の初期表示リセット

    private func resetToInitialState() {
        showsCreditCardSetting = false
        showsBankAccountSetting = false
        showsOtherMethodSetting = false
        showsPaymentMethodSetting = false
        showsReceiveMethodSetting = false
        showsAnalysisOrderSetting = false
        showsAssetGraphSetting = false
        showsFixedExpenseSetting = false
        showsRecurringIncomeSetting = false
        showsThemeColorSetting = false
        showsCategoryEditView = false
        showsPasscodeSettings = false
        showsAutoBackupSettings = false
        showsCSVExportSettings = false
        showsListColorSetting = false
        showsBudgetSetting = false
        showsCashSetting = false
        showsElectronicMoneySetting = false
        showsDebitCardSetting = false
        showsSecuritiesSetting = false
        showsCryptoSetting = false
        showsRecurringTransferSetting = false
        showsAccountingMonthSetting = false
        showsWeekStartWeekdayPicker = false
        showsBookSwitchSetting = false
        showsBookSharingSetting = false
        showsCloudSyncSettings = false
        showsMailUnavailable = false
        showsDataResetConfirm = false
        showsDataResetCompleteAlert = false
        showsTrashView = false
    }

    // MARK: - Helpers

    private var themeColorRow: some View {
        Button { showsThemeColorSetting = true } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(themeManager.mainColor)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .frame(width: 32)
                Text("テーマカラー")
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
    }

    private func sectionGroup<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(header)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 6)
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.main)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppColors.main)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 64)
        .background(Color.white)
    }

    private func groupRow(
        icon: String,
        title: String,
        value: String? = nil,
        subtitle: String? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.main)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            .background(Color.white)
        }
        .buttonStyle(.plain)
    }

    private func destructiveRow(
        icon: String,
        title: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(width: 32)
                Text(title)
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
