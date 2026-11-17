import SwiftUI
import UIKit

// MARK: - ピンチ拡大・ドラッグ移動対応の画像ビュー

struct ZoomableImageView: View {
    let image: UIImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnifyGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) { handleDoubleTap() }
    }

    // MARK: - ピンチ

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < minScale {
                    withAnimation(.spring()) {
                        resetTransform()
                    }
                }
            }
    }

    // MARK: - ドラッグ

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                if scale > 1.0 {
                    lastOffset = offset
                } else {
                    withAnimation(.spring()) {
                        offset = .zero
                    }
                    lastOffset = .zero
                }
            }
    }

    // MARK: - ダブルタップ

    private func handleDoubleTap() {
        withAnimation(.spring()) {
            if scale > 1.0 {
                resetTransform()
            } else {
                scale = 2.0
            }
        }
    }

    private func resetTransform() {
        scale = minScale
        offset = .zero
        lastOffset = .zero
    }
}
