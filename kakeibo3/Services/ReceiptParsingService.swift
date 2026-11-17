import Foundation

// MARK: - OCR結果（行配列）→ 構造化データへの変換
//
// すべて正規表現・キーワードによるベストエフォートなヒューリスティック。
// レシートのレイアウトは店舗ごとに大きく異なるため完全な精度は前提とせず、
// 読み取れなかった項目はnilのまま返す（呼び出し側で「未設定」表示にする）。

struct ParsedReceiptItem {
    var name: String
    var amount: Int
}

struct ReceiptParseResult {
    var date: Date?
    var storeName: String?
    var items: [ParsedReceiptItem]
    var receiptTotal: Int?
    var subtotal: Int?
    var taxAmount: Int?
    var isTaxIncluded: Bool?
    var paymentMethodGuess: String?
}

enum ReceiptParsingService {
    // 合計系キーワード（優先度の高い順）。「合計」単体は「小計」「税込合計」等と衝突しやすいため、
    // より具体的なキーワードを先に試す。
    private static let totalKeywords = ["お買上げ合計", "ご利用金額", "お会計", "合計金額", "総合計", "合計"]
    private static let subtotalKeywords = ["小計"]
    private static let taxKeywords = ["内消費税", "消費税", "内税"]
    private static let taxIncludedKeywords = ["税込"]
    private static let taxExcludedKeywords = ["税抜"]

    private static let excludeFromItemsKeywords: [String] =
        totalKeywords + subtotalKeywords + taxKeywords + taxIncludedKeywords + taxExcludedKeywords + [
            "領収書", "レシート", "お預り", "お預かり", "おつり", "お釣り", "点数", "様",
            "電話", "TEL", "住所", "登録番号", "ありがとうございました", "またお越しください"
        ]

    private static let paymentMethodKeywordTable: [(keywords: [String], guess: String)] = [
        (["現金"], "現金"),
        (["クレジット", "クレジットカード", "VISA", "Mastercard", "MasterCard", "JCB", "AMEX", "銀聯"], "クレジットカード"),
        (["電子マネー", "交通系IC", "Suica", "PASMO", "nanaco", "WAON", "楽天Edy", "Edy"], "電子マネー"),
        (["QRコード決済", "PayPay", "d払い", "楽天ペイ", "au PAY", "メルペイ"], "コード決済")
    ]

    static func parse(lines: [ReceiptOCRService.RecognizedLine]) -> ReceiptParseResult {
        let texts = lines.map(\.text)

        var result = ReceiptParseResult(
            date: nil,
            storeName: nil,
            items: [],
            receiptTotal: nil,
            subtotal: nil,
            taxAmount: nil,
            isTaxIncluded: nil,
            paymentMethodGuess: nil
        )

        result.date = extractDate(from: texts)
        result.storeName = extractStoreName(from: texts)
        result.isTaxIncluded = texts.contains { $0.contains(taxIncludedKeywords[0]) } ? true
            : (texts.contains { $0.contains(taxExcludedKeywords[0]) } ? false : nil)
        result.subtotal = extractAmount(from: texts, matching: subtotalKeywords)
        result.taxAmount = extractAmount(from: texts, matching: taxKeywords)
        result.receiptTotal = extractAmount(from: texts, matching: totalKeywords)
        result.paymentMethodGuess = extractPaymentMethod(from: texts)
        result.items = extractItems(from: texts)

        return result
    }

    // MARK: - 日付

    private static let dateRegexes: [(pattern: String, formatIsReiwa: Bool)] = [
        (#"(\d{4})[/年](\d{1,2})[/月](\d{1,2})日?"#, false),
        (#"令和(\d{1,2})年(\d{1,2})月(\d{1,2})日"#, true),
        (#"(\d{2})[/.](\d{1,2})[/.](\d{1,2})"#, false)
    ]

    private static func extractDate(from texts: [String]) -> Date? {
        for text in texts {
            for entry in dateRegexes {
                guard let regex = try? NSRegularExpression(pattern: entry.pattern) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                guard let match = regex.firstMatch(in: text, range: range) else { continue }
                guard let date = date(from: match, in: text, isReiwa: entry.formatIsReiwa) else { continue }
                return date
            }
        }
        return nil
    }

    private static func date(from match: NSTextCheckingResult, in text: String, isReiwa: Bool) -> Date? {
        guard match.numberOfRanges == 4,
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text),
              let r3 = Range(match.range(at: 3), in: text),
              let p1 = Int(text[r1]), let month = Int(text[r2]), let day = Int(text[r3])
        else { return nil }

        var year: Int
        if isReiwa {
            year = 2018 + p1 // 令和1年 = 2019年
        } else if p1 < 100 {
            year = 2000 + p1 // 2桁年は感熱紙レシートで一般的、2000年代前提
        } else {
            year = p1
        }

        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)
    }

    // MARK: - 店舗名

    private static func extractStoreName(from texts: [String]) -> String? {
        let candidates = texts.prefix(5)
        for text in candidates {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard trimmedAmount(in: trimmed) == nil else { continue }
            guard !isPureSymbolOrNumber(trimmed) else { continue }
            guard !excludeFromItemsKeywords.contains(where: { trimmed.contains($0) }) else { continue }
            return trimmed
        }
        return nil
    }

    private static func isPureSymbolOrNumber(_ text: String) -> Bool {
        text.allSatisfy { $0.isNumber || $0.isSymbol || $0.isPunctuation || $0.isWhitespace }
    }

    // MARK: - 金額抽出（行末の￥1,234円のようなパターン）

    private static let amountRegex = try? NSRegularExpression(pattern: #"[¥￥]?\s*([\d,]{2,})\s*円?\s*$"#)

    private static func trimmedAmount(in text: String) -> Int? {
        guard let regex = amountRegex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges == 2,
              let amountRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let digits = text[amountRange].replacingOccurrences(of: ",", with: "")
        return Int(digits)
    }

    private static func extractAmount(from texts: [String], matching keywords: [String]) -> Int? {
        for keyword in keywords {
            for text in texts where text.contains(keyword) {
                if let amount = trimmedAmount(in: text) {
                    return amount
                }
            }
        }
        return nil
    }

    // MARK: - 支払い方法

    private static func extractPaymentMethod(from texts: [String]) -> String? {
        for text in texts {
            for entry in paymentMethodKeywordTable where entry.keywords.contains(where: { text.contains($0) }) {
                return entry.guess
            }
        }
        return nil
    }

    // MARK: - 商品行

    private static func extractItems(from texts: [String]) -> [ParsedReceiptItem] {
        var items: [ParsedReceiptItem] = []

        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !excludeFromItemsKeywords.contains(where: { trimmed.contains($0) }) else { continue }
            guard let amount = trimmedAmount(in: trimmed), amount > 0 else { continue }

            var name = trimmed
            if let regex = amountRegex {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = regex.firstMatch(in: trimmed, range: range),
                   let matchRange = Range(match.range, in: trimmed) {
                    name = String(trimmed[trimmed.startIndex..<matchRange.lowerBound])
                }
            }
            name = cleanItemName(name)
            guard !name.isEmpty else { continue }

            items.append(ParsedReceiptItem(name: name, amount: amount))
        }

        return items
    }

    private static func cleanItemName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        // 先頭の個数表記（例: "×2 " "2個 "）を除去
        if let regex = try? NSRegularExpression(pattern: #"^(×\d+|\d+個)\s*"#) {
            let range = NSRange(name.startIndex..., in: name)
            name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
