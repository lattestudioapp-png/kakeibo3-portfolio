import SwiftUI
import Combine

// MARK: - 支払い方法 / 受け取り方法エリア

struct MethodSelectAreaView: View {
    @Binding var selectedMethod: String

    let methodTitle: String
    let methods: [MethodOption]
    let layout: InputFormLayout
    var onTapUnset: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(methodTitle)
                .font(layout.rowTitleFont)
                .foregroundStyle(Color.black)

            Spacer()

            if methods.isEmpty {
                // 候補が0件のときは「＋ 新しく追加」を表示してタップで設定画面へ
                Button {
                    onTapUnset?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("新しく追加")
                            .font(layout.smallInputTextFont)
                    }
                    .foregroundStyle(AppColors.main)
                    .frame(
                        width: layout.smallInputWidth,
                        height: layout.smallInputHeight
                    )
                    .background(layout.rowBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                            .stroke(AppColors.main.opacity(0.4), lineWidth: 1)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(methods) { method in
                        Button {
                            selectedMethod = method.name
                        } label: {
                            if method.isLocked {
                                Label(method.name, systemImage: "lock.fill")
                            } else {
                                Text(method.name)
                            }
                        }
                        .disabled(method.isLocked)
                    }

                    Divider()

                    Button {
                        onTapUnset?()
                    } label: {
                        Label("新しく追加", systemImage: "plus")
                    }
                } label: {
                    Text(selectedMethod.isEmpty ? (methods.first?.name ?? "") : selectedMethod)
                        .font(layout.smallInputTextFont)
                        .foregroundStyle(.tint)
                        .frame(
                            width: layout.smallInputWidth,
                            height: layout.smallInputHeight
                        )
                        .background(layout.rowBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                                .stroke(layout.lineColor, lineWidth: 1)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                        )
                }
                .frame(width: 10, alignment: .trailing)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, layout.rowHorizontalPadding)
        .frame(height: layout.normalRowHeight)
        .background(layout.rowBackgroundColor)
        .overlay(alignment: .top) {
            ThinBorderView(layout: layout)
        }
    }
}
