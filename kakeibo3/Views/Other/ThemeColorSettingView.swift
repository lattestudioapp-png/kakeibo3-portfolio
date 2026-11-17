import SwiftUI

// MARK: - テーマカラー候補

struct ThemeColorOption: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
}

private let themeColorOptions: [ThemeColorOption] = [
    ThemeColorOption(name: "グリーン",   hex: "#52806E"),
    ThemeColorOption(name: "ブルー",     hex: "#4A90E2"),
    ThemeColorOption(name: "オレンジ",   hex: "#F2994A"),
    ThemeColorOption(name: "ピンク",     hex: "#EB6F92"),
    ThemeColorOption(name: "パープル",   hex: "#9B6FD3"),
    ThemeColorOption(name: "ブラック",   hex: "#333333"),
]

// MARK: - テーマカラー選択画面

struct ThemeColorSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        NavigationStack {
            List {
                ForEach(themeColorOptions) { option in
                    Button {
                        theme.setColor(hex: option.hex)
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(ColorHexConverter.color(from: option.hex))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            Text(option.name)
                                .font(AppFonts.rowTitle)
                                .foregroundStyle(Color.black.opacity(0.8))
                            Spacer()
                            if theme.selectedThemeColorHex == option.hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.mainColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("テーマカラー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
    }
}
