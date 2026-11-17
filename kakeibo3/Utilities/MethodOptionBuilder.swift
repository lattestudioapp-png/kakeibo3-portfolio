import Foundation

// MARK: - 入力画面の支払い/受け取り方法ピッカーの1候補
//
// isLocked = true の場合、選択肢として表示はするが選べない（灰色表示）。
// クレジットカードは「カード自身」と「紐づく引き落とし口座」の両方が unlocked な場合のみ isLocked=false。

struct MethodOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isLocked: Bool
    let colorHex: String?
}

enum MethodOptionBuilder {

    // 支出: PaymentMethodSettingData + BankAccountData（showAsPaymentMethod が ON のみ）を sortOrder 順に統合
    static func expenseOptions(
        paymentMethods: [PaymentMethodSettingData],
        bankAccounts: [BankAccountData]
    ) -> [MethodOption] {
        typealias Entry = (option: MethodOption, sortOrder: Int, createdAt: Date)
        let regular: [Entry] = paymentMethods
            .filter { $0.isActive && $0.showInInputPicker }
            .map { m in
                (
                    option: MethodOption(id: m.id, name: m.methodName, isLocked: !isUsable(m, bankAccounts: bankAccounts), colorHex: m.colorHex),
                    sortOrder: m.sortOrder,
                    createdAt: m.createdAt
                )
            }
        let banks: [Entry] = bankAccounts
            .filter { $0.isActive && $0.showAsPaymentMethod }
            .map { b in
                (
                    option: MethodOption(id: b.id, name: b.accountName, isLocked: b.isLocked, colorHex: b.colorHex),
                    sortOrder: b.sortOrder,
                    createdAt: b.createdAt
                )
            }
        return (regular + banks)
            .sorted {
                $0.option.isLocked != $1.option.isLocked ? !$0.option.isLocked
                    : ($0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder)
            }
            .map { $0.option }
    }

    // 収入: PaymentMethodSettingData(useForReceive=true) + BankAccountData(showAsReceiveMethod) を sortOrder 順に統合
    static func incomeOptions(
        paymentMethods: [PaymentMethodSettingData],
        bankAccounts: [BankAccountData]
    ) -> [MethodOption] {
        typealias Entry = (option: MethodOption, sortOrder: Int, createdAt: Date)
        let regulars: [Entry] = paymentMethods
            .filter { $0.isActive && $0.useForReceive }
            .map { m in
                (
                    option: MethodOption(id: m.id, name: m.methodName, isLocked: !isUsable(m, bankAccounts: bankAccounts), colorHex: m.colorHex),
                    sortOrder: m.sortOrder,
                    createdAt: m.createdAt
                )
            }
        let banks: [Entry] = bankAccounts
            .filter { $0.isActive && $0.showAsReceiveMethod }
            .map { b in
                (
                    option: MethodOption(id: b.id, name: b.accountName, isLocked: b.isLocked, colorHex: b.colorHex),
                    sortOrder: b.sortOrder,
                    createdAt: b.createdAt
                )
            }
        return (regulars + banks)
            .sorted {
                $0.option.isLocked != $1.option.isLocked ? !$0.option.isLocked
                    : ($0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder)
            }
            .map { $0.option }
    }

    private static func isUsable(_ method: PaymentMethodSettingData, bankAccounts: [BankAccountData]) -> Bool {
        if method.type == PaymentMethodType.creditCard.rawValue {
            return DowngradeLockService.isCreditCardUsable(method, bankAccounts: bankAccounts)
        }
        return !method.isLocked
    }
}
