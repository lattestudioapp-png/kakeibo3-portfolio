import SwiftUI
import Combine

// MARK: - テーマカラー管理

final class ThemeManager: ObservableObject {
    @Published private(set) var selectedThemeColorHex: String

    init() {
        selectedThemeColorHex = UserDefaults.standard.string(forKey: AppColors.themeColorStorageKey)
            ?? AppColors.defaultThemeHex
    }

    func setColor(hex: String) {
        UserDefaults.standard.set(hex, forKey: AppColors.themeColorStorageKey)
        selectedThemeColorHex = hex
    }

    var mainColor: Color {
        ColorHexConverter.color(from: selectedThemeColorHex)
    }

    var backgroundColor: Color {
        mainColor.opacity(0.05)
    }
}
