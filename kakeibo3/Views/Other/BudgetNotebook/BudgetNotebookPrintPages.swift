import SwiftUI

// MARK: - 印刷ページ共通の枠（タイトル・対象年月・アクセントライン・ページ番号）

private struct NotebookPageChrome<Content: View>: View {
    let title: String
    let periodLabel: String
    let accentColor: Color
    let pageSize: CGSize
    var pageInfo: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.black)
                Spacer()
                Text(periodLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.6))
            }

            Rectangle()
                .fill(accentColor)
                .frame(height: 3)
                .padding(.top, 8)
                .padding(.bottom, 18)

            content

            Spacer(minLength: 0)

            if let pageInfo {
                HStack {
                    Spacer()
                    Text(pageInfo)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.4))
                }
            }
        }
        .padding(28)
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .clipped()
    }
}

// MARK: - 金額フォーマット

private func notebookYen(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return "¥" + (formatter.string(from: NSNumber(value: value)) ?? "\(value)")
}

// MARK: - 収支まとめページ

struct MonthlySummaryPrintPage: View {
    let data: BudgetNotebookData
    let accentColor: Color
    let pageSize: CGSize
    let periodLabel: String
    var pageInfo: String? = nil

    var body: some View {
        NotebookPageChrome(
            title: "収支まとめ", periodLabel: periodLabel,
            accentColor: accentColor, pageSize: pageSize, pageInfo: pageInfo
        ) {
            VStack(spacing: 0) {
                row(label: "収入合計", value: "+" + notebookYen(data.totalIncome))
                row(label: "支出合計", value: "-" + notebookYen(data.totalExpense))
                row(label: "収支", value: (data.balance >= 0 ? "+" : "-") + notebookYen(abs(data.balance)), emphasized: true)

                if data.totalBudgetAmount > 0 {
                    Spacer().frame(height: 20)
                    Text("予算")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .padding(.bottom, 6)
                    row(label: "予算額", value: notebookYen(data.totalBudgetAmount))
                    row(label: "残り予算", value: (data.remainingBudget >= 0 ? "" : "-") + notebookYen(abs(data.remainingBudget)))
                    budgetBar
                }
            }
        }
    }

    private func row(label: String, value: String, emphasized: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.7))
                Spacer()
                Text(value)
                    .font(.system(size: emphasized ? 24 : 19, weight: emphasized ? .bold : .semibold))
                    .foregroundStyle(Color.black)
            }
            .padding(.vertical, 12)
            Divider()
        }
    }

    private var budgetBar: some View {
        GeometryReader { geo in
            let ratio = data.totalBudgetAmount > 0
                ? min(Double(data.totalExpense) / Double(data.totalBudgetAmount), 1.0)
                : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accentColor.opacity(0.15))
                RoundedRectangle(cornerRadius: 6)
                    .fill(accentColor)
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 14)
        .padding(.top, 10)
    }
}

// MARK: - カテゴリー別支出ページ

struct CategoryBreakdownPrintPage: View {
    let data: BudgetNotebookData
    let accentColor: Color
    let pageSize: CGSize
    let periodLabel: String
    var pageInfo: String? = nil

    private let maxRows = 14

    var body: some View {
        NotebookPageChrome(
            title: "カテゴリー別支出", periodLabel: periodLabel,
            accentColor: accentColor, pageSize: pageSize, pageInfo: pageInfo
        ) {
            if data.categories.isEmpty {
                Text("この月の支出データがありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black.opacity(0.4))
            } else {
                VStack(spacing: 12) {
                    ForEach(displayCategories) { category in
                        categoryRow(category)
                    }
                }
            }
        }
    }

    private var displayCategories: [NotebookCategorySummary] {
        guard data.categories.count > maxRows else { return data.categories }
        let visible = Array(data.categories.prefix(maxRows))
        let rest = data.categories.dropFirst(maxRows)
        let amount = rest.reduce(0) { $0 + $1.amount }
        let percentage = rest.reduce(0.0) { $0 + $1.percentage }
        let others = NotebookCategorySummary(
            categoryName: "その他（\(rest.count)件）", amount: amount, percentage: percentage, colorHex: "#CFCFCF"
        )
        return visible + [others]
    }

    private func categoryRow(_ category: NotebookCategorySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.categoryName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black)
                Spacer()
                Text(notebookYen(category.amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                Text(String(format: "%.0f%%", category.percentage * 100))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorHexConverter.color(from: category.colorHex).opacity(0.85))
                        .frame(width: geo.size.width * category.percentage)
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - 日別明細ページ

struct DailyDetailPrintPage: View {
    let entries: [NotebookDailyEntry]
    let pageIndex: Int
    let totalPages: Int
    let accentColor: Color
    let pageSize: CGSize
    let periodLabel: String

    var body: some View {
        NotebookPageChrome(
            title: "日別明細", periodLabel: periodLabel,
            accentColor: accentColor, pageSize: pageSize,
            pageInfo: "\(pageIndex) / \(totalPages)"
        ) {
            VStack(spacing: 0) {
                headerRow
                if entries.isEmpty {
                    Text("この月の入力データがありません")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.black.opacity(0.4))
                        .padding(.top, 12)
                } else {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("日付").frame(width: 44, alignment: .leading)
                Text("種別").frame(width: 32, alignment: .leading)
                Text("カテゴリ").frame(width: 80, alignment: .leading)
                Text("メモ").frame(maxWidth: .infinity, alignment: .leading)
                Text("金額").frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.5))
            .padding(.bottom, 6)
            Divider()
        }
    }

    private func entryRow(_ entry: NotebookDailyEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(shortDate(entry.date)).frame(width: 44, alignment: .leading)
                Text(entry.isExpense ? "支出" : "収入").frame(width: 32, alignment: .leading)
                Text(entry.category).frame(width: 80, alignment: .leading).lineLimit(1)
                Text(entry.memo).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                Text((entry.isExpense ? "-" : "+") + notebookYen(entry.amount))
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.8))
            .padding(.vertical, 6)
            Divider()
        }
    }

    // エントリ行ごと（ForEach内）に呼ばれるため、DateFormatterを毎回生成しないよう
    // static letでキャッシュする。
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private func shortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
}

// MARK: - 振り返り欄ページ

struct ReflectionPrintPage: View {
    let reflection: NotebookReflectionText
    let accentColor: Color
    let pageSize: CGSize
    let periodLabel: String
    var pageInfo: String? = nil

    var body: some View {
        NotebookPageChrome(
            title: "振り返り", periodLabel: periodLabel,
            accentColor: accentColor, pageSize: pageSize, pageInfo: pageInfo
        ) {
            VStack(alignment: .leading, spacing: 16) {
                reflectionBox(title: "今月よかったこと", text: reflection.goodThings)
                reflectionBox(title: "使いすぎたもの", text: reflection.overspent)
                reflectionBox(title: "来月気をつけること", text: reflection.nextMonthCaution)
                reflectionBox(title: "自由メモ", text: reflection.freeMemo)
            }
        }
    }

    private func reflectionBox(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                .frame(height: 78)
                .overlay(alignment: .topLeading) {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
        }
    }
}
