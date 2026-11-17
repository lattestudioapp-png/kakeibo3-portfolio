import SwiftUI

// MARK: - セッションタイムアウト選択画面

struct SessionTimeoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var passcodeManager: PasscodeManager

    var body: some View {
        NavigationStack {
            List {
                ForEach(SessionTimeoutOption.allCases, id: \.self) { option in
                    optionRow(option)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("セッションタイムアウト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
    }

    private func optionRow(_ option: SessionTimeoutOption) -> some View {
        Button {
            passcodeManager.sessionTimeoutOption = option
            dismiss()
        } label: {
            HStack {
                Text(option.displayName)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                if passcodeManager.sessionTimeoutOption == option {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.main)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
