import SwiftUI
import Charts

// MARK: - 資産推移グラフの実際の描画部分（既に確定した点列を受け取るだけ）
//
// 「日次データから何点表示するか決める」処理（AssetTrendChartView＝ライブ計算、
// AssetTrendCacheCardView＝キャッシュ済みデータ）と、「実際にChartを描く」処理を分離した
// 低レベル共通コンポーネント。points は既に最終的な表示粒度・間引きが適用済みの前提。

struct AssetTrendChartBody: View {
    /// 表示する点列（昇順・既に最終的な間引き・粒度が適用済み）
    let points: [AssetChartPoint]
    /// points がどの粒度で作られたか（軸ラベル・ツールチップの表示形式に使う）
    let granularity: AssetTrendGranularity
    var valueName: String = "資産"

    // グラフタッチ選択（ドラッグ中のみ更新）
    @State private var selectedPoint: AssetChartPoint? = nil
    // ツールチップの水平アラインメント（左端付近は右側へ、右端付近は左側へ、
    // それ以外は従来通り点の中央上へ表示することでカード外へのはみ出しを防ぐ）
    @State private var tooltipAlignment: HorizontalAlignment = .center

    // ツールチップが反転を始める、プロット端からの距離（pt）。
    // ツールチップ自体のおおよその幅（左右のpadding込みで100〜140pt程度）の半分弱を目安にする。
    private let tooltipEdgeThreshold: CGFloat = 55

    private func tooltipAlignment(forPointX x: CGFloat, plotWidth: CGFloat) -> HorizontalAlignment {
        if x < tooltipEdgeThreshold { return .leading }
        if x > plotWidth - tooltipEdgeThreshold { return .trailing }
        return .center
    }

    private var periodStartDate: Date { points.first?.date ?? Date() }
    private var periodEndDate: Date { points.last?.date ?? Date() }

    /// チャートのX軸ドメイン（開始日==終了日でも幅を持たせる）
    private var chartDomain: ClosedRange<Date> {
        if periodStartDate < periodEndDate { return periodStartDate...periodEndDate }
        let cal = Calendar.current
        let extendedEnd = cal.date(byAdding: .day, value: 1, to: periodStartDate) ?? periodStartDate
        return periodStartDate...extendedEnd
    }

    private var hasData: Bool { !points.isEmpty }

    /// ちょうど1点しか無く、推移として線を引けない状態か。
    private var hasSinglePointOnly: Bool { points.count == 1 }

    /// 点が多いグラフでは、点そのものは小さく／非表示にして線を見やすくする。
    private var pointSymbolSize: Double? {
        let count = points.count
        if count > 40 { return nil }       // 線のみ
        if count > 20 { return 10 }        // 小さめ
        return 28
    }

    /// 横軸ラベル：表示している点から最大6つ、両端を必ず含む均等割りで選ぶ。
    private var axisDates: [Date] {
        let dates = points.map(\.date)
        guard dates.count > 1 else { return dates }
        let maxLabels = 6
        if dates.count <= maxLabels { return dates }
        var picked: [Date] = []
        for i in 0..<maxLabels {
            let idx = Int((Double(i) / Double(maxLabels - 1)) * Double(dates.count - 1))
            picked.append(dates[idx])
        }
        return Array(Set(picked)).sorted()
    }

    // MARK: - グラフ最近点を探索

