import SwiftUI

struct CustomPeriodSettingView: View {
    let initialStartDate: Date
    let initialEndDate: Date
    let onApply: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        initialStartDate: Date,
        initialEndDate: Date,
        onApply: @escaping (Date, Date) -> Void
    ) {
        self.initialStartDate = initialStartDate
        self.initialEndDate = initialEndDate
        self.onApply = onApply
        self._startDate = State(initialValue: initialStartDate)
        self._endDate = State(initialValue: initialEndDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                dateRangeCard
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("期間を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        onApply(startDate, endDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.main)
                }
            }
        }
        .onChange(of: startDate) { _, newValue in
            if newValue > endDate { endDate = newValue }
        }
    }

    private var dateRangeCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("開始日")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)

            Divider().padding(.horizontal, 16)

            HStack {
                Text("終了日")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.line, lineWidth: 1)
        )
    }
}
