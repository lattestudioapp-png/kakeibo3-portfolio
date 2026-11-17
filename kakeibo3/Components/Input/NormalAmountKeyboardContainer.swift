import SwiftUI
import UIKit

// 通常画面（TabView内のInputViewなど）用キーボードコンテナ。
//
// InputView で確立された見た目を正解とし、他の通常画面でも同じ表示を再現する。
// BottomNavigationBar 分だけキーボードを上にずらし、背景色で隙間を埋める。
// sheet画面は SheetAmountKeyboardContainer を使う。
struct NormalAmountKeyboardContainer: View {
    @Binding var amountText: String
    @Binding var isPresented: Bool

    var body: some View {
        CalculatorKeyboardView(amountText: $amountText, isPresented: $isPresented)
            .padding(.bottom, AppLayout.normalKeyboardBottomPadding)
            .background(alignment: .bottom) {
                Color(UIColor.systemGray6)
                    .frame(height: AppLayout.normalKeyboardBottomPadding)
                    .ignoresSafeArea(edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
            .zIndex(100)
    }
}
