import Combine
//
//  ColorHexConverter.swift
//  KakeiboApp
//
//  Created by 楠本陸 on 2026/05/29.
//


import SwiftUI

// MARK: - Color と Hex の変換

/**
 SwiftUI の Color と、保存用の16進カラー文字列を変換するための部品。
 */
struct ColorHexConverter {

    /**
     Hex文字列から Color を作る。
     
     例:
     "#4A7DBA" → Color
     */
    static func color(from hex: String) -> Color {
        let c = rgbComponents(from: hex)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /**
     お金の管理データ（現金・クレジットカード・銀行口座など）用。
     colorHexが未設定（nil・空文字）の既存データは、現在のテーマカラーへフォールバックする。
     */
    static func color(from hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return AppColors.main }
        return color(from: hex)
    }

    /**
     Hex文字列から (red, green, blue) の生の成分を取り出す。
     不透明な合成色を自前で計算したい場合（例: AppColors.background）に使う。
     */
    static func rgbComponents(from hex: String) -> (red: Double, green: Double, blue: Double) {
        let cleanedHex = hex
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanedHex.count == 6 else {
            return (0.5, 0.5, 0.5)
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        return (red, green, blue)
    }
}
