import SwiftUI

// MARK: - 点滅カーソル
//
// 金額入力中であることを示す縦棒カーソル。
// マウント中は自動で点滅し続け、アンマウントされると停止する。
// 呼び出し側は `if isEditing { BlinkingCursorView(...) }` のように
// 条件付きで配置するだけでよい。

struct BlinkingCursorView: View {
    var width: CGFloat = 2
    var height: CGFloat
    var color: Color = .accentColor

    @State private var isCursorVisible = false
    @State private var timer: Timer? = nil

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: height)
            .opacity(isCursorVisible ? 1 : 0)
            .onAppear { startBlinking() }
            .onDisappear { stopBlinking() }
    }

    private func startBlinking() {
        timer?.invalidate()
        isCursorVisible = true
        let newTimer = Timer(timeInterval: 0.6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                isCursorVisible.toggle()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopBlinking() {
        timer?.invalidate()
        timer = nil
        isCursorVisible = false
    }
}
