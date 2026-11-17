import Foundation

// MARK: - 性能測定モード
//
// カレンダー・分析・検索・CSV・バックアップ・スナップショット生成など、
// データ量が増えると重くなりうる処理の実行時間をまとめて計測し、コンソールへ出力する。
// PerformanceTestDataGenerator で作った20年分の負荷データに対して実行することを想定している。
//
// 計測対象のうち AnalysisViewModel / SearchViewModel は実際にユーザーが画面を開いた時と
// 同じ処理経路（ViewModelのrebuild系メソッド）をそのまま呼ぶことで、体感速度に近い数値にしている。
// 一方、開いたことのない画面のViewModelをここでインスタンス化して使うため、実際の描画コスト
// （SwiftUIのbody評価・レイアウト）は含まれない＝あくまで「データ層＋集計ロジック」の所要時間である点に注意。

enum PerformanceBenchmark {

    struct BenchmarkResult: Identifiable {
        let id = UUID()
        let label: String
        let milliseconds: Double
        let detail: String?
    }

    // MARK: - まとめて実行

    // 呼び出し側のUIをできるだけブロックしないよう、Task.detached等バックグラウンドから
    // 渡されたcontextで実行することを想定している（TestDataViewのrunInBackgroundと同じ流儀）。
    // ただしAnalysisViewModel/SearchViewModelの計算自体はメインスレッドと同じ処理内容のため、
    // 数値は実際にその画面を開いた時の体感に近い。
    static func runAll() -> [BenchmarkResult] {
        print("========================================")
        print("性能測定モード 開始")
        print("========================================")

        var results: [BenchmarkResult] = []

        results.append(measureStartup())
        results.append(measureCalendarDisplay())
        results.append(measureAnalysisDisplay())
        results.append(measureAssetTrend())
        results.append(measureSearch())
        results.append(measureCSVExport())
        results.append(measureBackup())
        results.append(measureSnapshotGeneration())

        print("----------------------------------------")
        print("計測結果まとめ")
        for r in results {
            let detailText = r.detail.map { " (\($0))" } ?? ""
            let paddedLabel = r.label.padding(toLength: 16, withPad: "　", startingAt: 0)
            let msText = String(format: "%8.2f ms", r.milliseconds)
            print("  \(paddedLabel) \(msText)\(detailText)")
        }
        print("========================================")
        print("性能測定モード 終了")
        print("========================================")

        return results
    }

    // MARK: - 1. 起動時間
    //
    // Kakeibo3App.onAppearと同じ処理経路（バックフィル＋ロック解除）を計測する。
    // スナップショットが既に存在する場合、backfillIfNeededは即座に返るため、
    // 2回目以降の計測では「通常起動時のコスト」に近い小さい値になるのが正しい挙動。

