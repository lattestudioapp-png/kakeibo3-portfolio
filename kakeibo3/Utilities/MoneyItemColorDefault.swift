import Foundation

// MARK: - お金の管理データ（現金・クレジットカード・銀行口座など）の新規追加時デフォルト色
//
// カテゴリー追加時の初期色決定（CategoryRepository参照）と全く同じ考え方・同じ関数
// （CategoryColorPalette.nextDistinctColor）を使う。「同じ帳簿内で既に使われている色」を
// 種類をまたいで（現金・クレジットカード・銀行口座など「お金の管理」全体で）避けて次の色を
// 選ぶことで、似た色が連続して割り当てられないようにする。

enum MoneyItemColorDefault {
    /// 現金・クレジットカード・電子マネー・デビットカード・証券口座・暗号資産・その他
    /// （いずれも PaymentMethodSettingData）用。typeは呼び出し元の意図を示すだけで、
    /// 重複判定は種類をまたいで「お金の管理」全体（銀行口座も含む）に対して行う。
    static func nextColorHex(forPaymentMethodType type: String, bookId: UUID) -> String {
        CategoryColorPalette.nextDistinctColor(existingColors: usedColorsAcrossMoneyItems(bookId: bookId))
    }

    /// 銀行口座（BankAccountData）用。こちらも他の種類を含めた「お金の管理」全体で重複判定する。
    static func nextColorHexForBankAccount(bookId: UUID) -> String {
        CategoryColorPalette.nextDistinctColor(existingColors: usedColorsAcrossMoneyItems(bookId: bookId))
    }

    /// 現在の帳簿内で「お金の管理」に登録されている全データ（PaymentMethodSettingDataの
    /// 全種類 + BankAccountData）が使用中の色一覧。
    private static func usedColorsAcrossMoneyItems(bookId: UUID) -> [String] {
        let paymentColors = PaymentMethodSettingDataSync.fetchAll(bookId: bookId).compactMap(\.colorHex)
        let bankColors = BankAccountDataSync.fetchAll(bookId: bookId).compactMap(\.colorHex)
        return paymentColors + bankColors
    }

    // MARK: - 既存データへの色バックフィル（起動時に一度だけ実行）
    //
    // この機能が実装される前から存在するデータはcolorHexがnilのままのため、画面表示のたびに
    // ColorHexConverter.color(from:)がテーマカラーへフォールバックしてしまう（保存されないため
    // 一意色ではない）。起動時に一度だけ、colorHexが未設定の行にnextDistinctColorと同じロジックで
    // 色を確定・保存し、以後は表示のたびに色が変わらないようにする。colorHex == nilの行だけを
    // 対象にするため、複数回実行しても安全（すでに割り当て済みの行には触れない）。
    static func backfillMissingColorsIfNeeded() {
        let allPayments = PaymentMethodSettingDataSync.fetchAll()
        let allBanks = BankAccountDataSync.fetchAll()

        guard allPayments.contains(where: { $0.colorHex == nil })
            || allBanks.contains(where: { $0.colorHex == nil }) else { return }

        // 帳簿ごとに、既に色が確定している行の色一覧を先に集めておく
        var usedColorsByBook: [UUID: [String]] = [:]
        for p in allPayments {
            guard let bookId = p.bookId, let hex = p.colorHex else { continue }
            usedColorsByBook[bookId, default: []].append(hex)
        }
        for b in allBanks {
            guard let bookId = b.bookId, let hex = b.colorHex else { continue }
            usedColorsByBook[bookId, default: []].append(hex)
        }

        // 一覧の表示順（sortOrder→createdAt）と同じ順番で割り当てることで、
        // 通常の新規追加時と同じ見た目の並びになるようにする
        let unsetPayments = allPayments
            .filter { $0.colorHex == nil }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
        let unsetBanks = allBanks
            .filter { $0.colorHex == nil }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }

        for p in unsetPayments {
            let bookId = p.bookId ?? UUID()
            let newColor = CategoryColorPalette.nextDistinctColor(existingColors: usedColorsByBook[bookId] ?? [])
            var updated = p
            updated.colorHex = newColor
            usedColorsByBook[bookId, default: []].append(newColor)
            PaymentMethodSettingDataSync.update(updated)
        }
        for b in unsetBanks {
            let bookId = b.bookId ?? UUID()
            let newColor = CategoryColorPalette.nextDistinctColor(existingColors: usedColorsByBook[bookId] ?? [])
            var updated = b
            updated.colorHex = newColor
            usedColorsByBook[bookId, default: []].append(newColor)
            BankAccountDataSync.update(updated)
        }
    }
}
