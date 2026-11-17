import SwiftUI

// MARK: - 「並び替え ↓」表示（一覧上部右側）
//
// CategoryEditView（Views/Input/CategoryEditView.swift）のguideArea右側テキストと
// 文字サイズ・文字色・太さ・位置・余白を完全に一致させたもの。
// モード切り替えやタップ操作は持たず、既存のドラッグハンドルによる並び替えの案内表示のみ。

struct ReorderHintView: View {
    private let fontSize: CGFloat = 15
    private let fontWeight: Font.Weight = .semibold
    private let textColor = Color.gray
    private let textOpacity: Double = 0.90
    private let textXOffset: CGFloat = -10
    private let horizontalPadding: CGFloat = 28
    private let areaHeight: CGFloat = 36

    var body: some View {
        HStack {
            Spacer()
            Text("並び替え ↓")
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(textColor.opacity(textOpacity))
                .offset(x: textXOffset)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: areaHeight)
    }
}
