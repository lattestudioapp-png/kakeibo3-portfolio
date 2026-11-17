import Foundation

// MARK: - 文字コード選択

enum CSVExportEncoding: String, CaseIterable {
    case utf8
    case shiftJIS
}

// MARK: - 出力対象選択

enum CSVExportTarget: String, CaseIterable {
    case all
    case expenseOnly
    case incomeOnly
}

// MARK: - CSVエクスポートエラー

enum CSVExportError: LocalizedError {
    case noData
    case shiftJISConversionFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noData:
            return "出力できるデータがありません"
        case .shiftJISConversionFailed:
            return "Shift_JISで出力できない文字が含まれています。UTF-8で出力してください。"
        case .writeFailed:
            return "CSVファイルの書き出しに失敗しました。"
        }
    }
}

// MARK: - CSVエクスポートサービス

struct CSVExportService {

    private struct ExportRow {
        let date: Date
        let type: String
        let category: String
        let method: String
        let amount: Int
        let memo: String
        let createdAt: Date
    }

    // MARK: - エクスポート実行

    static func exportCSV(
        bookId: UUID?,
        encoding: CSVExportEncoding,
        target: CSVExportTarget,
        startDate: Date?,
        endDate: Date?
    ) throws -> URL {
        var rows: [ExportRow] = []

        if target != .incomeOnly {
            let expenses = ExpenseDataSync.fetchAll()
                .filter { $0.bookId == bookId }
            rows.append(contentsOf: expenses.map {
                ExportRow(
                    date: $0.date,
                    type: "支出",
                    category: $0.category,
                    method: $0.paymentMethod,
                    amount: $0.amount,
                    memo: $0.memo,
                    createdAt: $0.createdAt
                )
            })
        }

        if target != .expenseOnly {
            let incomes = IncomeDataSync.fetchAll()
                .filter { $0.bookId == bookId }
            rows.append(contentsOf: incomes.map {
                ExportRow(
                    date: $0.date,
                    type: "収入",
                    category: $0.category,
                    method: $0.receiveMethod,
                    amount: $0.amount,
                    memo: $0.memo,
                    createdAt: $0.createdAt
                )
            })
        }

        rows = filterByDateRange(rows: rows, startDate: startDate, endDate: endDate)

        guard !rows.isEmpty else {
            throw CSVExportError.noData
        }

        // 日付の古い順、同じ日付なら登録日時の古い順
        rows.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.createdAt < $1.createdAt
        }

        let csvString = makeCSVString(rows: rows)
        return try writeToTemporaryFile(csvString, encoding: encoding)
    }

    // MARK: - 期間フィルタ

    private static func filterByDateRange(
        rows: [ExportRow],
        startDate: Date?,
        endDate: Date?
    ) -> [ExportRow] {
        let calendar = Calendar.current
        let lowerBound = startDate.map { calendar.startOfDay(for: $0) }
        let upperBound = endDate.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
        }

        return rows.filter { row in
            if let lowerBound, row.date < lowerBound { return false }
            if let upperBound, row.date >= upperBound { return false }
            return true
        }
    }

    // MARK: - CSV文字列生成

    private static func makeCSVString(rows: [ExportRow]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"

        var lines: [String] = []
        lines.append(
            ["日付", "種類", "カテゴリー", "支払い・受け取り方法", "金額", "メモ", "登録日時"]
                .map(escapeCSVField)
                .joined(separator: ",")
        )

        for row in rows {
            let fields = [
                dateFormatter.string(from: row.date),
                row.type,
                row.category,
                row.method,
                String(row.amount),
                row.memo,
                dateTimeFormatter.string(from: row.createdAt)
            ]
            lines.append(fields.map(escapeCSVField).joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }

    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    // MARK: - ファイル書き出し

    private static func writeToTemporaryFile(_ csvString: String, encoding: CSVExportEncoding) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "kakeibo_export_\(formatter.string(from: Date())).csv"

        let data: Data
        switch encoding {
        case .utf8:
            guard let textData = csvString.data(using: .utf8) else {
                throw CSVExportError.writeFailed
            }
            let bom = Data([0xEF, 0xBB, 0xBF])
            data = bom + textData
        case .shiftJIS:
            guard let textData = csvString.data(using: .shiftJIS, allowLossyConversion: false) else {
                throw CSVExportError.shiftJISConversionFailed
            }
            data = textData
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}
