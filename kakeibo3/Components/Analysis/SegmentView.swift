import SwiftUI

struct SegmentView: View {
    @Binding var selectedType: AnalysisSegmentType
    var orderedSegments: [AnalysisSegmentType] = AnalysisSegmentType.allCases
    var width: CGFloat = SegmentBarLayout.standard.width

    private var selectedIndex: Int {
        orderedSegments.firstIndex(of: selectedType) ?? 0
    }

    var body: some View {
        AppSegmentControl(
            items: orderedSegments.map(\.rawValue),
            selectedIndex: selectedIndex,
            onSelect: { index in
                guard index < orderedSegments.count else { return }
                selectedType = orderedSegments[index]
            },
            width: width
        )
    }
}
