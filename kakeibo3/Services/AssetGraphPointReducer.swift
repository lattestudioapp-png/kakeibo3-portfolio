import Foundation

// MARK: - 資産推移グラフの表示粒度
//
// 「最大表示点数以内に収まる中で、一番細かい粒度を選ぶ」方式。
// 期間の長さ（1年だから月別、等）では固定しない。

enum AssetTrendGranularity {
    case daily
    case weekly
    case monthly
    case yearly

    /// AssetGraphCacheData.granularityUsed への保存用文字列
    var storageValue: String {
        switch self {
        case .daily:   return "daily"
        case .weekly:  return "weekly"
        case .monthly: return "monthly"
        case .yearly:  return "yearly"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "weekly":  self = .weekly
        case "monthly": self = .monthly
        case "yearly":  self = .yearly
        default:        self = .daily
        }
    }
}

// MARK: - 粒度選択・間引きの結果

struct AssetGraphReduction {
    let points: [AssetChartPoint]
    let granularity: AssetTrendGranularity
}

// MARK: - 資産推移グラフの点数リデューサー
//
// 呼び出し側（AssetSnapshotCalculator / AssetDetailViewModel など）が用意した
// 「隙間のない日次配列」（取引が無い日も前日の値を引き継いだもの）を受け取り、
// 最大表示点数（maxPoints）以内に収まる中で一番細かい粒度を自動で選ぶ。
// 日別→週別→月別→年別の順に試し、それでも収まらなければ年別を均等に間引く。
//
// どの粒度でも「その期間の最後の日（＝期間終了時点の値）」を代表値として使うため、
// 日別配列に隙間が無ければ「取引が無い期間も前回の資産額を引き継ぐ」仕様は自動的に満たされる。
//
// 表示単位は常に自動（ユーザーが日間/週間/月間/年間を手動選択するUIは無い）。
// ユーザーが調整できるのは maxPoints（その他 > 分析 > グラフ設定）だけ。

enum AssetGraphPointReducer {

    static func reduce(dailyPoints: [AssetChartPoint], maxPoints: Int) -> AssetGraphReduction {
        guard !dailyPoints.isEmpty else {
            return AssetGraphReduction(points: [], granularity: .daily)
        }
        guard dailyPoints.count > maxPoints else {
            return AssetGraphReduction(points: dailyPoints, granularity: .daily)
        }

        let weekly = lastPerBucket(dailyPoints, key: weekKey)
        if weekly.count <= maxPoints {
            return AssetGraphReduction(points: ensureEndpoints(weekly, original: dailyPoints), granularity: .weekly)
        }

        let monthly = lastPerBucket(dailyPoints, key: monthKey)
        if monthly.count <= maxPoints {
            return AssetGraphReduction(points: ensureEndpoints(monthly, original: dailyPoints), granularity: .monthly)
        }

        let yearly = lastPerBucket(dailyPoints, key: yearKey)
        if yearly.count <= maxPoints {
            return AssetGraphReduction(points: ensureEndpoints(yearly, original: dailyPoints), granularity: .yearly)
        }

        let thinned = thinEvenly(yearly, maxPoints: maxPoints)
        return AssetGraphReduction(points: ensureEndpoints(thinned, original: dailyPoints), granularity: .yearly)
    }

    // MARK: - 最初/最後の点の保証
    //
    // 週別/月別/年別の間引き（lastPerBucket）は「区間の最後の点」だけを残すため、
    // 元データの一番最初の点がバケットの途中に埋もれて欠落することがある
    // （最後の点は「今日を含む最後の区間の最後」に必ず一致するため欠落しない）。
    // 元のdailyPointsが2点以上あるのに、間引き後に1点以下へ減ってしまうことも
    // ここで防ぐ（横ばいの2点グラフなどが「データ不足」扱いにならないようにするため）。
    private static func ensureEndpoints(_ reduced: [AssetChartPoint], original: [AssetChartPoint]) -> [AssetChartPoint] {
        guard let firstOriginal = original.first, let lastOriginal = original.last,
              original.count >= 2 else { return reduced }

        guard !reduced.isEmpty else { return [firstOriginal, lastOriginal] }

        var result = reduced
        if result.first?.date != firstOriginal.date {
            result.insert(firstOriginal, at: 0)
        }
        if result.last?.date != lastOriginal.date {
            result.append(lastOriginal)
        }
        if result.count < 2 {
            result = [firstOriginal, lastOriginal]
        }
        return result
    }

    // MARK: - バケットキー

    private static func weekKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    // 月次バケットは暦月ではなく、月の開始日設定を反映した会計月（anchor）単位でグループ化する。
    // デフォルト設定（開始日=1・調整なし）では暦月と完全に一致する。
    private static func monthKey(_ date: Date) -> String {
        guard let range = AccountingMonthCalculator.range(containing: date) else {
            let c = Calendar.current.dateComponents([.year, .month], from: date)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        }
        return "\(range.anchorYear)-\(range.anchorMonth)"
    }

    private static func yearKey(_ date: Date) -> String {
        "\(Calendar.current.component(.year, from: date))"
    }

    /// 同じキーが連続する区間ごとに最後の点だけを残す（＝その区間の終了時点の値）。
    /// 昇順（古い→新しい）を前提とする。
    private static func lastPerBucket(_ points: [AssetChartPoint], key: (Date) -> String) -> [AssetChartPoint] {
        guard !points.isEmpty else { return [] }
        var result: [AssetChartPoint] = []
        var currentKey: String? = nil
        for point in points {
            let k = key(point.date)
            if k == currentKey {
                result[result.count - 1] = point
            } else {
                currentKey = k
                result.append(point)
            }
        }
        return result
    }

    /// 最初と最後の点は必ず残しつつ、maxPoints以内になるよう均等に間引く。
    private static func thinEvenly(_ points: [AssetChartPoint], maxPoints: Int) -> [AssetChartPoint] {
        guard points.count > maxPoints, maxPoints > 1 else { return points }
        var picked: [AssetChartPoint] = []
        for i in 0..<maxPoints {
            let idx = Int((Double(i) / Double(maxPoints - 1)) * Double(points.count - 1))
            picked.append(points[idx])
        }
        // 重複除去（丸め誤差で同じindexが選ばれた場合）しつつ順序を維持
        var seen = Set<Date>()
        return picked.filter { seen.insert($0.date).inserted }
    }
}