    private static func measureStartup() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()
        SnapshotManager.backfillIfNeeded()
        AnalysisSnapshotManager.backfillIfNeeded()
        DowngradeLockService.unlockAll()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("起動時間", ms: ms)
        return BenchmarkResult(label: "起動時間", milliseconds: ms, detail: "backfill+ロック解除")
    }

    // MARK: - 2. カレンダー表示時間
    //
    // 今月のグリッド42日分のDailySnapshotと全期間のMonthlySnapshotを取得し、
    // CalendarTransactionServiceで月次集計を組み立てるまでを計測する（実画面と同じ処理経路）。

    private static func measureCalendarDisplay() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()
        let service = CalendarTransactionService()
        let selectedDate = Date()

        var dailyCount = 0
        if let range = service.gridDateRange(selectedDate: selectedDate) {
            let rangeStart = range.start, rangeEnd = range.end
            let dailySnapshots = DailySnapshotSync.fetchAll().filter { $0.date >= rangeStart && $0.date < rangeEnd }
            let allMonthly = MonthlySnapshotSync.fetchAll()
            dailyCount = dailySnapshots.count
            _ = service.monthAggregate(selectedDate: selectedDate, dailySnapshots: dailySnapshots, allMonthlySnapshots: allMonthly)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("カレンダー表示時間", ms: ms)
        return BenchmarkResult(label: "カレンダー表示時間", milliseconds: ms, detail: "グリッド\(dailyCount)日分")
    }

    // MARK: - 3. 分析表示時間
    //
    // 分析タブを開いた直後の初期状態（期間=今月）を想定し、支出・収入タブの再集計を計測する。

    private static func measureAnalysisDisplay() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()

        let bankAccounts = BankAccountDataSync.fetchAll()
        let paymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let allExpenses = ExpenseDataSync.fetchAll()
        let allIncomes = IncomeDataSync.fetchAll()
        let allTransfers = TransferDataSync.fetchAll()
        let categories = CategoryDataSync.fetchAll()
        let allAnalysisMonthlySnapshots = AnalysisMonthlySnapshotSync.fetchAll()

        let visibleExpenses = DowngradeLockService.visibleExpenses(allExpenses, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        let visibleIncomes = DowngradeLockService.visibleIncomes(allIncomes, bankAccounts: bankAccounts, paymentMethods: paymentMethods)

        let dateRange = AnalysisDateRangeCalculator.current(for: .month, referenceDate: Date())
        let prevDateRange = AnalysisDateRangeCalculator.previous(for: .month, referenceDate: Date())

        let vm = AnalysisViewModel()
        vm.rebuildExpenseIncome(
            allExpenses: visibleExpenses, allIncomes: visibleIncomes, allTransfers: allTransfers,
            categories: categories, paymentMethods: paymentMethods, bankAccounts: bankAccounts,
            dateRange: dateRange, prevDateRange: prevDateRange, periodType: .month,
            monthlySnapshots: allAnalysisMonthlySnapshots
        )

        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("分析表示時間", ms: ms)
        return BenchmarkResult(label: "分析表示時間", milliseconds: ms, detail: "支出\(allExpenses.count)件/収入\(allIncomes.count)件から今月分集計")
    }

    // MARK: - 4. 資産推移生成時間
    //
    // 資産推移グラフの「更新」ボタン押下時（AssetGraphCacheService.rebuildTotalAssetsCache）と
    // 同じ計算を行い、全期間分の元データからグラフ用データを作る最重量ケースを計測する。
    // このグラフは分析Viewを開いただけでは再計算されないため、通常の分析表示時間には含めない。

    private static func measureAssetTrend() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()

        let bankAccounts = BankAccountDataSync.fetchAll()
        let paymentMethods = PaymentMethodSettingDataSync.fetchAll()
        let allExpenses = ExpenseDataSync.fetchAll()
        let allIncomes = IncomeDataSync.fetchAll()
        let allTransfers = TransferDataSync.fetchAll()

        let visibleExpenses = DowngradeLockService.assetTotalExpenses(allExpenses, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        let visibleIncomes = DowngradeLockService.assetTotalIncomes(allIncomes, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
        let creditCardNames = Set(paymentMethods.filter { $0.type == PaymentMethodType.creditCard.rawValue }.map(\.methodName))
        let timing = CreditCardAssetReflectionTiming(
            rawValue: UserDefaults.standard.string(forKey: CreditCardAssetReflectionTiming.storageKey) ?? ""
        ) ?? .usageDate

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let earliestDate = (visibleExpenses.map(\.date) + visibleIncomes.map(\.date) + allTransfers.map(\.date))
            .min().map { cal.startOfDay(for: $0) } ?? today

        let calc = BankAccountBalanceCalculator(
            bankAccounts: bankAccounts, allIncomeData: visibleIncomes, allExpenseData: visibleExpenses,
            allTransferData: allTransfers, creditCardNames: creditCardNames, assetReflectionTiming: timing
        )
        let raw = calc.dailyAssetPoints(from: earliestDate, to: today)
        let dailyPoints = raw.map { AssetChartPoint(id: $0.date, date: $0.date, assetAmount: $0.value) }
        let storedMaxPoints = UserDefaults.standard.object(forKey: AssetGraphSettings.storageKey) as? Int ?? AssetGraphSettings.defaultValue
        _ = AssetGraphPointReducer.reduce(dailyPoints: dailyPoints, maxPoints: AssetGraphSettings.clamped(storedMaxPoints))

        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("資産推移生成時間", ms: ms)
        return BenchmarkResult(label: "資産推移生成時間", milliseconds: ms, detail: "全期間・支出\(visibleExpenses.count)件/収入\(visibleIncomes.count)件から生成")
    }

    // MARK: - 5. 検索時間
    //
    // 検索画面を開いた直後（全件をTransactionListItemへ変換）から、
    // キーワードを1つ入力して絞り込むまでを計測する。

    private static func measureSearch() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()

        let incomes = IncomeDataSync.fetchAll()
        let expenses = ExpenseDataSync.fetchAll()

        let vm = SearchViewModel()
        vm.rebuildAllItems(incomes: incomes, expenses: expenses)
        vm.keyword = "食費"
        vm.applyFilters()

        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("検索時間", ms: ms)
        return BenchmarkResult(label: "検索時間", milliseconds: ms, detail: "全\(incomes.count + expenses.count)件→\(vm.filteredItems.count)件に絞り込み")
    }

    // MARK: - 6. CSV時間

    private static func measureCSVExport() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()
        var detail = "失敗"
        do {
            let url = try CSVExportService.exportCSV(
                bookId: nil, encoding: .utf8, target: .all, startDate: nil, endDate: nil
            )
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            detail = "\((size ?? 0) / 1024)KB"
        } catch {
            detail = "失敗: \(error.localizedDescription)"
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("CSV出力時間", ms: ms)
        return BenchmarkResult(label: "CSV出力時間", milliseconds: ms, detail: detail)
    }

    // MARK: - 7. バックアップ時間

    private static func measureBackup() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()
        var detail = "失敗"
        do {
            guard let bookId = BookResolver.mainBookId() else {
                throw BackupError.bookmarkResolutionFailed
            }
            let url = try BackupManager.shared.createBackup(bookId: bookId)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            detail = "\((size ?? 0) / 1024)KB"
        } catch {
            detail = "失敗: \(error.localizedDescription)"
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log("バックアップ時間", ms: ms)
        return BenchmarkResult(label: "バックアップ時間", milliseconds: ms, detail: detail)
    }

    // MARK: - 8. Snapshot生成時間
    //
    // 既存スナップショットを全削除してから作り直す、最も重いケース
    // （バックアップ復元・ロック状態の一括変更などと同じ処理経路）を計測する。

    private static func measureSnapshotGeneration() -> BenchmarkResult {
        let start = CFAbsoluteTimeGetCurrent()
        SnapshotManager.rebuildAll()
        AnalysisSnapshotManager.rebuildAll()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let dailyCount = DailySnapshotSync.count()
        let monthlyCount = MonthlySnapshotSync.count()
        log("Snapshot生成時間", ms: ms)
        return BenchmarkResult(label: "Snapshot生成時間", milliseconds: ms, detail: "日次\(dailyCount)件/月次\(monthlyCount)件を再構築")
    }

    // MARK: - ログ出力

    private static func log(_ label: String, ms: Double) {
        print(String(format: "[PerformanceBenchmark] %@: %.2f ms", label, ms))
    }
}
