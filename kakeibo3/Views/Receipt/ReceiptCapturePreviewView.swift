import SwiftUI

// MARK: - 撮影/選択直後のプレビュー画面
//
// 暗さ・ブレの簡易チェック結果を案内バナーとして表示し、「撮り直す」「読み取る」を選ばせる。

struct ReceiptCapturePreviewView: View {
    let image: UIImage
    let onRetake: () -> Void
    let onRecognize: () -> Void

    private var isDark: Bool { ImageQualityChecker.isDark(image) }
    private var isBlurry: Bool { ImageQualityChecker.isBlurry(image) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                if isDark || isBlurry {
                    qualityWarningBanner
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
            }

            Spacer(minLength: 0)

            buttonArea
        }
        .background(AppColors.sheetBackground)
    }

    private var qualityWarningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                if isDark {
                    Text("画像が暗いようです。明るい場所で撮り直すと読み取り精度が上がります。")
                        .font(.system(size: 13))
                }
                if isBlurry {
                    Text("画像がブレているようです。ピントを合わせて撮り直してください。")
                        .font(.system(size: 13))
                }
            }
            .foregroundStyle(Color.black.opacity(0.7))
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var buttonArea: some View {
        VStack(spacing: 10) {
            Button(action: onRecognize) {
                Text("読み取る")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColors.main)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button(action: onRetake) {
                Text("撮り直す")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }
}
