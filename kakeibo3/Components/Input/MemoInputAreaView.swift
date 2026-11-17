import SwiftUI
import Combine

// MARK: - メモフォーカス識別子
//
// 入力Viewは支出/収入/振替の3ページ、取引編集Viewは支出/収入の2ページが
// 同じHStack内に同時に存在する（スワイプ切り替えのためoffsetで隠しているだけで、
// ビュー自体は常に生成されている）。各ページが同じ MemoInputAreaView を使うため、
// 全ページが同じ .memo 値だけで .focused(_, equals:) すると、
// どのページのTextFieldが実際にフォーカスを受け取るかSwiftUI側で曖昧になり、
// 「タップしてもカーソルが出ない/文字が反映されない」といった不安定な挙動の原因になる。
// ページごとに一意な識別子を持たせて区別する。

enum InputFocusedField: Hashable {
    case memo(String)
}

// MARK: - メモ入力エリア

struct MemoInputAreaView: View {
    @Binding var memo: String
    @Binding var memoPhotos: [MemoPhoto]
    var focusedField: FocusState<InputFocusedField?>.Binding
    @Binding var isCalculatorKeyboardPresented: Bool
    var onCameraButtonTap: () -> Void

    // 設定「カメラマークの表示」がOFFの画面から呼ばれた場合に false が渡る。
    // デフォルトtrueのため、この値を指定しない既存の呼び出し元（振替画面など）は
    // 従来通りカメラマークが表示され続ける。
    var showsCameraIcon: Bool = true

    // 支出/収入/振替など、このメモ欄が属するページを一意に区別するための識別子
    let focusId: String

    let layout: InputFormLayout

    private var focusValue: InputFocusedField { .memo(focusId) }

    var body: some View {
        HStack(spacing: 0) {
            // 「メモ」ラベル：カメラボタンを含まない単独のタップ領域なので、素の onTapGesture で問題ない
            Text("メモ")
                .font(layout.memoTitleFont)
                .foregroundStyle(Color.black)
                .contentShape(Rectangle())
                .onTapGesture { startMemoEditing() }

            // カメラボタン：メモ入力開始のタップ範囲から独立させ、競合しないようにする
            if showsCameraIcon {
                Button {
                    onCameraButtonTap()
                } label: {
                    Image(systemName: !memoPhotos.isEmpty ? "camera.fill" : "camera")
                        .font(.system(size: 16))
                        .foregroundStyle(!memoPhotos.isEmpty ? AppColors.main : Color.gray.opacity(0.55))
                        .frame(width: 32, height: 32)
                }
                .padding(.leading, 6)
            }

            // 空白部分 + TextField：まとめて1つのタップ領域にする。
            // TextFieldが同じ領域にあると素の onTapGesture は競合してタップを取りこぼすことがあるため、
            // TextField自身のジェスチャーと共存できる simultaneousGesture で確実に拾う
            // （InputDateAreaView / MethodSelectAreaView と同じ方式）
            HStack(spacing: 2) {
                Spacer()

                // TextField標準の入力・カーソル挙動をそのまま使う（独自カーソルは持たない）
                TextField(
                    "",
                    text: $memo,
                    prompt: Text(layout.memoPlaceholder)
                        .foregroundStyle(Color.black.opacity(0.45))
                )
                .font(layout.memoTextFieldFont)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(layout.memoTextColor)
                .offset(y: layout.memoTextFieldYOffset)
                .focused(focusedField, equals: focusValue)
                .fixedSize()
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { startMemoEditing() })
        }
        .padding(.horizontal, layout.memoHorizontalPadding)
        .frame(height: layout.memoRowHeight)
        .background(layout.memoBackgroundColor)
        .onChange(of: focusedField.wrappedValue) { _, newValue in
            // メモにフォーカスが移ったら、経路（行タップ／TextField直接タップ）に関わらず
            // 電卓キーボードを閉じて文字キーボードだけにする
            if newValue == focusValue {
                isCalculatorKeyboardPresented = false
            }
        }
        .overlay(alignment: .top) {
            if layout.showsMemoTopBorder {
                ThinBorderView(layout: layout)
            }
        }
        .overlay(alignment: .bottom) {
            if layout.showsMemoBottomBorder {
                ThinBorderView(layout: layout)
            }
        }
        .offset(y: layout.memoAreaYOffset)
    }

    // 文字部分タップ／行全体タップのどちらでも同じ処理を通す
    private func startMemoEditing() {
        isCalculatorKeyboardPresented = false
        focusedField.wrappedValue = focusValue
    }
}
