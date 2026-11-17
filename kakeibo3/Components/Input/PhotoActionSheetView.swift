import SwiftUI
import UIKit

// MARK: - 写真追加・削除メニュー（画面下固定）

struct PhotoActionSheetView: View {
    @Binding var isPresented: Bool
    let hasPhoto: Bool
    let onTakePhoto: () -> Void
    let onSelectLibrary: () -> Void
    let onDeletePhoto: () -> Void

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 8) {
                // メインアクションパネル
                VStack(spacing: 0) {
                    if cameraAvailable {
                        actionButton("写真を撮る") {
                            isPresented = false
                            onTakePhoto()
                        }
                        Divider()
                    }

                    actionButton("ライブラリから選択") {
                        isPresented = false
                        onSelectLibrary()
                    }

                    if hasPhoto {
                        Divider()
                        Button(role: .destructive) {
                            isPresented = false
                            onDeletePhoto()
                        } label: {
                            Text("写真を削除")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.red.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // キャンセルボタン
                Button { isPresented = false } label: {
                    Text("キャンセル")
                        .font(AppFonts.button)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, AppLayout.bottomNavigationHeight - 80)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}
