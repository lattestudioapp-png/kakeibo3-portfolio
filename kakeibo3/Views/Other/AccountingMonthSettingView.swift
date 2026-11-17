import SwiftUI

// MARK: - 月の開始日設定（会計月の区切り方。カレンダー・予算・分析・グラフ共通）

struct AccountingMonthSettingView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AccountingMonthSettings.startDayStorageKey)
    private var startDay: Int = AccountingMonthSettings.startDayDefaultValue
    @AppStorage(WeekendHolidayAdjustment.storageKey)
    private var storedAdjustment: String = WeekendHolidayAdjustment.defaultValue.rawValue
    @AppStorage(AccountingMonthLabelBasis.storageKey)
    private var storedLabelBasis: String = AccountingMonthLabelBasis.defaultValue.rawValue

    @State private var showsStartDayPicker = false
    @State private var showsAdjustmentPicker = false
    @State private var showsLabelBasisPicker = false

    private var adjustment: WeekendHolidayAdjustment {
        WeekendHolidayAdjustment(rawValue: storedAdjustment) ?? .defaultValue
    }

    private var labelBasis: AccountingMonthLabelBasis {
        AccountingMonthLabelBasis(rawValue: storedLabelBasis) ?? .defaultValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        settingRow(title: "月の開始日", value: "\(startDay)日") {
                            showsStartDayPicker = true
                        }
                        Divider().padding(.leading, 16)
                        settingRow(title: "開始日が土日祝の場合", value: adjustment.displayName) {
                            showsAdjustmentPicker = true
                        }
                        Divider().padding(.leading, 16)
                        settingRow(title: "年月表示", value: labelBasis.displayName) {
                            showsLabelBasisPicker = true
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))

                    Text("「年月表示」は、カレンダーや分析グラフの表示月に反映されます。")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("月の開始日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(AppColors.main)
                }
            }
        }
        .sheet(isPresented: $showsStartDayPicker) { AccountingMonthStartDayPickerView() }
        .sheet(isPresented: $showsAdjustmentPicker) { WeekendHolidayAdjustmentPickerView() }
        .sheet(isPresented: $showsLabelBasisPicker) { AccountingMonthLabelBasisPickerView() }
    }

    private func settingRow(title: String, value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Text(value)
                    .font(AppFonts.body)
                    .foregroundStyle(Color.black.opacity(0.4))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
