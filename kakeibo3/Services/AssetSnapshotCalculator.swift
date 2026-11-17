import Foundation

// MARK: - 総資産・資産推移グラフの計算（AnalysisMonthlySnapshotベース）
//
// BankAccountBalanceCalculator.totalAssets/dailyAssetPoints と同じ結果になるように、
// 全期間の生データを毎回スキャンする代わりに、事前計算済みのAnalysisMonthlySnapshotから組み立てる。
// 口座別・支払い方法別の内訳（summaries/paymentMethodSummaries）はここでは扱わない
// （AnalysisSnapshotが口座単位の粒度を持たないため、BankAccountBalanceCalculator側に残す）。
//
// 以前はAnalysisDailySnapshot（日ごとの独立モデル）を使っていたが、AnalysisMonthlySnapshotが
// 持つ日別配列（dailyExpenseTotals/dailyIncomeTotals/dailyCreditCardExpenseTotals/
// dailyTransferFeeTotals）から同じ値を再現できるため、そちらを直接読む形に切り替えた。

struct AssetSnapshotCalculator {
    let monthlySnapshots: [AnalysisMonthlySnapshot]
    let assetReflectionTiming: CreditCardAssetReflectionTiming

    private var monthlyByKey: [String: AnalysisMonthlySnapshot] {
        Dictionary(uniqueKeysWithValues: monthlySnapshots.map { ($0.yearMonth, $0) })
    }

    // MARK: - 総資産（指定日より前のぶん）

    /// - pmInitialOffset: incomeエントリが未作成の支払い方法初期残高の合計（呼び出し元で計算）
    func totalAssets(upTo endDate: Date, pmInitialOffset: Int = 0) -> Int {
        pmInitialOffset + cumulativeAssetNet(upTo: endDate)
    }

    private func cumulativeAssetNet(upTo endDate: Date) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: endDate)
        guard let monthStart = cal.date(from: comps) else { return 0 }
        let year = comps.year ?? 0
        let month = comps.month ?? 0

        let baseline = resolveMonthStartBalance(year: year, month: month)
        guard let monthSnap = monthlyByKey[yearMonthKey(year: year, month: month)] else { return baseline }

        var partial = 0
        for index in 0..<monthSnap.dailyExpenseTotals.count {
            guard let dayDate = cal.date(byAdding: .day, value: index, to: monthStart),
                  dayDate >= monthStart, dayDate < endDate else { continue }
            partial += assetNet(monthSnap: monthSnap, dayIndex: index)
        }
        return baseline + partial
    }

    // MARK: - 日次資産推移（startDate〜endDate 両端含む・1日1点）

    /// - pmInitialOffset: incomeエントリが未作成の支払い方法初期残高の合計（呼び出し元で計算）
    func dailyAssetPoints(from startDate: Date, to endDate: Date, pmInitialOffset: Int = 0) -> [(date: Date, value: Int)] {
        let cal = Calendar.current
        var days: [Date] = []
        var current = cal.startOfDay(for: startDate)
        let last = cal.startOfDay(for: endDate)
        while current <= last {
            days.append(current)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        guard !days.isEmpty else { return [] }

        let byKey = monthlyByKey

        var results: [(date: Date, value: Int)] = []
        results.reserveCapacity(days.count)

        // 月をまたぐたびにその月の開始残高（carryoverBalance相当）を基準値として取り直し、
        // 月内は日別配列を1件ずつ積み上げる（running sum）
        var currentMonthKey = ""
        var runningWithinMonth = 0

        for day in days {
            let comps = cal.dateComponents([.year, .month], from: day)
            let key = yearMonthKey(year: comps.year ?? 0, month: comps.month ?? 0)
            if key != currentMonthKey {
                currentMonthKey = key
                runningWithinMonth = resolveMonthStartBalance(year: comps.year ?? 0, month: comps.month ?? 0)
            }
            if let monthSnap = byKey[key] {
                let dayIndex = (comps.day ?? 1) - 1
                if dayIndex >= 0 && dayIndex < monthSnap.dailyExpenseTotals.count {
                    runningWithinMonth += assetNet(monthSnap: monthSnap, dayIndex: dayIndex)
                }
            }
            results.append((date: day, value: pmInitialOffset + runningWithinMonth))
        }
        return results
    }

    // MARK: - Private

    private func assetNet(monthSnap: AnalysisMonthlySnapshot, dayIndex: Int) -> Int {
        let expense = monthSnap.dailyExpenseTotals[dayIndex]
        let creditCard = monthSnap.dailyCreditCardExpenseTotals[dayIndex]
        let income = monthSnap.dailyIncomeTotals[dayIndex]
        let fees = monthSnap.dailyTransferFeeTotals[dayIndex]
        let assetExpense = assetReflectionTiming == .withdrawalDate ? expense - creditCard : expense
        return income - assetExpense - fees
    }

    /// 指定年月の「月初時点」の資産基準額。MonthlySnapshotがあればそのcarryoverBalanceを使い、
    /// 無ければ（未来月など）直近過去月のendOfMonthBalanceで代用する
    /// （それ以降に取引が無い以上、残高は変化しないため。Calendar側のresolveCarryoverと同じ考え方）。
    private func resolveMonthStartBalance(year: Int, month: Int) -> Int {
        let key = yearMonthKey(year: year, month: month)
        if let exact = monthlySnapshots.first(where: { $0.yearMonth == key }) {
            return exact.carryoverBalance
        }
        guard let latestPrior = monthlySnapshots
            .filter({ $0.yearMonth < key })
            .max(by: { $0.yearMonth < $1.yearMonth })
        else { return 0 }
        return latestPrior.endOfMonthBalance(assetReflectionTiming: assetReflectionTiming)
    }

    private func yearMonthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }
}
