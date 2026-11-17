import SwiftUI

// MARK: - お金の管理データ（現金・クレジットカード・銀行口座など）用の色設定行
//
// Cash/CreditCard/DebitCard/ElectronicMoney/Securities/Crypto/PaymentReceive/BankAccountの
// 各編集画面で共通利用する。行自体の見た目は各画面が既に使っている
// 「ラベル + 値 + chevron、横パディング16・高さAppLayout.selectionRowHeight」規約に合わせ、
// パレットとシート構成はCategoryDetailEditView.colorPickerSheet（グラフの色）と完全に揃える
// （CategoryColorPickerViewをそのまま呼び出すだけで、新しいパレット・選択UIは作らない）。

struct MoneyItemColorRow: View {
    @Binding var colorHex: String
    @State private var isPresented = false

    private let swatchSize: CGFloat = AppLayout.categoryColorPreviewSize
    private let swatchCornerRadius: CGFloat = 6

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text("グラフの色")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                RoundedRectangle(cornerRadius: swatchCornerRadius)
                    .fill(ColorHexConverter.color(from: colorHex))
                    .frame(width: swatchSize, height: swatchSize)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            colorPickerSheet
        }
    }

    // MARK: - カラーピッカーシート（CategoryDetailEditView.colorPickerSheetと同一構成）

    private var colorPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("グラフの色")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Button("完了") {
                    isPresented = false
                }
                .font(AppFonts.button)
                .foregroundStyle(AppColors.main)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            CategoryColorPickerView(selectedColorHex: $colorHex)
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.fraction(0.72)])
        .presentationDragIndicator(.visible)
    }
}
