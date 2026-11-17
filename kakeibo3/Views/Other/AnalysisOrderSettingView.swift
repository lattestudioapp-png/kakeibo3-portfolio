import SwiftUI

struct AnalysisOrderSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("analysisSegmentOrder") private var storedOrder: String = ""

    @State private var orderedItems: [AnalysisSegmentType] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedItems, id: \.self) { item in
                    Text(item.rawValue)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                        .listRowBackground(Color.white)
                }
                .onMove { from, to in
                    orderedItems.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("分析表示順")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        storedOrder = orderedItems.map(\.rawValue).joined(separator: ",")
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.main)
                }
            }
        }
        .onAppear {
            orderedItems = parseStoredOrder()
        }
    }

    private func parseStoredOrder() -> [AnalysisSegmentType] {
        let rawValues = storedOrder.split(separator: ",").map(String.init)
        let parsed = rawValues.compactMap { AnalysisSegmentType(rawValue: $0) }
        let missing = AnalysisSegmentType.allCases.filter { !parsed.contains($0) }
        return parsed.isEmpty ? AnalysisSegmentType.allCases : parsed + missing
    }
}
