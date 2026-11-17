import SwiftUI
import Combine

// MARK: - 入力フォーム用区切り線

struct ThinBorderView: View {
    let layout: InputFormLayout

    var body: some View {
        Rectangle()
            .fill(layout.thinBorderColor)
            .frame(height: 1)
    }
}
