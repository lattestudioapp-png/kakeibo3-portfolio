import SwiftUI

// MARK: - リスト表示色設定画面

struct ListColorSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    @AppStorage(TransactionListColorSettings.expenseRowColorStorageKey)
    private var expenseRowColorRaw: String = TransactionListColorSettings.defaultExpenseRowColor.rawValue
    @AppStorage(TransactionListColorSettings.incomeRowColorStorageKey)
    private var incomeRowColorRaw: String = TransactionListColorSettings.defaultIncomeRowColor.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("支出リスト") {
                    ForEach(TransactionListRowColorOption.allCases, id: \.self) { option in
                        colorRow(
                            option: option,
                            isSelected: expenseRowColorRaw == option.rawValue
                        ) {
                            expenseRowColorRaw = option.rawValue
                        }
                    }
                }
                Section("収入リスト") {
                    ForEach(TransactionListRowColorOption.allCases, id: \.self) { option in
                        colorRow(
                            option: option,
                            isSelected: incomeRowColorRaw == option.rawValue
                        ) {
                            incomeRowColorRaw = option.rawValue
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("リスト表示色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
    }

    private func colorRow(
        option: TransactionListRowColorOption,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .fill(option.color)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                Text(option.displayName)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeManager.mainColor)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
