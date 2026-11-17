import SwiftUI
import UIKit

// sheet / fullScreenCover / NavigationStack 内のキーボードコンテナ。
//
// sheet内ではGeometryReader / SafeArea の高さ基準が通常画面と異なるため、
// AppLayout の sheet用定数で位置・高さを個別調整する。
// 通常画面は NormalAmountKeyboardContainer を使う。
//
// 調整できる定数（AppLayout）:
//   sheetKeyboardBottomPadding  … キーボード下部の余白
//   sheetKeyboardTopPadding     … キーボード上部の余白
//   sheetKeyboardBottomOffset   … キーボード全体の縦オフセット（正 = 下へ）
struct SheetAmountKeyboardContainer: View {
    @Binding var amountText: String
    @Binding var isPresented: Bool

    var body: some View {
        CalculatorKeyboardView(amountText: $amountText, isPresented: $isPresented)
            .padding(.top, AppLayout.sheetKeyboardTopPadding)
            .padding(.bottom, AppLayout.sheetKeyboardBottomPadding)
            .offset(y: AppLayout.sheetKeyboardBottomOffset)
            .background(alignment: .bottom) {
                Color(UIColor.systemGray6)
                    .frame(height: AppLayout.sheetKeyboardBottomPadding + 34)
                    .ignoresSafeArea(edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
            .zIndex(100)
    }
}
