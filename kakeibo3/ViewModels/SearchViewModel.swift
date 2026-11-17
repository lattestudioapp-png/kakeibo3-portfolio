import Foundation
import Combine

// MARK: - 検索種別

enum SearchTransactionType: Hashable {
    case all, expense, income
}

// MARK: - 検索画面用ViewModel
//
// allItems: IncomeData / ExpenseData を変換・ソートした全件キャッシュ。
//           SwiftData のデータが変わった時だけ rebuildAllItems() で再構築。
// filteredItems: allItems にフィルターを適用した結果。body からは読むだけ。
// フィルター状態が変わると Combine が 80ms デバウンス後に applyFilters() を自動呼び出し。

final class SearchViewModel: ObservableObject {

    // MARK: - デフォルト期間（直近1年・パフォーマンスのため全件を初期表示しない）

    static func defaultStartDate(from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .year, value: -1, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    // MARK: - フィルター状態（View から直接 bind 可能）

    @Published var keyword: String = ""
    @Published var selectedType: SearchTransactionType = .all
    @Published var startDate: Date? = SearchViewModel.defaultStartDate()
    @Published var endDate: Date? = nil
    @Published var selectedCategory: String? = nil
    @Published var selectedPayment: String? = nil
    @Published var selectedReceive: String? = nil

    // MARK: - 検索結果（読み取り専用・body は参照するだけ）

    @Published private(set) var filteredItems: [TransactionListItem] = []
    @Published private(set) var groupedDates: [Date] = []
    @Published private(set) var groupedItems: [Date: [TransactionListItem]] = [:]
    @Published private(set) var incomeTotal: Int = 0
    @Published private(set) var expenseTotal: Int = 0
    @Published private(set) var balanceTotal: Int = 0

    // MARK: - 内部キャッシュ

    private var allItems: [TransactionListItem] = []
    private var cancellables = Set<AnyCancellable>()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "MM月dd日 (E)"
        return f
    }()

    // MARK: - 検索条件があるか（デフォルト期間以外に何か指定されているか）

    var hasActiveFilter: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || startDate != nil
            || endDate != nil
            || selectedCategory != nil
            || selectedPayment != nil
            || selectedReceive != nil
            || selectedType != .all
    }

    // MARK: - Init

    init() {
        // フィルター状態が変わるたびに自動で再適用（80ms デバウンスでキー連打を抑制）
        Publishers.MergeMany(
            $keyword.map { _ in }.eraseToAnyPublisher(),
            $selectedType.map { _ in }.eraseToAnyPublisher(),
            $startDate.map { _ in }.eraseToAnyPublisher(),
            $endDate.map { _ in }.eraseToAnyPublisher(),
            $selectedCategory.map { _ in }.eraseToAnyPublisher(),
            $selectedPayment.map { _ in }.eraseToAnyPublisher(),
            $selectedReceive.map { _ in }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
        .sink { [weak self] in self?.applyFilters() }
        .store(in: &cancellables)
    }

    // MARK: - 全条件リセット

    func resetAllFilters() {
        keyword         = ""
        startDate       = nil
        endDate         = nil
        selectedCategory = nil
        selectedPayment  = nil
        selectedReceive  = nil
        selectedType     = .all
    }

    // MARK: - 種別切り替え

    func setTransactionType(_ type: SearchTransactionType) {
        if type == .income  { selectedPayment = nil }
        if type == .expense { selectedReceive = nil }
        selectedType = type
    }

    // MARK: - データ変換（SwiftData データが変わった時だけ呼ぶ）

    func rebuildAllItems(incomes: [IncomeData], expenses: [ExpenseData]) {
        let incomeItems  = incomes.map   { TransactionListItem.income(from: $0) }
        let expenseItems = expenses.map  { TransactionListItem.expense(from: $0) }
        allItems = (incomeItems + expenseItems).sorted {
            if Calendar.current.isDate($0.date, inSameDayAs: $1.date) {
                return $0.createdAt > $1.createdAt
            }
            return $0.date > $1.date
        }
        applyFilters()
    }

    // MARK: - フィルター適用（allItems を1回走査するだけ・body 外で実行）

    func applyFilters() {
        let kw  = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current

        let result = allItems.filter { item in
            // 種別
            switch selectedType {
            case .expense: if item.kind != .expense { return false }
            case .income:  if item.kind != .income  { return false }
            case .all:     break
            }
            // 開始日
            if let start = startDate,
               item.date < cal.startOfDay(for: start) { return false }
            // 終了日
            if let end = endDate {
                var comps = cal.dateComponents([.year, .month, .day], from: end)
                comps.hour = 23; comps.minute = 59; comps.second = 59
                if let endOfDay = cal.date(from: comps), item.date > endOfDay { return false }
            }
            // カテゴリー
            if let cat = selectedCategory, item.category != cat { return false }
            // 支払い（支出のみ）
            if let pay = selectedPayment, item.kind == .expense, item.method != pay { return false }
            // 受け取り（収入のみ）
            if let rec = selectedReceive, item.kind == .income,  item.method != rec { return false }
            // キーワード
            if !kw.isEmpty {
                let typeLabel: String
                switch item.kind {
                case .income:   typeLabel = "収入"
                case .expense:  typeLabel = "支出"
                case .transfer: typeLabel = "振替"
                }
                let targets = [
                    item.category, item.memo,
                    String(item.amount), item.method,
                    typeLabel,
                    SearchViewModel.dateFormatter.string(from: item.date)
                ]
                if !targets.contains(where: { $0.localizedCaseInsensitiveContains(kw) }) {
                    return false
                }
            }
            return true
        }

        filteredItems = result

        // 合計を1パスで計算（reduce を2回呼ばない）
        var inc = 0, exp = 0
        for item in result {
            switch item.kind {
            case .income:            inc += item.amount
            case .expense:           exp += item.amount
            case .transfer: break
            }
        }
        incomeTotal  = inc
        expenseTotal = exp
        balanceTotal = inc - exp

        // 日付ごとのグループ化（body 側では絶対にやらない・ここで1回だけ計算）
        var grouped: [Date: [TransactionListItem]] = [:]
        for item in result {
            let day = cal.startOfDay(for: item.date)
            grouped[day, default: []].append(item)
        }
        groupedItems = grouped
        groupedDates = grouped.keys.sorted(by: >)
    }
}
