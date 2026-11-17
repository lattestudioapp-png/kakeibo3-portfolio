import SwiftUI

// MARK: - 破壊的操作の確認ダイアログ（帳簿リセット・帳簿削除などで共通利用）
//
// 標準の.confirmationDialog/.alertでは「ボタンを上下2段・区切り線のみ・背景無し」という
// デザインを細かく制御できないため、CalendarDatePickerModalViewと同じ
// 「白いカード + Divider区切り」のハウススタイルでこのアプリ専用に用意する。
// キャンセル・破壊的操作のどちらも見た目はここに集約し、呼び出し側ごとに
// バラバラなデザインにならないようにする。

struct DestructiveConfirmationDialogView: View {
    let title: String
    /// 複数行に分けたい場合は呼び出し側で改行(\n)を含めて渡す。
    let message: String
    let destructiveLabel: String
    let onCancel: () -> Void
    let onDestructive: () -> Void

    private let cardCornerRadius: CGFloat = 24
    private let cardMaxWidth: CGFloat = 340
    private let cardHorizontalPadding: CGFloat = 32
    private let buttonHeight: CGFloat = 52

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider()

                Button(action: onCancel) {
                    Text("キャンセル")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.main)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(.plain)

                Divider()

                Button(action: onDestructive) {
                    Text(destructiveLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(.plain)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .frame(maxWidth: cardMaxWidth)
            .padding(.horizontal, cardHorizontalPadding)
        }
    }
}
