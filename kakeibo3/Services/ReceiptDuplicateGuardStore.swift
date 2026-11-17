import UIKit
import CoreImage

// MARK: - 同一レシートの二重保存防止
//
// 撮影画像を16x16グレースケールに縮小した平均ハッシュ（aHash）で同一性を判定する。
// OCRのパース結果（店舗名・日付）は解析失敗や同一店舗の再来店で衝突しうるため使わず、
// 画像そのものの近似指紋を使う。UserDefaultsにJSON配列で保存し、クラウド同期はしない
// （BackupManagerの対象にも含めない）。

enum ReceiptDuplicateGuardStore {
    private static let storageKey = "receiptSavedHashes.v1"
    private static let hashSize = 16
    private static let context = CIContext()

    static func isDuplicate(_ image: UIImage) -> Bool {
        guard let hash = perceptualHash(of: image) else { return false }
        return loadHashes().contains(hash)
    }

    static func markSaved(_ image: UIImage) {
        guard let hash = perceptualHash(of: image) else { return }
        var hashes = loadHashes()
        hashes.insert(hash)
        persist(hashes)
    }

    // MARK: - aHash計算

    private static func perceptualHash(of image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let grayscale = grayscaleFilter.outputImage else { return nil }

        let extent = grayscale.extent
        let scaleX = CGFloat(hashSize) / extent.width
        let scaleY = CGFloat(hashSize) / extent.height
        let scaled = grayscale.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(
            scaled,
            from: CGRect(x: 0, y: 0, width: hashSize, height: hashSize)
        ) else { return nil }

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let pixelData = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var luminances: [Int] = []
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset < CFDataGetLength(data) else { continue }
                luminances.append(Int(pixelData[offset]))
            }
        }
        guard !luminances.isEmpty else { return nil }

        let average = luminances.reduce(0, +) / luminances.count
        var bits = ""
        for luminance in luminances {
            bits += luminance >= average ? "1" : "0"
        }

        // 2進文字列を16進文字列に変換してコンパクトに保存
        var hex = ""
        var index = bits.startIndex
        while index < bits.endIndex {
            let end = bits.index(index, offsetBy: 4, limitedBy: bits.endIndex) ?? bits.endIndex
            let chunk = String(bits[index..<end])
            let padded = chunk.padding(toLength: 4, withPad: "0", startingAt: 0)
            if let value = UInt8(padded, radix: 2) {
                hex += String(value, radix: 16)
            }
            index = end
        }
        return hex
    }

    // MARK: - 永続化

    private static func loadHashes() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(array)
    }

    private static func persist(_ hashes: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(hashes)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
