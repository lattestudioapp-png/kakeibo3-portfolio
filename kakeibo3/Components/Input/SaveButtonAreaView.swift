import SwiftUI
import Combine

// MARK: - 保存ボタンエリア

struct SaveButtonAreaView: View {
    let layout: InputFormLayout
    let onSave: () -> Void

    var body: some View {
        Button {
            onSave()
        } label: {
            Text("保存")
                .font(layout.saveButtonFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: layout.saveButtonHeight)
                .background(layout.mainColor)
                .clipShape(
                    RoundedRectangle(cornerRadius: layout.saveButtonCornerRadius)
                )
        }
        .padding(.horizontal, layout.saveButtonHorizontalPadding)
        .padding(.top, layout.saveButtonTopPadding)
        .padding(.bottom, layout.saveButtonBottomPadding)
        .background(layout.backgroundColor)
        .buttonStyle(.plain)
    }
}
