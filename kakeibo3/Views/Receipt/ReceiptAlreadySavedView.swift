import SwiftUI

// MARK: - 二重保存防止・保存エラー時の案内画面

struct ReceiptAlreadySavedView: View {
    var message: String = "このレシートは保存済みです"
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.gray.opacity(0.5))

            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onClose) {
                Text("閉じる")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColors.main)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.sheetBackground)
    }
}
