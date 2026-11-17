import SwiftUI

// MARK: - 分析詳細画面専用コンテナ
//
// 分析Viewから開くすべての詳細画面（カテゴリー詳細・支払い方法詳細・貯金額詳細など）に使う土台。
// 通常の AppScreenContainer とは分けており、下部タブバー用余白を持たない。
//
// ヘッダー背景は .background { AppColors.main.ignoresSafeArea(edges: .top) } で実装。
// コンテンツ自体は SafeArea を尊重した位置に配置され、背景だけが Dynamic Island 背後まで延伸する。
// これにより .sheet / fullScreenCover のどちらで表示されても機種ごとにズレにくい。
//
// 使用例:
//   AnalysisDetailScreenContainer(
//       title: "交通",
//       onClose: { dismiss() }
//   ) {
//       summaryCard
//       historyList
//   }

struct AnalysisDetailScreenContainer<Content: View>: View {
    let title: String
    let onClose: () -> Void

    // 月切り替えバー（任意）
    var showsMonthSelector: Bool = false
    var selectedDate: Binding<Date>? = nil

    // 期間フィルター（任意）
    var showsPeriodFilter: Bool = false
    var selectedPeriod: Binding<AnalysisPeriodType>? = nil
    var onCustomPeriodTap: (() -> Void)? = nil

    let content: Content

    init(
        title: String,
        onClose: @escaping () -> Void,
        showsMonthSelector: Bool = false,
        selectedDate: Binding<Date>? = nil,
        showsPeriodFilter: Bool = false,
        selectedPeriod: Binding<AnalysisPeriodType>? = nil,
        onCustomPeriodTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onClose = onClose
        self.showsMonthSelector = showsMonthSelector
        self.selectedDate = selectedDate
        self.showsPeriodFilter = showsPeriodFilter
        self.selectedPeriod = selectedPeriod
        self.onCustomPeriodTap = onCustomPeriodTap
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if showsMonthSelector, let dateBinding = selectedDate {
                monthSelectorBar(dateBinding)
            }

            if showsPeriodFilter, let periodBinding = selectedPeriod {
                periodFilterBar(periodBinding)
            }

            ScrollView {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background)
        }
        .background {
            // 全 SafeArea（Dynamic Island・ホームインジケーター）を背景色で塗る
            AppColors.background.ignoresSafeArea()
        }
    }

    // MARK: - ヘッダー
    //
    // HStack（バツボタン + タイトル + ミラースペーサー）に padding(.vertical) を付け、
    // .background { AppColors.main.ignoresSafeArea(edges: .top) } で背景を Dynamic Island まで延伸。
    // コンテンツ自体は SafeArea 内に収まるため、機種ごとのズレが起きない。

    private var headerView: some View {
        HStack(spacing: 0) {
            // バツボタン（左）
            HeaderCloseButtonView { onClose() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)

            Spacer()

            // タイトル（画面中央）
            // バツボタンと同幅の透明スペーサーを右に置くことでタイトルを中央に固定
            AppHeaderTitleView(title: title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            // タイトルを中央に保つためのミラースペーサー（バツボタンと同サイズ）
            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            // 背景のみ Dynamic Island 背後まで延伸。コンテンツ位置には影響しない。
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - 月切り替えバー

    private func monthSelectorBar(_ dateBinding: Binding<Date>) -> some View {
        MonthSelectorView(
            selectedDate: dateBinding,
            titleColor: Color.black.opacity(0.8),
            arrowColor: AppColors.main,
            arrowButtonBackgroundColor: AppColors.main.opacity(0.1),
            titleFontSize: 18,
            titleFontWeight: .semibold,
            arrowIconSize: 16,
            arrowButtonWidth: 32,
            arrowButtonHeight: 32,
            arrowButtonSpacing: 12,
            titleOverride: accountingMonthTitle(for: dateBinding.wrappedValue)
        )
        .padding(.horizontal, 28)
        .frame(height: AppLayout.detailMonthSelectorBarHeight)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.12))
                .frame(height: 1)
        }
    }

    // 月の開始日設定（年月表示基準）を反映したラベルを返す。dateの暦月をそのままanchorとして
    // 使うと、月の開始日設定次第では実際に属する会計期間とズレることがあるため、
    // range(containing:)でdateが実際に属する会計期間を検索して求める。
    private func accountingMonthTitle(for date: Date) -> String? {
        AccountingMonthCalculator.range(containing: date).map { "\($0.labelYear)年\($0.labelMonth)月" }
    }

    // MARK: - 期間フィルターバー

    private func periodFilterBar(_ periodBinding: Binding<AnalysisPeriodType>) -> some View {
        AnalysisPeriodSelectorView(
            selectedPeriod: periodBinding,
            onCustomTap: onCustomPeriodTap
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.12))
                .frame(height: 1)
        }
    }
}
