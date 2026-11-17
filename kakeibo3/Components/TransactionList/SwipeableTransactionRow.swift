import SwiftUI

// MARK: - 左スワイプ削除対応の行ラッパー

struct SwipeableTransactionRow<Content: View>: View {
    @Binding var openItemID: UUID?
    let itemID: UUID
    let onTap: () -> Void
    let onDelete: () -> Void
    let content: Content

    @State private var offsetX: CGFloat = 0
    @State private var isDeleting = false

    private let capsuleHeight: CGFloat = 32
    private let capsuleTrailingPadding: CGFloat = 14
    private let minCapsuleWidth: CGFloat = 28
    private let openOffset: CGFloat = -96
    private let fullSwipeOffset: CGFloat = -230
    private let fullSwipeTranslation: CGFloat = -160

    private var isOpen: Bool { openItemID == itemID }

    private var dynamicCapsuleWidth: CGFloat {
        let raw = abs(offsetX) - capsuleTrailingPadding
        return max(minCapsuleWidth, raw)
    }

    init(
        openItemID: Binding<UUID?>,
        itemID: UUID,
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._openItemID = openItemID
        self.itemID = itemID
        self.onTap = onTap
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            content
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .offset(x: offsetX)
                .overlay {
                    RowGestureOverlay(
                        onTap: {
                            if isOpen { closeRow() } else { onTap() }
                        },
                        onPanChanged: { tx in
                            guard !isDeleting else { return }
                            onDragChanged(tx)
                        },
                        onPanEnded: { tx in
                            guard !isDeleting else { return }
                            onDragEnded(tx)
                        }
                    )
                }

            // 削除ボタンはZStackの最後（最前面）に置くことで、
            // .offset() がヒットテスト領域を移動しない SwiftUI の仕様を回避する
            deleteButton
                .opacity(offsetX < -20 ? 1 : 0)
                .allowsHitTesting(offsetX < -20)
        }
        .clipped()
        .onChange(of: openItemID) { _, newID in
            guard !isDeleting else { return }
            if newID != itemID, offsetX < 0 {
                withAnimation(.easeOut(duration: 0.2)) {
                    offsetX = 0
                }
            }
        }
    }

    // MARK: - カプセル削除ボタン

    private var deleteButton: some View {
        Button(action: { deleteWithAnimation() }) {
            Text("削除")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: dynamicCapsuleWidth, height: capsuleHeight)
                .background(Color.red)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, capsuleTrailingPadding)
    }

    // MARK: - ジェスチャー処理

    private func onDragChanged(_ translation: CGFloat) {
        if translation < 0 {
            let base: CGFloat = isOpen ? openOffset : 0
            offsetX = max(base + translation, fullSwipeOffset - 20)
        } else if offsetX < 0 {
            offsetX = min(0, (isOpen ? openOffset : 0) + translation)
        }
    }

    private func onDragEnded(_ translation: CGFloat) {
        if offsetX <= fullSwipeOffset || translation <= fullSwipeTranslation {
            deleteWithAnimation()
        } else if offsetX < openOffset / 2 {
            withAnimation(.easeOut(duration: 0.2)) {
                offsetX = openOffset
                openItemID = itemID
            }
        } else {
            closeRow()
        }
    }

    // MARK: - 削除アニメーション

    private func deleteWithAnimation() {
        guard !isDeleting else { return }
        isDeleting = true
        openItemID = nil

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        withAnimation(.easeOut(duration: 0.15)) {
            offsetX = -500
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            offsetX = 0
            onDelete()
        }
    }

    private func closeRow() {
        withAnimation(.easeOut(duration: 0.2)) {
            offsetX = 0
            if openItemID == itemID { openItemID = nil }
        }
    }
}

// MARK: - UIKit ジェスチャーオーバーレイ

private struct RowGestureOverlay: UIViewRepresentable {
    let onTap: () -> Void
    let onPanChanged: (CGFloat) -> Void
    let onPanEnded: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onPanChanged = onPanChanged
        context.coordinator.onPanEnded = onPanEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPanChanged: onPanChanged, onPanEnded: onPanEnded)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        var onPanChanged: (CGFloat) -> Void
        var onPanEnded: (CGFloat) -> Void

        init(
            onTap: @escaping () -> Void,
            onPanChanged: @escaping (CGFloat) -> Void,
            onPanEnded: @escaping (CGFloat) -> Void
        ) {
            self.onTap = onTap
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
        }

        @objc func handleTap() {
            onTap()
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let tx = pan.translation(in: pan.view).x
            switch pan.state {
            case .began, .changed:
                onPanChanged(tx)
            case .ended, .cancelled:
                onPanEnded(tx)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return true
        }
    }
}
