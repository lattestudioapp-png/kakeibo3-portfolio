import Foundation

enum AnalysisPeriodType: String, CaseIterable {
    case month = "今月"
    case previousMonth = "先月"
    case year = "1年"
    case allTime = "全期間"
    case custom = "カスタム"

    var comparisonLabel: String {
        switch self {
        case .month, .previousMonth: return "前月比"
        case .year: return "前年比"
        case .allTime: return "前期間比"
        case .custom: return "前期間比"
        }
    }

    // 全期間は前期間比を表示しない（前期間が存在しないため）
    var showsPeriodComparison: Bool {
        self != .allTime
    }

    // 全期間は日次平均が意味をなさないため非表示
    var showsDailyAverage: Bool {
        self != .allTime
    }

    func summaryTitle(for category: String) -> String {
        "\(rawValue)の\(category)"
    }
}
