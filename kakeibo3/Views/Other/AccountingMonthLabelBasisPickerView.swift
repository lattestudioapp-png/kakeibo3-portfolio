import SwiftUI

// MARK: - 年月表示の基準ピッカー

struct AccountingMonthLabelBasisPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AccountingMonthLabelBasis.storageKey)
    private var storedLabelBasis: String = AccountingMonthLabelBasis.defaultValue.rawValue

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountingMonthLabelBasis.allCases, id: \.rawValue) { option in
                    Button {
                        storedLabelBasis = option.rawValue
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option.rawValue == storedLabelBasis {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.main)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("年月表示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(AppColors.main)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
