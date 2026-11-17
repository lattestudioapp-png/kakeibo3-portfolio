import SwiftUI

// MARK: - 設定行の右側に置く「値 + 上下シェブロン」ラベル（Menuのlabelとして使う）
//
// 元はCreditCardEditView内のprivate struct。固定費/定期収入の
// 「金融機関が休業日の場合」など、同じ見た目のMenu行を他画面でも使うために共通化した。

struct CardRowValueLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(AppFonts.rowTitle)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .frame(height: 32)
        .contentShape(Rectangle())
    }
}
