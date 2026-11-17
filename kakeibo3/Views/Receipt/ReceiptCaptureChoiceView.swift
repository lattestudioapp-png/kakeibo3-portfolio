import SwiftUI

// MARK: - レシート撮影フロー最初の画面（カメラ撮影 / 写真ライブラリから選択）

struct ReceiptCaptureChoiceView: View {
    let onTakePhoto: () -> Void
    let onSelectLibrary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.main)

            VStack(spacing: 8) {
                Text("レシートを撮影してください")
                    .font(.system(size: 17, weight: .semibold))
                Text("レシート全体が枠に収まるように撮影すると\n読み取り精度が上がります")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 10) {
                Button(action: onTakePhoto) {
                    Label("カメラで撮影", systemImage: "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColors.main)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onSelectLibrary) {
                    Label("写真ライブラリから選択", systemImage: "photo.on.rectangle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.sheetBackground)
    }
}
