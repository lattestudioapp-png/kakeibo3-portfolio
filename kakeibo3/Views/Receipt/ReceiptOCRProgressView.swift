import SwiftUI

// MARK: - OCR解析中の待機画面

struct ReceiptOCRProgressView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("読み取り中…")
                .font(.system(size: 15))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.sheetBackground)
    }
}
