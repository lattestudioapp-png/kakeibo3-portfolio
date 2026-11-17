import SwiftUI

// MARK: - アプリ起動・復帰時のロック画面

struct PasscodeLockView: View {
    let onUnlock: () -> Void

    @State private var errorMessage: String = ""

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            PasscodeEntryPanel(
                title: "パスコードを入力",
                errorMessage: errorMessage
            ) { input in
                if PasscodeManager.shared.validate(input) {
                    onUnlock()
                } else {
                    showError("パスコードが違います")
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            errorMessage = message
        }
    }
}
