import SwiftUI
import Combine

// MARK: - 金額入力エリア

struct AmountInputAreaView: View {
    @Binding var amountText: String
    @Binding var isCalculatorKeyboardPresented: Bool
    var focusedField: FocusState<InputFocusedField?>.Binding

    let layout: InputFormLayout

    @State private var showCopiedBadge: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            Text("金額")
                .font(layout.rowTitleFont)
                .foregroundStyle(Color.black)

            Spacer()

            HStack(spacing: 1) {
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: layout.amountFontSize, weight: layout.amountFontWeight))
                    .monospacedDigit()
                    .foregroundStyle(amountText.isEmpty ? Color.gray.opacity(0.35) : Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)

                if isCalculatorKeyboardPresented {
                    BlinkingCursorView(height: layout.amountFontSize * 1.1)
                }
            }
            .frame(maxWidth: layout.amountInputMaxWidth, alignment: .trailing)
            .overlay(alignment: .topTrailing) {
                if showCopiedBadge {
                    Text("コピー")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .offset(y: -18)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            Text("円")
                .font(layout.rowTitleFont)
                .foregroundStyle(Color.gray)
        }
        .padding(.horizontal, layout.rowHorizontalPadding)
        .frame(height: layout.amountRowHeight)
        .background(layout.rowBackgroundColor)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCalculatorKeyboardPresented {
                // キーボード表示中のタップ → クリップボードにコピー
                let text = amountText.isEmpty ? "0" : amountText
                UIPasteboard.general.string = text
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeOut(duration: 0.15)) { showCopiedBadge = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeIn(duration: 0.2)) { showCopiedBadge = false }
                }
                return
            }
            focusedField.wrappedValue = nil
            DispatchQueue.main.async {
                isCalculatorKeyboardPresented = true
            }
        }
        .overlay(alignment: .top) {
            ThinBorderView(layout: layout)
        }
        .overlay(alignment: .bottom) {
            ThinBorderView(layout: layout)
        }
    }
}
