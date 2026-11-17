import SwiftUI
import Combine

struct CalendarView: View {
    @Binding var selectedTab: AppTab
    @Binding var inputInitialDate: Date
    @Binding var inputInitialType: String
    @Binding var isEditingTransactionPresented: Bool
    @Binding var analysisJumpTarget: AnalysisJumpTarget?
    let resetTrigger: Int

    @StateObject private var transferDataObserver = TransferDataSync.observer()
    private var allTransferData: [TransferData] { transferDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    @StateObject private var viewModel = CalendarViewModel()

    // MARK: - 複数帳簿

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    // MARK: - 履歴編集画面オーバーレイ状態（収入・支出）

    @State private var editingTransactionItem: TransactionListItem?

    // MARK: - 振替編集シート

    @State private var editingTransferData: TransferData?

    // MARK: - 日付ピッカー表示状態

    @State private var isDatePickerPresented = false
    @State private var temporarySelectedDate = Date()

    private let calendarGridTopOffset: CGFloat = 0

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    // ヘッダーの年月見出しは、月の開始日設定（年月表示基準）を反映したラベルを表示する
    // （viewModel.selectedDateの暦月をanchorとして扱う）。
    private var calendarTitleLabel: String {
        guard let range = AccountingMonthCalculator.range(containing: viewModel.selectedDate)
        else { return Self.monthTitleFormatter.string(from: viewModel.selectedDate) }
        return "\(range.labelYear)年\(range.labelMonth)月"
    }

    var body: some View {
        ZStack {
            AppScreenContainer {
                calendarContent
            } headerOverlay: {
                ZStack(alignment: .top) {
                    CalendarHeaderView(
                        selectedDate: $viewModel.selectedDate,
                        onTitleTap: {
                            temporarySelectedDate = viewModel.selectedDate
                            viewModel.closeDayAction()
                            isDatePickerPresented = true
                        },
                        titleOverride: calendarTitleLabel
                    )
                    HeaderSearchButtonView()
                }
                .frame(height: AppLayout.headerHeight)
            }

            if isDatePickerPresented {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isDatePickerPresented = false
                        }

                    CalendarDatePickerModalView(
                        selectedDate: $temporarySelectedDate,
                        onCancel: {
                            isDatePickerPresented = false
                        },
                        onConfirm: {
                            viewModel.moveToDate(temporarySelectedDate)
                            isDatePickerPresented = false
                        }
                    )
                    .zIndex(20)
                }
                .transition(.opacity)
                .zIndex(20)
            }

            if viewModel.isDayActionPresented, let currentBookId {
                CalendarDayActionView(
                    targetDate: viewModel.inputTargetDate,
                    periodStartDate: viewModel.monthAggregate.periodStartDate,
                    carryoverAmount: viewModel.monthAggregate.carryoverAmount,
                    bookId: currentBookId,
                    onCreateNew: {
                        inputInitialDate = viewModel.inputTargetDate
                        inputInitialType = "支出"
                        viewModel.closeDayAction()
                        selectedTab = .input
                    },
                    onSelectTransaction: { item in
                        viewModel.closeDayAction()
                        handleSelectTransaction(item)
                    },
                    onDismiss: {
                        viewModel.closeDayAction()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                .zIndex(5)
            }

            if let item = editingTransactionItem {
                TransactionHistoryEditView(
                    item: item,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            editingTransactionItem = nil
                        }
                        isEditingTransactionPresented = false
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
            }

        }
        .sheet(item: $editingTransferData) { transfer in
            TransferEditView(existing: transfer)
        }
        .onChange(of: resetTrigger) { _, _ in
            resetToInitialState()
        }
    }

    // MARK: - タブ再タップ時の初期表示リセット

    private func resetToInitialState() {
        viewModel.closeDayAction()
        isDatePickerPresented = false
        editingTransactionItem = nil
        editingTransferData = nil
        isEditingTransactionPresented = false
        viewModel.moveToDate(Date())
    }

    private var calendarContent: some View {
        VStack(spacing: 0) {
            CalendarMonthGridView(viewModel: viewModel)
                .padding(.top, calendarGridTopOffset)

            CalendarSummaryView(
                viewModel: viewModel,
                onTapIncome: {
                    analysisJumpTarget = AnalysisJumpTarget(segment: .income, date: viewModel.selectedDate)
                    selectedTab = .analysis
                },
                onTapExpense: {
                    analysisJumpTarget = AnalysisJumpTarget(segment: .expense, date: viewModel.selectedDate)
                    selectedTab = .analysis
                },
                onTapBalance: {
                    analysisJumpTarget = AnalysisJumpTarget(segment: .asset, date: viewModel.selectedDate)
                    selectedTab = .analysis
                }
            )

            // 【レイアウト不具合の修正】bookIdが解決できない間（帳簿がまだ無い・CloudKit初回
            // 同期待ち等）、以前はMonthlyTransactionListViewをVStackから完全に取り除いていた。
            // この場合VStack自体の内容（月グリッド＋集計のみ）は親の`.frame(maxHeight: .infinity)`
            // より大きく縮むため、`.frame`の既定の中央揃えによりVStack全体が画面中央へ寄り、
            // ヘッダー直下に大きな空白ができ、カレンダー本体が画面下側に表示される不具合が
            // 実機で確認された。bookIdが無い間も同じ高さを埋める透明なプレースホルダーを
            // 表示することで、見た目のレイアウトを常に一定に保つ（デザイン自体は変更しない）。
            if let currentBookId {
                MonthlyTransactionListView(
                    selectedDate: viewModel.selectedDate,
                    carryoverAmount: viewModel.monthAggregate.carryoverAmount,
                    bookId: currentBookId,
                    onSelectTransaction: { item in
                        handleSelectTransaction(item)
                    }
                )
                // 【不具合修正・取引履歴リストが古い月のまま更新されない】
                // MonthlyTransactionListViewは@StateObjectで保持するCore Data observerの
                // NSPredicate（日付範囲・bookId）をinit時点に一度だけ構築する。SwiftUIは
                // 同じ型・同じ構造上の位置にある子Viewを明示的なIDの変更なしに再利用し続け、
                // let selectedDate/carryoverAmount等のプロパティだけを新しい値に差し替えて
                // @StateObjectはそのまま温存する仕様のため、.id()を付けていないと、
                // カレンダーの月を切り替えても（またはbookIdが別の帳簿に変わっても）
                // 一番最初に表示した月のobserverのまま固定され、以後ずっと古い月の取引が
                // 表示され続けていた（日付セルの合計・タップ時の日付別一覧は別経路の
                // CalendarTransactionService/viewModel.monthAggregate側で都度再計算される
                // ため正しく表示され、この下部リストだけが取り残されていた）。
                // 会計月のanchor（月の開始日設定を反映した実際の期間の単位）とbookIdが
                // 変わった時だけ新しいIDにすることで、月内の日付選択だけでは再生成されず
                // （スクロール位置等を無駄に失わない）、月またぎ・帳簿切り替え時には
                // 確実に新しいobserverへ作り直させる。
                .id(Self.monthlyTransactionListIdentity(bookId: currentBookId, selectedDate: viewModel.selectedDate))
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    // MARK: - 下部取引履歴リストの再生成キー
    //
    // MonthlyTransactionListViewに付与する.id()の値を計算する純粋関数。ロジックを
    // 切り出し、実際のCore Data接続やSwiftUIのView識別機構を介さずに、単体テストから
    // 「会計月のanchorまたはbookIdが変わればキーも変わる」「同じ会計月内の日付選択だけでは
    // キーが変わらない」ことを決定的に検証できるようにする。
    //
    // internal公開の理由: @testable経由でテストから直接呼べるようにするため。
    static func monthlyTransactionListIdentity(
        bookId: UUID, selectedDate: Date, calendar: Calendar = .current
    ) -> String {
        guard let anchor = AccountingMonthCalculator.range(containing: selectedDate, calendar: calendar) else {
            return "\(bookId.uuidString)-unknown"
        }
        return "\(bookId.uuidString)-\(anchor.anchorYear)-\(anchor.anchorMonth)"
    }

    // MARK: - 振替 / 収支 ルーティング

    private func handleSelectTransaction(_ item: TransactionListItem) {
        guard item.category != TransactionListItem.carryoverCategory else { return }
        if item.kind == .transfer {
            editingTransferData = allTransferData.first(where: { $0.id == item.sourceId })
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                editingTransactionItem = item
            }
            isEditingTransactionPresented = true
        }
    }
}

