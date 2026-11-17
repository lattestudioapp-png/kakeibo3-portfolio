import SwiftUI

// MARK: - 資産推移グラフカード（銀行口座 / その他残高管理項目のライブ計算用）
//
// 呼び出し側（ViewModel）が用意した「隙間の無い全履歴ぶんの日次データ」を受け取り、
// その他 > 分析 > グラフ設定 の最大表示点数に応じて AssetGraphPointReducer で
// 表示粒度・間引きを決め、実際の描画は共通の AssetTrendChartBody に委譲する。
//
// 総資産グラフ（分析 > 資産）は、開くたびに再計算しないようキャッシュ方式
// （AssetTrendCacheCardView）に置き換え済み。こちらは口座別・支払い方法別の
// 残高推移（AssetDetailView）でのみ使うライブ計算版。

struct AssetTrendChartView: View {
    let title: String
    /// 昇順（古い→新しい）の全履歴ぶんの日次推移データ（取引が無い日も前日の値を
    /// 引き継いだ、隙間のない配列）。全取引の再集計はせず、呼び出し側
    /// （AssetDetailViewModel）が作成済みのものを渡す。
    let dailyPoints: [AssetChartPoint]
    /// 実際に記録が存在する最古の日付（現状このView内では未使用。呼び出し側の互換のため保持）。
    let firstRecordedDate: Date?
    /// 選択月の範囲（現状このView内では未使用。呼び出し側の互換のため保持）。
    let dateRange: AnalysisDateRange
    /// Chart内部の値ラベル（画面には表示されないが VoiceOver 等で使用）
    var valueName: String = "資産"

    // その他 > 分析 > グラフ設定 で変更できる最大表示点数
    @AppStorage(AssetGraphSettings.storageKey)
    private var storedMaxPoints: Int = AssetGraphSettings.defaultValue

    private var maxPoints: Int {
        AssetGraphSettings.clamped(storedMaxPoints)
    }

    /// 最大表示点数設定に応じて、自動で選ばれた粒度・点列。
    private var reduction: AssetGraphReduction {
        AssetGraphPointReducer.reduce(dailyPoints: dailyPoints, maxPoints: maxPoints)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFonts.sectionTitle)
                .foregroundStyle(Color.black.opacity(0.65))

            AssetTrendChartBody(
                points: reduction.points,
                granularity: reduction.granularity,
                valueName: valueName
            )
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }
}
