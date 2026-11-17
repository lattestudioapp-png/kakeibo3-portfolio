import SwiftUI

// MARK: - 支出 / 収入 / 振替切り替えバー

struct TransactionTypeSwitchView: View {
    @Binding var selectedType: String

    let expenseSetting: TransactionInputSetting
    let incomeSetting: TransactionInputSetting
    let onChange: (TransactionInputSetting) -> Void
    var showsTransfer: Bool = false
    var onTransferSelect: (() -> Void)? = nil
    var showsReceipt: Bool = false
    var onReceiptSelect: (() -> Void)? = nil
    var width: CGFloat = SegmentBarLayout.standard.width

    static let transferTypeName = "振替"
    static let receiptTypeName = "レシート"

    // レシートタップは選択状態を持たない一回限りのアクションのため、
    // selectedIndexの計算からは除外し、常に支出/収入/振替のいずれかを指す。
    private var receiptOffset: Int { showsReceipt ? 1 : 0 }

    private var selectedIndex: Int {
        if selectedType == expenseSetting.typeName { return receiptOffset + 0 }
        if selectedType == incomeSetting.typeName  { return receiptOffset + 1 }
        if showsTransfer && selectedType == Self.transferTypeName { return receiptOffset + 2 }
        return receiptOffset + 0
    }

    private var items: [String] {
        var names: [String] = showsTransfer
            ? [expenseSetting.typeName, incomeSetting.typeName, Self.transferTypeName]
            : [expenseSetting.typeName, incomeSetting.typeName]
        if showsReceipt { names.insert(Self.receiptTypeName, at: 0) }
        return names
    }

    var body: some View {
        AppSegmentControl(
            items: items,
            selectedIndex: selectedIndex,
            onSelect: { index in
                if showsReceipt && index == 0 {
                    onReceiptSelect?()
                    return
                }
                let adjustedIndex = index - receiptOffset
                if showsTransfer && adjustedIndex == 2 {
                    onTransferSelect?()
                } else {
                    let setting = adjustedIndex == 0 ? expenseSetting : incomeSetting
                    onChange(setting)
                }
            },
            width: width
        )
    }
}
