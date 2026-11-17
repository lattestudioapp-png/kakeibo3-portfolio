import SwiftUI

// MARK: - グラフ設定（資産推移グラフの細かさ）

struct AssetGraphSettingView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AssetGraphSettings.storageKey)
    private var maxPoints: Int = AssetGraphSettings.defaultValue

    @State private var customText: String = ""
    @FocusState private var isCustomFieldFocused: Bool

    private var isPresetSelected: Bool {
        AssetGraphSettings.presets.contains(maxPoints)
    }

    private var customIntValue: Int? { Int(customText) }

    private var isCustomValid: Bool {
        guard let v = customIntValue else { return false }
        return (AssetGraphSettings.minCustom...AssetGraphSettings.maxCustom).contains(v)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("点数が多いほど細かく表示されますが、長期間では少し重くなる場合があります。")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        presetRow(value: 30, label: "少なめ")
                        Divider().padding(.leading, 16)
                        presetRow(value: 60, label: "標準")
                        Divider().padding(.leading, 16)
                        presetRow(value: 100, label: "多め")
                        Divider().padding(.leading, 16)
                        customRow
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("資産推移グラフの細かさ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(AppColors.main)
                }
            }
            .onAppear {
                if !isPresetSelected { customText = String(maxPoints) }
            }
        }
    }

    // MARK: - プリセット行

    private func presetRow(value: Int, label: String) -> some View {
        Button {
            isCustomFieldFocused = false
            maxPoints = value
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Text("\(value)点")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                Spacer()
                if maxPoints == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.main)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - カスタム行

    private var customRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("カスタム")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Text("\(AssetGraphSettings.minCustom)〜\(AssetGraphSettings.maxCustom)点の範囲で指定")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                Spacer()
                if !isPresetSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.main)
                }
            }

            HStack(spacing: 10) {
                TextField("例：80", text: $customText)
                    .keyboardType(.numberPad)
                    .focused($isCustomFieldFocused)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                    .padding(.horizontal, 12)
                    .frame(width: 100, height: 36)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: customText) { _, newValue in
                        let filtered = newValue.filter(\.isNumber)
                        if filtered != newValue { customText = filtered }
                    }

                Text("点")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.6))

                Spacer()

                Button("適用") {
                    guard let v = customIntValue else { return }
                    maxPoints = AssetGraphSettings.clamped(v)
                    customText = String(maxPoints)
                    isCustomFieldFocused = false
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isCustomValid ? AppColors.main : Color.gray.opacity(0.4))
                .disabled(!isCustomValid)
            }

            if !customText.isEmpty && !isCustomValid {
                Text("\(AssetGraphSettings.minCustom)〜\(AssetGraphSettings.maxCustom)の範囲で入力してください")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
