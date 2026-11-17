import SwiftUI

// MARK: - メール送信が使えない端末向けのお問い合わせ先表示（DestructiveConfirmationDialogViewと同じハウススタイル）

struct ContactEmailFallbackView: View {
    let email: String
    let onClose: () -> Void

    @State private var didCopy = false

    private let cardCornerRadius: CGFloat = 24
    private let cardMaxWidth: CGFloat = 340
    private let cardHorizontalPadding: CGFloat = 32
    private let buttonHeight: CGFloat = 52

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("メールを送信できません")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .multilineTextAlignment(.center)
                    Text("この端末にはメールアカウントが設定されていません。\n以下のアドレスへ直接お問い合わせください。")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Text(email)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.main)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider()

                Button {
                    UIPasteboard.general.string = email
                    didCopy = true
                } label: {
                    Text(didCopy ? "コピーしました" : "コピーする")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.main)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(.plain)

                Divider()

                Button(action: onClose) {
                    Text("閉じる")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.black.opacity(0.6))
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
