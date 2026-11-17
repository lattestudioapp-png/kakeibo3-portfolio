import SwiftUI

// MARK: - AnalysisMonthlySnapshotの内訳（カテゴリー別・方法別）を、
// 1ヶ月〜複数ヶ月（年・全期間）ぶんまとめて[AnalysisCategorySummary]に変換する
//
// 月ごとに保存されているamountを合算してから改めてpercentageを計算する
// （保存済みpercentageは「その月単独」の割合なので、複数月をまたぐ場合はそのまま使えない）。
// 1%未満は既存のAnalysisViewModel.buildCategoryItemsと同じ基準で除外する。
// .month/.previousMonthは対象snapshotが1件になるだけで、同じロジックがそのまま単純ケースとして動く。

enum AnalysisSnapshotBreakdownAggregator {

    // MARK: - カテゴリー別（支出・収入共通）

    static func categorySummaries(
        current: [AnalysisMonthlySnapshot],
        previous: [AnalysisMonthlySnapshot],
        pick: (AnalysisMonthlySnapshot) -> [AnalysisCategoryAmount],
        categoryType: String,
        categories: [CategoryData]
    ) -> [AnalysisCategorySummary] {
        let currentTotals = mergeAmounts(current.flatMap(pick).map { (id: $0.categoryId, name: $0.categoryName, amount: $0.amount) })
        let previousTotals = mergeAmounts(previous.flatMap(pick).map { (id: $0.categoryId, name: $0.categoryName, amount: $0.amount) })
        return buildSummaries(current: currentTotals, previous: previousTotals) { name in
            categoryColor(for: name, type: categoryType, categories: categories)
        }
    }

    // MARK: - 支払い/受け取り方法別

    static func methodSummaries(
        current: [AnalysisMonthlySnapshot],
        previous: [AnalysisMonthlySnapshot],
        pick: (AnalysisMonthlySnapshot) -> [AnalysisMethodAmount],
        paymentMethods: [PaymentMethodSettingData],
        bankAccounts: [BankAccountData]
    ) -> [AnalysisCategorySummary] {
        let currentTotals = mergeAmounts(current.flatMap(pick).map { (id: $0.methodId, name: $0.methodName, amount: $0.amount) })
        let previousTotals = mergeAmounts(previous.flatMap(pick).map { (id: $0.methodId, name: $0.methodName, amount: $0.amount) })
        return buildSummaries(current: currentTotals, previous: previousTotals) { name in
            methodColor(for: name, paymentMethods: paymentMethods, bankAccounts: bankAccounts)
        }
    }

    // MARK: - Private: 合算

    private static func mergeAmounts(_ items: [(id: UUID?, name: String, amount: Int)]) -> [(id: UUID?, name: String, amount: Int)] {
        var totals: [String: (id: UUID?, name: String, amount: Int)] = [:]
        for item in items {
            let key = item.id?.uuidString ?? item.name
            if var existing = totals[key] {
                existing.amount += item.amount
                totals[key] = existing
            } else {
                totals[key] = item
            }
        }
        return Array(totals.values)
    }

    // MARK: - Private: percentage再計算 + 1%未満除外 + ソート + Summary化

    private static func buildSummaries(
        current: [(id: UUID?, name: String, amount: Int)],
        previous: [(id: UUID?, name: String, amount: Int)],
        color: (String) -> Color
    ) -> [AnalysisCategorySummary] {
        let positives = current.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
        let displayTotal = positives.reduce(0) { $0 + $1.amount }
        guard displayTotal > 0 else { return [] }

        var previousByKey: [String: Int] = [:]
        for item in previous {
            let key = item.id?.uuidString ?? item.name
            previousByKey[key] = item.amount
        }

        return positives.compactMap { item in
            let pct = Double(item.amount) / Double(displayTotal) * 100
            guard Int(pct) >= 1 else { return nil }
            let key = item.id?.uuidString ?? item.name
            return AnalysisCategorySummary(
                id: item.name,
                categoryName: item.name,
                color: color(item.name),
                totalAmount: item.amount,
                percentage: pct,
                monthOverMonthDiff: previousByKey[key].map { item.amount - $0 }
            )
        }
    }

    // MARK: - Private: カテゴリー色解決（AnalysisViewModel.categoryColorと同じロジック）

    private static func categoryColor(for name: String, type: String, categories: [CategoryData]) -> Color {
        if let hex = categories.first(where: { $0.name == name && $0.type == type })?.colorHex,
           !hex.isEmpty {
            let normalized = CategoryColorPalette.normalize(hex)
            if normalized != "#" && !normalized.isEmpty {
                return ColorHexConverter.color(from: normalized)
            }
        }
        return ColorHexConverter.color(
            from: CategoryColorPalette.colors[abs(name.hashValue) % CategoryColorPalette.colors.count]
        )
    }

    // MARK: - 支払い/受け取り方法の色解決
    //
    // お金の管理（現金・クレジットカード・銀行口座など）で設定された「グラフの色」（colorHex）を
    // 名前で逆引きする。手数料の疑似カテゴリーや削除済みの方法など一致しない名前は、
    // カテゴリーの色解決と同じくハッシュから決定的に色を選ぶ（毎回ランダムに変わらないように）。
    // AnalysisViewModel.buildMethodItemsLive（ライブ集計パス）とも共通利用する。
    //
    // お金の管理データを扱うグラフ・一覧の色は「支払い方法別グラフ」専用ではなく、この
    // colorHexを唯一の情報源とする共通設計にすること。新しく支払い/受け取り方法を色分け表示する
    // グラフや一覧を追加する場合も、独自の色パレット（固定配列・インデックス割当・色相回転など）を
    // 持たず、この関数（または colorHex を直接 ColorHexConverter.color(from:) に渡す形）を再利用する。
    static func methodColor(for name: String, paymentMethods: [PaymentMethodSettingData], bankAccounts: [BankAccountData]) -> Color {
        if let hex = paymentMethods.first(where: { $0.methodName == name })?.colorHex, !hex.isEmpty {
            return ColorHexConverter.color(from: hex)
        }
        if let hex = bankAccounts.first(where: { $0.accountName == name })?.colorHex, !hex.isEmpty {
            return ColorHexConverter.color(from: hex)
        }
        return ColorHexConverter.color(
            from: CategoryColorPalette.colors[abs(name.hashValue) % CategoryColorPalette.colors.count]
        )
    }
}
