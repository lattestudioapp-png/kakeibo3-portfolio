import UIKit

// MARK: - レシート画像の保存・読み込みユーティリティ

enum ReceiptImageHelper {

    private static var receiptsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("receipts")
    }

    // Documents/receipts/<UUID>.jpg に保存し、ファイル名を返す
    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let dir = receiptsDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(filename))
            return filename
        } catch {
            return nil
        }
    }

    // ファイル名から UIImage を読み込む
    static func load(_ filename: String) -> UIImage? {
        let url = receiptsDirectory.appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    // ファイルを削除する
    static func delete(_ filename: String) {
        let url = receiptsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 複数枚対応

    // [String] → カンマ区切り文字列（DBの String? フィールドに保存）
    static func encodePaths(_ paths: [String]) -> String? {
        paths.isEmpty ? nil : paths.joined(separator: ",")
    }

    // カンマ区切り文字列 → [String]（既存の1枚データも自動対応）
    static func decodePaths(_ encoded: String?) -> [String] {
        guard let encoded, !encoded.isEmpty else { return [] }
        return encoded.split(separator: ",").map(String.init)
    }

    // 複数ファイルをまとめて読み込む（読み込めないものはスキップ）
    static func loadAll(_ paths: [String]) -> [UIImage] {
        paths.compactMap { load($0) }
    }

    // 複数ファイルをまとめて削除する
    static func deleteAll(_ paths: [String]) {
        paths.forEach { delete($0) }
    }

    // MARK: - 軽量化対応

    // 圧縮済みDataをそのままファイルに保存（MemoPhoto保存時に使う）
    static func save(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let dir = receiptsDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(filename))
            return filename
        } catch {
            return nil
        }
    }

    // MARK: - 生バイト列での読み書き（CloudKit同期用）
    //
    // UIImageを経由すると再エンコードによる画質劣化・EXIF情報の欠落が起こるため、
    // 同期用の読み書きは常にこちらを使い、元のJPEGバイト列をそのまま扱う
    // （レシートOCRの読み取り精度を優先するため、同期のために画質を落とさない）。

    // ファイル名から生のJPEGバイト列を読み込む（CloudKitへアップロードする直前に使う）
    static func loadData(_ filename: String) -> Data? {
        let url = receiptsDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    // 指定したファイル名でそのまま書き込む。既に同名ファイルが存在する場合は何もしない
    // （絶対に上書きしない）。別端末からCloudKit経由で届いた写真をローカルキャッシュへ
    // 書き出す際に使う。戻り値：新たに書き込んだら true、既に存在していて何もしなければ false。
    @discardableResult
    static func writeIfMissing(_ data: Data, filename: String) -> Bool {
        let dir = receiptsDirectory
        let url = dir.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    // 長辺を maxLength 以下にリサイズ（バックグラウンドで呼ぶ）
    static func resized(_ image: UIImage, maxLength: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxLength else { return image }
        let scale = maxLength / maxSide
        let newSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
