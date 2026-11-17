import SwiftUI
import VisionKit

// MARK: - レシート撮影用カメラ（VisionKitのドキュメントスキャナー）
//
// VNDocumentCameraViewControllerはエッジ検出・ガイド枠表示・自動撮影を標準で備えており、
// ImagePickerView（UIImagePickerController）よりレシート撮影に適している。
// 複数ページのスキャンに対応しているが、レシートは1枚として扱うため1ページ目のみ採用する。
// Simulatorでは動作しないため、実機での確認が必要。

struct DocumentCameraView: UIViewControllerRepresentable {
    let onScanned: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScanned: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onScanned: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScanned = onScanned
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                controller.dismiss(animated: true, completion: onCancel)
                return
            }
            let image = scan.imageOfPage(at: 0)
            controller.dismiss(animated: true) {
                self.onScanned(image)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true, completion: onCancel)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true, completion: onCancel)
        }
    }
}
