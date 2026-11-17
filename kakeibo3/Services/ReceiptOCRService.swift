import UIKit
import Vision

// MARK: - レシート画像のテキスト認識（Vision framework、完全オンデバイス・無料）
//
// VNImageRequestHandler.perform は同期・ブロッキング呼び出しのため、
// メインアクター上で直接呼ばない。呼び出し側でTask.detachedを使い、
// メインスレッド外で実行すること（nonisolatedな値型のみを扱うためSendable）。

enum ReceiptOCRService {
    struct RecognizedLine {
        let text: String
        /// Visionの正規化座標（原点は左下、y=1が画面上端）
        let boundingBox: CGRect
    }

    enum OCRError: Error {
        case invalidImage
    }

    nonisolated static func recognizeLines(in image: UIImage) throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines: [RecognizedLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
        }
        // Visionのy座標は下から上に増えるため、降順に並べると読み取り順（上→下）になる
        return lines.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
    }
}
