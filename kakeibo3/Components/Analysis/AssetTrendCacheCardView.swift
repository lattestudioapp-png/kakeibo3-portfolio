import SwiftUI

// MARK: - 資産推移グラフカード（総資産・キャッシュ方式）
//
// 分析Viewを開くたびに元データから再計算すると10年/20年分のデータで重くなるため、
// 「更新」ボタンを押した時だけ AssetGraphCacheService で計算し、結果を
// AssetGraphCacheData に保存する。分析Viewを開いただけでは一切再計算しない。
//
// 計算中・成功・失敗・タイムアウトのすべてで確実に状態が戻るよう、
// 単一のRebuildState（enum）で管理する（bool一つだけだと「戻し忘れ」が起きやすいため）。

struct AssetTrendCacheCardView: View {
    @StateObject private var cacheDataObserver = AssetGraphCacheDataSync.observer()
    private var caches: [AssetGraphCacheData] { cacheDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(AssetGraphSettings.storageKey)
    private var storedMaxPoints: Int = AssetGraphSettings.defaultValue
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    private enum RebuildState: Equatable {
        case idle
        case calculating
        case failed(String)
        case timedOut
    }

    @State private var state: RebuildState = .idle

    // キャッシュが無い（＝まだ一度もグラフを作成していない）時に、元データ側に
    // グラフを作れるだけの量があるかどうか。「データ不足」と「グラフ作成ボタンを
    // 押してください」を区別するために使う。日別残高の展開は行わない軽量チェックのため
    // （AssetGraphCacheService.hasEnoughDataForTotalAssetsChart参照）、
    // 画面表示のたびに呼んでも問題ない。
    @State private var hasEnoughRawData = false

    private var maxPoints: Int {
        AssetGraphSettings.clamped(storedMaxPoints)
    }

    private var cache: AssetGraphCacheData? {
        caches.first { $0.bookId == currentBookId }
    }

    private var chartPoints: [AssetChartPoint] {
        guard let cache else { return [] }
        return cache.points.map { AssetChartPoint(id: $0.date, date: $0.date, assetAmount: $0.value) }
    }

    /// 線グラフとして成立する（2点以上ある）かどうか。取引件数ではなく、
    /// キャッシュに保存された最終的なグラフ点数で判定する。
    private var hasEnoughPointsToChart: Bool {
        (cache?.points.count ?? 0) >= 2
    }

    private static let updatedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/M/d HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("資産推移")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.65))
                Spacer()
                updateButton
            }

            statusText

            contentArea
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
        .task(id: currentBookId) {
            await refreshHasEnoughRawData()
        }
    }

    // MARK: - 元データの有無チェック（軽量。日別残高の展開は行わない）

    private func refreshHasEnoughRawData() async {
        guard let bookId = currentBookId else {
            hasEnoughRawData = false
            return
        }
        let result = await Task.detached(priority: .utility) { () -> Bool in
            AssetGraphCacheService.hasEnoughDataForTotalAssetsChart(bookId: bookId)
        }.value
        hasEnoughRawData = result
    }

    // [DEBUG] 「データ不足」/「グラフ作成ボタンを押してください」のどちらを出したかとその判定条件
    private func logEmptyStateCondition() {
        TimingDebugLog.write(
            "[AssetDebug] empty-state shown: cache==nil=\(cache == nil) "
            + "cache.points.count=\(cache?.points.count ?? -1) hasEnoughPointsToChart=\(hasEnoughPointsToChart) "
            + "hasEnoughRawData=\(hasEnoughRawData) -> text=\"\(hasEnoughRawData ? "グラフ作成ボタンを押してください" : "データ不足")\""
        )
    }

    // MARK: - ステータス表示（前回更新日時 / 未作成 / 計算中 / 失敗 / タイムアウト）

    @ViewBuilder
    private var statusText: some View {
        switch state {
        case .calculating:
            Text("計算中...")
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.4))
        case .failed:
            Text("グラフ作成に失敗しました")
                .font(.system(size: 11))
                .foregroundStyle(Color.red.opacity(0.7))
        case .timedOut:
            Text("計算に時間がかかっています")
                .font(.system(size: 11))
                .foregroundStyle(Color.red.opacity(0.7))
        case .idle:
            if let cache, hasEnoughPointsToChart {
                VStack(alignment: .leading, spacing: 2) {
                    Text("前回更新：\(Self.updatedAtFormatter.string(from: cache.updatedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.4))
                    // 設定変更を検知しても自動では再計算しない。次に「更新」を押した時に
                    // 反映されることを軽く伝えるだけの表示。
                    if cache.maxPointsUsed != maxPoints {
                        Text("グラフ設定が変更されています。更新すると反映されます")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.main.opacity(0.8))
                    }
                }
            } else {
                // データ不足・未作成の場合のメッセージは contentArea 側にまとめて表示し、
                // ここでは二重にメッセージを出さない
                EmptyView()
            }
        }
    }

    // MARK: - グラフ / 空状態 / 計算中 / 失敗 / タイムアウト

    @ViewBuilder
    private var contentArea: some View {
        switch state {
        case .calculating:
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
        case .failed(let message):
            errorContent(message: message)
        case .timedOut:
            errorContent(message: "データ量を減らすか、もう一度お試しください。")
        case .idle:
            if let cache, hasEnoughPointsToChart {
                AssetTrendChartBody(
                    points: chartPoints,
                    granularity: AssetTrendGranularity(storageValue: cache.granularityUsed),
                    valueName: "総資産"
                )
            } else {
                VStack {
                    Spacer()
                    Text(hasEnoughRawData ? "グラフ作成ボタンを押してください" : "データ不足")
                        .font(AppFonts.body)
                        .foregroundStyle(Color.black.opacity(0.35))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .onAppear { logEmptyStateCondition() }
            }
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(message)
                .font(AppFonts.body)
                .foregroundStyle(Color.black.opacity(0.4))
                .multilineTextAlignment(.center)
            Button("再試行") { rebuild(caller: "retryButton") }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.main)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .frame(height: 150)
    }

    // MARK: - 更新ボタン

    private var updateButton: some View {
        Button {
            rebuild(caller: cache == nil ? "createButton" : "updateButton")
        } label: {
            HStack(spacing: 4) {
                if state == .calculating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(buttonLabel)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AppColors.main)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppColors.main.opacity(0.1)))
            .overlay(Capsule().stroke(AppColors.main.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(state == .calculating)
    }

    private var buttonLabel: String {
        switch state {
        case .failed, .timedOut:
            return "再試行"
        case .calculating, .idle:
            return cache == nil ? "グラフを作成" : "更新"
        }
    }

    // MARK: - 再計算
    //
    // 成功・失敗・タイムアウトのいずれでも必ず state を .calculating から抜ける
    // （do/catchの全パスで明示的に代入するため、戻し忘れが起きない）。

    private func rebuild(caller: String) {
        guard state != .calculating else { return }
        guard let bookId = currentBookId else { return }
        TimingDebugLog.write("AssetGraphCache rebuild called by: \(caller)")
        state = .calculating
        let points = maxPoints
        Task {
            do {
                try await AssetGraphCacheService.rebuildTotalAssetsCache(bookId: bookId, maxPoints: points)
                await MainActor.run { state = .idle }
            } catch AssetGraphError.timeout {
                await MainActor.run { state = .timedOut }
            } catch {
                await MainActor.run { state = .failed(error.localizedDescription) }
            }
        }
    }
}
