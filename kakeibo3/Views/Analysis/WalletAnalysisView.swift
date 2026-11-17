import SwiftUI
import Charts

// MARK: - AssetAnalysisView（軽量版）
//
// 集計済みデータを受け取る。資産推移グラフは分析Viewを開くたびに再計算しないよう
// キャッシュ方式の AssetTrendCacheCardView に委譲する（「更新」ボタンを押した時だけ再計算）。

struct AssetAnalysisView: View {
    // AnalysisViewModel から渡される集計済みデータ
    let totalAssets: Int
    let periodIncome: Int
    let periodExpense: Int
    let bankSummaries: [BankAccountBalanceSummary]
    let paymentMethodSummaries: [PaymentMethodBalanceSummary]
    let dateRange: AnalysisDateRange

    // 詳細シート
    @State private var detailTarget: AssetDetailTarget? = nil

    // テーマカラー変更時にグラフを再描画するために監視
    @AppStorage(AppColors.themeColorStorageKey)
    private var themeHex: String = AppColors.defaultThemeHex

    // MARK: - 導出値（軽量な算術のみ）

    private var monthlyBalance: Int { periodIncome - periodExpense }

    private var selectedMonthLabel: String {
        "\(Calendar.current.component(.month, from: dateRange.start))月"
    }

    private var totalAssetsDescriptionText: String {
        let cal = Calendar.current
        let year  = cal.component(.year,  from: dateRange.start)
        let month = cal.component(.month, from: dateRange.start)
        return "\(year)年\(month)月末時点"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            totalAssetsCard
            monthlyBalanceCard
            AssetTrendCacheCardView()
            if !bankSummaries.isEmpty { bankAccountsSection }
            ForEach(groupedPaymentMethodSummaries, id: \.type) { group in
                paymentMethodAssetsSection(type: group.type, summaries: group.items)
            }
        }
        .sheet(item: $detailTarget) { target in
            AssetDetailView(target: target)
        }
    }

    // MARK: - 総資産カード

    private var totalAssetsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("総資産")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.65))
            Text(formatAnalysisAmount(totalAssets))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(totalAssets >= 0 ? Color.black.opacity(0.82) : AppColors.expenseColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.top, 2)
            Text(totalAssetsDescriptionText)
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.4))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    // MARK: - 収支カード

    private var monthlyBalanceCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("\(selectedMonthLabel)の収支")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.52))
                Spacer()
                Text(monthlyBalanceText)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundStyle(monthlyBalanceColor)
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
            }
            .padding(.bottom, 11)

            Divider()

            HStack(spacing: 0) {
                incomeExpenseColumn(
                    label: "\(selectedMonthLabel)の収入", amount: periodIncome,
                    amountColor: Color.black.opacity(0.65), icon: "arrow.down.circle.fill"
                )
                Rectangle().fill(AppColors.line).frame(width: 1, height: 42)
                incomeExpenseColumn(
                    label: "\(selectedMonthLabel)の支出", amount: periodExpense,
                    amountColor: Color.black.opacity(0.65), icon: "arrow.up.circle.fill"
                )
            }
            .padding(.top, 11)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    private var monthlyBalanceText: String {
        if monthlyBalance > 0 { return "+\(formatAnalysisAmount(monthlyBalance))" }
        if monthlyBalance < 0 { return formatAnalysisDiff(monthlyBalance) }
        return formatAnalysisAmount(0)
    }

    private var monthlyBalanceColor: Color {
        if monthlyBalance > 0 { return AppColors.incomeColor }
        if monthlyBalance < 0 { return AppColors.expenseColor }
        return Color.black.opacity(0.82)
    }

    private func incomeExpenseColumn(label: String, amount: Int, amountColor: Color, icon: String) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.black.opacity(0.40))
                Text(label)
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.40))
            }
            Text(formatAnalysisAmount(amount))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .minimumScaleFactor(0.85)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 口座別残高セクション

    private var bankAccountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("口座別残高")
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.45))
            VStack(spacing: 0) {
                ForEach(bankSummaries) { summary in
                    bankRow(summary)
                    if bankSummaries.last?.id != summary.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
    }

    private func bankRow(_ summary: BankAccountBalanceSummary) -> some View {
        Button {
            detailTarget = AssetDetailTarget(
                id: summary.id, name: summary.name, kind: .bank,
                hasBalance: true, selectedDate: dateRange.start
            )
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(ColorHexConverter.color(from: summary.colorHex))
                    .frame(width: 10, height: 10)
                Text(summary.name)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("残高")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.4))
                    Text(formatAnalysisAmount(summary.balance))
                        .font(.system(size: 16, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(summary.balance >= 0 ? Color.black.opacity(0.65) : AppColors.expenseColor)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 支払い方法の種類ごとのグルーピング
    //
    // 設定画面「お金の管理」の並び順・アイコンに合わせて種類ごとにセクション分けする。

    private static let paymentMethodGroupOrder: [PaymentMethodType] = [
        .cash, .electronicMoney, .debitCard, .securities, .crypto, .bankTransfer, .other
    ]

    private var groupedPaymentMethodSummaries: [(type: PaymentMethodType, items: [PaymentMethodBalanceSummary])] {
        let groups = Dictionary(grouping: paymentMethodSummaries, by: { $0.type })
        return Self.paymentMethodGroupOrder.compactMap { type in
            guard let items = groups[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    // MARK: - 種類別セクション

    private func paymentMethodAssetsSection(type: PaymentMethodType, summaries: [PaymentMethodBalanceSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(type.displayName)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.45))
            VStack(spacing: 0) {
                ForEach(summaries) { summary in
                    paymentMethodRow(summary, type: type)
                    if summaries.last?.id != summary.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        }
    }

    private func paymentMethodRow(_ summary: PaymentMethodBalanceSummary, type: PaymentMethodType) -> some View {
        Button {
            detailTarget = AssetDetailTarget(
                id: summary.id, name: summary.name, kind: .paymentMethod,
                hasBalance: summary.isAsset, selectedDate: dateRange.start
            )
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(ColorHexConverter.color(from: summary.colorHex))
                    .frame(width: 10, height: 10)
                Text(summary.name)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("残高")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.4))
                    Text(formatAnalysisAmount(summary.balance))
                        .font(.system(size: 16, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(summary.balance >= 0 ? Color.black.opacity(0.65) : AppColors.expenseColor)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
