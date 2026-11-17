import SwiftUI

// MARK: - カテゴリー色選択コンポーネント（128色スクロールグリッド）

struct CategoryColorPickerView: View {
    @Binding var selectedColorHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(ColorHexConverter.color(from: selectedColorHex))
                .frame(width: 64, height: 64)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.12), lineWidth: 1)
                )

            Text("色を選択")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.45))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(CategoryColorPalette.colors, id: \.self) { hex in
                        colorCircle(hex: hex)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 20)
    }

    private func colorCircle(hex: String) -> some View {
        let isSelected = CategoryColorPalette.normalize(selectedColorHex) == CategoryColorPalette.normalize(hex)

        return Circle()
            .fill(ColorHexConverter.color(from: hex))
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(
                        isSelected ? Color.black.opacity(0.75) : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .onTapGesture {
                selectedColorHex = hex
            }
    }
}
