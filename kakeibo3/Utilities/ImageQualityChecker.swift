import UIKit
import CoreImage

// MARK: - レシート撮影画像の簡易品質チェック（暗さ・ブレ）
//
// VNDocumentCameraViewControllerはリアルタイムの明るさ/ブレ情報を公開しないため、
// 撮影後の1枚に対してCore Imageで簡易的にチェックし、プレビュー画面で案内する。
// 高精度な判定は目的にしておらず、極端に暗い/ブレた場合のユーザー案内が目的。

enum ImageQualityChecker {
    private static let context = CIContext()

    static func isDark(_ image: UIImage) -> Bool {
        guard let averageLuminance = averageLuminance(of: image) else { return false }
        return averageLuminance < 60
    }

    static func isBlurry(_ image: UIImage) -> Bool {
        guard let sharpness = edgeEnergy(of: image) else { return false }
        return sharpness < 6
    }

    // 画像全体の平均輝度（0〜255相当）をCIAreaAverageで算出
    private static func averageLuminance(of image: UIImage) -> Double? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: "inputExtent")
        guard let outputImage = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Double(pixel[0]), g = Double(pixel[1]), b = Double(pixel[2])
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    // CIEdgesでエッジを強調した画像の平均輝度をブレの簡易指標として使う
    // （輪郭がはっきりしているほどエッジ強調後の平均輝度が高くなる）
    private static func edgeEnergy(of image: UIImage) -> Double? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let edgesFilter = CIFilter(name: "CIEdges") else { return nil }
        edgesFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgesFilter.setValue(4.0, forKey: kCIInputIntensityKey)
        guard let edged = edgesFilter.outputImage else { return nil }

        guard let averageFilter = CIFilter(name: "CIAreaAverage") else { return nil }
        averageFilter.setValue(edged, forKey: kCIInputImageKey)
        averageFilter.setValue(CIVector(cgRect: ciImage.extent), forKey: "inputExtent")
        guard let outputImage = averageFilter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Double(pixel[0]), g = Double(pixel[1]), b = Double(pixel[2])
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
