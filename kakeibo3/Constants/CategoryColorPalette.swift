import Foundation

// MARK: - カテゴリー色パレット（128色）

enum CategoryColorPalette {

    static let colors: [String] = [
        // Green 系 (16色)
        "#1B5E20", "#2E7D32", "#388E3C", "#43A047",
        "#4CAF50", "#66BB6A", "#81C784", "#A5D6A7",
        "#00695C", "#00796B", "#00897B", "#26A69A",
        "#4DB6AC", "#80CBC4", "#B2DFDB", "#E0F2F1",

        // Blue 系 (16色)
        "#0D47A1", "#1565C0", "#1976D2", "#1E88E5",
        "#2196F3", "#42A5F5", "#64B5F6", "#90CAF9",
        "#283593", "#303F9F", "#3949AB", "#3F51B5",
        "#5C6BC0", "#7986CB", "#9FA8DA", "#C5CAE9",

        // Cyan / Light Blue 系 (16色)
        "#006064", "#00838F", "#0097A7", "#00ACC1",
        "#00BCD4", "#26C6DA", "#4DD0E1", "#80DEEA",
        "#01579B", "#0277BD", "#0288D1", "#039BE5",
        "#03A9F4", "#29B6F6", "#4FC3F7", "#81D4FA",

        // Red / Pink 系 (16色)
        "#B71C1C", "#C62828", "#D32F2F", "#E53935",
        "#F44336", "#EF5350", "#E57373", "#EF9A9A",
        "#880E4F", "#AD1457", "#C2185B", "#D81B60",
        "#E91E63", "#EC407A", "#F48FB1", "#F8BBD0",

        // Orange 系 (16色)
        "#BF360C", "#D84315", "#E64A19", "#F4511E",
        "#FF5722", "#FF7043", "#FF8A65", "#FFAB91",
        "#E65100", "#EF6C00", "#F57C00", "#FB8C00",
        "#FF9800", "#FFA726", "#FFB74D", "#FFCC80",

        // Yellow / Lime 系 (16色)
        "#F57F17", "#F9A825", "#FBC02D", "#FDD835",
        "#FFEB3B", "#FFEE58", "#FFF176", "#FFF9C4",
        "#827717", "#9E9D24", "#AFB42B", "#C0CA33",
        "#CDDC39", "#D4E157", "#DCE775", "#F0F4C3",

        // Purple 系 (16色)
        "#4A148C", "#6A1B9A", "#7B1FA2", "#8E24AA",
        "#9C27B0", "#AB47BC", "#BA68C8", "#CE93D8",
        "#311B92", "#4527A0", "#512DA8", "#5E35B1",
        "#673AB7", "#7E57C2", "#9575CD", "#B39DDB",

        // Brown / Gray 系 (16色)
        "#3E2723", "#4E342E", "#5D4037", "#6D4C41",
        "#795548", "#8D6E63", "#A1887F", "#BCAAA4",
        "#212121", "#424242", "#616161", "#757575",
        "#9E9E9E", "#BDBDBD", "#D6D6D6", "#EEEEEE",
    ]

    /// 同じ type のカテゴリーで未使用の色を返す。全色使用済みの場合は先頭色。
    static func nextAvailableColorHex(usedColorHexes: [String]) -> String {
        let usedSet = Set(usedColorHexes.map { normalize($0) })

        if let unused = colors.first(where: { !usedSet.contains(normalize($0)) }) {
            return unused
        }

        return colors.first ?? "#9E9E9E"
    }

    static func normalize(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let withHash = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        return withHash.uppercased()
    }

    // MARK: - 既存色と一番離れた色を選ぶ

    /// パレットは色相ごとに16色ずつ並んでいるため、先頭から順に拾うと同系色が続く。
    /// 既存カテゴリーが0件の時（最初の1色目）だけ使うフォールバック順。
    /// 各色相グループの同じ位置を先に一巡することで、最初の1色が偏らないようにする。
    static let paletteOrderForAutoPick: [String] = {
        let perFamily = 16
        let familyCount = colors.count / perFamily
        var order: [String] = []
        for positionInFamily in 0..<perFamily {
            for family in 0..<familyCount {
                let index = family * perFamily + positionInFamily
                if index < colors.count {
                    order.append(colors[index])
                }
            }
        }
        return order
    }()

    /// 既存カテゴリーの色一覧から、最も離れた色をパレットから選ぶ。
    ///
    /// 優先順位:
    /// 1. 未使用色の中で、既存色との最小距離が一番大きい色
    /// 2. 全色使用済みなら、使用回数が少なく、既存色との距離が遠い色
    /// 3. それでも並んだら、直近で使われていない色
    ///
    /// - Parameter existingColors: 同じ type（支出 or 収入）の既存カテゴリーの colorHex 一覧
    static func nextDistinctColor(existingColors: [String]) -> String {
        guard !existingColors.isEmpty else {
            return paletteOrderForAutoPick.first ?? colors.first ?? "#9E9E9E"
        }

        let existingNormalized = existingColors.map { normalize($0) }
        let existingRGB = existingColors.map { hexToRGB($0) }

        func minDistanceToExisting(_ candidate: String) -> Double {
            let candidateRGB = hexToRGB(candidate)
            return existingRGB.map { distance(candidateRGB, $0) }.min() ?? 0
        }

        var usageCount: [String: Int] = [:]
        var lastUsedIndex: [String: Int] = [:]
        for (index, hex) in existingNormalized.enumerated() {
            usageCount[hex, default: 0] += 1
            lastUsedIndex[hex] = index
        }

        let unusedColors = colors.filter { usageCount[normalize($0)] == nil }

        if !unusedColors.isEmpty {
            let withDistance = unusedColors.map { ($0, minDistanceToExisting($0)) }
            return withDistance.max { $0.1 < $1.1 }?.0 ?? unusedColors[0]
        }

        // 全色使用済み: 使用回数が少なく → 距離が遠く → 直近使われていない色を優先
        return colors.max { a, b in
            let normA = normalize(a), normB = normalize(b)
            let countA = usageCount[normA] ?? 0
            let countB = usageCount[normB] ?? 0
            if countA != countB { return countA > countB }

            let distA = minDistanceToExisting(a)
            let distB = minDistanceToExisting(b)
            if distA != distB { return distA < distB }

            let lastA = lastUsedIndex[normA] ?? -1
            let lastB = lastUsedIndex[normB] ?? -1
            return lastA > lastB
        } ?? colors.first ?? "#9E9E9E"
    }

    /// RGB (0-255) のユークリッド距離
    private static func distance(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        let dr = a.r - b.r
        let dg = a.g - b.g
        let db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// 2つのhex色のRGB距離（0に近いほど似ている）
    static func colorDistance(_ hex1: String, _ hex2: String) -> Double {
        distance(hexToRGB(hex1), hexToRGB(hex2))
    }

    /// hex文字列をRGB各成分（0-255）に変換する。変換自体は ColorHexConverter に委譲する。
    static func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let c = ColorHexConverter.rgbComponents(from: hex)
        return (r: c.red * 255, g: c.green * 255, b: c.blue * 255)
    }
}
