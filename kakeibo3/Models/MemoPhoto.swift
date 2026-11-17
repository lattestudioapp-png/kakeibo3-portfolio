import UIKit

// MARK: - メモ写真（表示用サムネイル + 保存用Data を一緒に持つ）

struct MemoPhoto: Identifiable, Equatable {
    let id: UUID
    let thumbnail: UIImage   // 表示専用（小サイズ）。Image(uiImage:) で使う
    let imageData: Data      // 保存専用（1280px以下 JPEG）。ディスク書き込みに使う

    init(thumbnail: UIImage, imageData: Data) {
        self.id = UUID()
        self.thumbnail = thumbnail
        self.imageData = imageData
    }

    static func == (lhs: MemoPhoto, rhs: MemoPhoto) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ファクトリ（バックグラウンドで呼ぶ）

extension MemoPhoto {

    // UIImage から MemoPhoto を生成（リサイズ + 圧縮 + サムネイル作成）
    static func make(from image: UIImage) -> MemoPhoto? {
        let saved = ReceiptImageHelper.resized(image, maxLength: 1280)
        guard let data = saved.jpegData(compressionQuality: 0.75) else { return nil }
        let thumbnail = ReceiptImageHelper.resized(image, maxLength: 160)
        return MemoPhoto(thumbnail: thumbnail, imageData: data)
    }

    // ディスク上のファイルパスから MemoPhoto を生成（編集画面ロード時）
    static func make(fromFilePath path: String) -> MemoPhoto? {
        guard let image = ReceiptImageHelper.load(path) else { return nil }
        return make(from: image)
    }
}
