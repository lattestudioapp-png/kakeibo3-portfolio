import SwiftUI

enum AnalysisSegmentType: String, CaseIterable {
    case asset = "資産"
    case payment = "決済"
    case expense = "支出"
    case income = "収入"
}

// カレンダーから分析Viewへのジャンプ要求を運ぶ値型
struct AnalysisJumpTarget: Equatable {
    let segment: AnalysisSegmentType
    let date: Date
}