    private func nearestPoint(to date: Date) -> AssetChartPoint? {
        points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    // 月次バケットの代表点は「バケット内最後の実日」のままだが、ラベル表示だけは
    // 月の開始日設定の年月表示（開始日/終了日基準）を反映する（実際の点の位置は変えない）。
    private func monthlyLabel(for date: Date) -> (year: Int, month: Int) {
        guard let range = AccountingMonthCalculator.range(containing: date) else {
            let cal = Calendar.current
            return (cal.component(.year, from: date), cal.component(.month, from: date))
        }
        return (range.labelYear, range.labelMonth)
    }

    // 静的フォーマッターを使用（body 描画のたびに生成しない）。
    private func formatChartDate(_ date: Date) -> String {
        switch granularity {
        case .daily, .weekly:
            return AnalysisViewModel.monthDayFormatter.string(from: date)
        case .monthly:
            let label = monthlyLabel(for: date)
            return "\(label.year)年\(label.month)月"
        case .yearly:
            return "\(Calendar.current.component(.year, from: date))年"
        }
    }

    private func formatAxisLabel(_ date: Date) -> String {
        let cal = Calendar.current
        switch granularity {
        case .daily, .weekly:
            return AnalysisViewModel.monthDayFormatter.string(from: date)
        case .monthly:
            let label = monthlyLabel(for: date)
            return "\(label.year)/\(label.month)"
        case .yearly:
            return "\(cal.component(.year, from: date))"
        }
    }

    private func shortAmountLabel(_ value: Int) -> String {
        let absVal = Swift.abs(value)
        let sign   = value < 0 ? "-" : ""
        if absVal >= 100_000_000 { return "\(sign)\(absVal / 100_000_000)億" }
        if absVal >= 10_000      { return "\(sign)\(absVal / 10_000)万" }
        if absVal >= 1_000       { return "\(sign)\(absVal / 1_000)千" }
        return "\(value)"
    }

    // MARK: - Body

    var body: some View {
        let themeColor = AppColors.main
        let selected   = selectedPoint
        let data       = points

        if !hasData || hasSinglePointOnly {
            // 0点・1点: 推移として線を引けるだけのデータが無い
            VStack {
                Spacer()
                Text("データ不足")
                    .font(AppFonts.body)
                    .foregroundStyle(Color.black.opacity(0.35))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
        } else {
            Chart {
                ForEach(data) { point in
                    AreaMark(
                        x: .value("日付", point.date),
                        y: .value(valueName, point.assetAmount)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [themeColor.opacity(0.13), themeColor.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("日付", point.date),
                        y: .value(valueName, point.assetAmount)
                    )
                    .foregroundStyle(themeColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)

                    if let size = pointSymbolSize {
                        PointMark(
                            x: .value("日付", point.date),
                            y: .value(valueName, point.assetAmount)
                        )
                        .foregroundStyle(themeColor)
                        .symbolSize(size)
                    }
                }

                if let sel = selected {
                    RuleMark(x: .value("選択日", sel.date))
                        .foregroundStyle(Color.black.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("日付", sel.date),
                        y: .value(valueName, sel.assetAmount)
                    )
                    .foregroundStyle(themeColor)
                    .symbolSize(55)
                    .annotation(
                        position: .top,
                        alignment: Alignment(horizontal: tooltipAlignment, vertical: .center),
                        spacing: 6
                    ) {
                        VStack(alignment: .center, spacing: 2) {
                            Text(formatChartDate(sel.date))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.52))
                            Text(formatAnalysisAmount(sel.assetAmount))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.82))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.black.opacity(0.09), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatAxisLabel(date))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.black.opacity(0.38))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(shortAmountLabel(v))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.black.opacity(0.38))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let plotFrame = geo[proxy.plotAreaFrame]
                                    let relX = value.location.x - plotFrame.origin.x
                                    if let date = proxy.value(atX: relX, as: Date.self) {
                                        let nearest = nearestPoint(to: date)
                                        // 同じ日付なら更新しない・アニメーションも無効にして処理を軽くする
                                        if selectedPoint?.date != nearest?.date {
                                            // ツールチップがカード左右端からはみ出さないよう、選択点の
                                            // 実際のプロット内X座標（タッチ位置ではなく点そのものの位置）を
                                            // 基準にアラインメントを決める。
                                            let pointX = nearest.flatMap { proxy.position(forX: $0.date) } ?? relX
                                            let alignment = tooltipAlignment(forPointX: pointX, plotWidth: plotFrame.width)
                                            var t = Transaction()
                                            t.disablesAnimations = true
                                            withTransaction(t) {
                                                selectedPoint = nearest
                                                tooltipAlignment = alignment
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in selectedPoint = nil }
                        )
                }
            }
            .onChange(of: points) { _, _ in
                selectedPoint = nil
                tooltipAlignment = .center
            }
            .frame(height: 150)
        }
    }
}
