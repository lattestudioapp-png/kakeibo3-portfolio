import SwiftUI
import UIKit

// MARK: - 家計簿ノートPDF作成
//
// 選択されたページ種別を SwiftUI で描画 → ImageRenderer で画像化 → UIGraphicsPDFRenderer でPDF化する。
// 日別明細は1ページに収まる行数を用紙サイズから逆算し、複数ページに分割する。

@MainActor
enum BudgetNotebookPDFRenderer {

    static func makePDF(
        data: BudgetNotebookData,
        pageKinds: [NotebookPageKind],
        paperSize: NotebookPaperSize,
        accentColor: Color,
        reflection: NotebookReflectionText,
        periodLabel: String,
        pdfTitle: String
    ) -> URL? {
        let size = paperSize.size
        var pages: [AnyView] = []

        if pageKinds.contains(.monthlySummary) {
            pages.append(AnyView(
                MonthlySummaryPrintPage(data: data, accentColor: accentColor, pageSize: size, periodLabel: periodLabel)
            ))
        }

        if pageKinds.contains(.categoryBreakdown) {
            pages.append(AnyView(
                CategoryBreakdownPrintPage(data: data, accentColor: accentColor, pageSize: size, periodLabel: periodLabel)
            ))
        }

        if pageKinds.contains(.dailyDetail) {
            let chunks = chunkedDailyEntries(data.dailyEntries, pageSize: size)
            let total = max(chunks.count, 1)
            if chunks.isEmpty {
                pages.append(AnyView(
                    DailyDetailPrintPage(entries: [], pageIndex: 1, totalPages: total, accentColor: accentColor, pageSize: size, periodLabel: periodLabel)
                ))
            } else {
                for (index, chunk) in chunks.enumerated() {
                    pages.append(AnyView(
                        DailyDetailPrintPage(entries: chunk, pageIndex: index + 1, totalPages: total, accentColor: accentColor, pageSize: size, periodLabel: periodLabel)
                    ))
                }
            }
        }

        if pageKinds.contains(.reflection) {
            pages.append(AnyView(
                ReflectionPrintPage(reflection: reflection, accentColor: accentColor, pageSize: size, periodLabel: periodLabel)
            ))
        }

        guard !pages.isEmpty else { return nil }

        let images = pages.compactMap { renderImage($0, size: size) }
        guard !images.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let safeTitle = pdfTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "〜", with: "_")
            .replacingOccurrences(of: " ", with: "")
        let fileName = "\(safeTitle)_\(formatter.string(from: Date())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: pdfTitle]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
        do {
            try renderer.writePDF(to: url) { context in
                for image in images {
                    context.beginPage()
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 印刷

    static func presentPrint(url: URL, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true, completionHandler: nil)
    }

    // MARK: - 画像化

    private static func renderImage<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: - 日別明細のページ分割

    private static func chunkedDailyEntries(_ entries: [NotebookDailyEntry], pageSize: CGSize) -> [[NotebookDailyEntry]] {
        guard !entries.isEmpty else { return [] }

        let rowHeight: CGFloat = 26
        let reservedHeight: CGFloat = 160 // ヘッダー・表見出し・余白分
        let available = max(pageSize.height - reservedHeight, rowHeight * 4)
        let rowsPerPage = max(Int(available / rowHeight), 6)

        var chunks: [[NotebookDailyEntry]] = []
        var index = 0
        while index < entries.count {
            let end = min(index + rowsPerPage, entries.count)
            chunks.append(Array(entries[index..<end]))
            index = end
        }
        return chunks
    }
}
