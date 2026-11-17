import SwiftUI

// MARK: - 日付グループ化された取引リストの1セクション（見出し＋行）
//
// カレンダーの取引リスト（TransactionListComponent）と、
// 分析詳細画面（資産・カテゴリ・支払い方法）の取引リスト（AnalysisItemListCard）で
// 共通利用する。見た目・構造をここに集約し、両方の画面で常に同じスタイルになるようにする。

struct DateGroupedTransactionSection: View {
    // ロック中の支払い/受け取り方法に紐づく取引を非表示にするための判定用。
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    let date: Date
    let items: [TransactionListItem]
    @Binding var openItemID: UUID?
    var onTap: ((TransactionListItem) -> Void)? = nil
    let onDelete: (TransactionListItem) -> Void
    // 親のスクロールView側で縦ドラッグ中を検知して渡す。true の間はタップを無視する。
    var isDraggingList: Bool = false

    // ロック中の口座/支払い方法（クレジットカードは紐づく引き落とし口座のロックも連動）に
    // 紐づく取引は、リスト・分析から非表示にする。振替は対象外。
    // itemsは呼び出し元で既に選択中の帳簿に絞り込まれているため、その帳簿idで口座/支払い方法も絞り込む。
    private var visibleItems: [TransactionListItem] {
        let bookId = items.first?.bookId
        let bankAccounts = bankAccountsRaw.filter { $0.bookId == bookId }
        let paymentMethods = paymentMethodsRaw.filter { $0.bookId == bookId }
        return items.filter { item in
            guard item.kind != .transfer else { return true }
            return !DowngradeLockService.isMethodLocked(
                bankAccountId: item.bankAccountId, methodName: item.method,
                bankAccounts: bankAccounts, paymentMethods: paymentMethods
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "MM月dd日 (E)"
        return f
    }()

    private let dateHeaderHeight: CGFloat = 18
    private let dateHeaderFontSize: CGFloat = 12
    private let dateHeaderTextOpacity: Double = 0.75
    private let horizontalPadding: CGFloat = 25
    private let dateHeaderBackgroundColor = Color(red: 0.99, green: 0.97, blue: 0.90)
    private let dateHeaderBorderWidth: CGFloat = 0.6
    private let dateHeaderBorderOpacity: Double = 0.25
    private let dateHeaderBorderColor = Color.gray
    private let itemDividerOpacity: Double = 0.20

    var body: some View {
        if !visibleItems.isEmpty {
            VStack(spacing: 0) {
                dateHeader

                ForEach(visibleItems) { item in
                    if item.category == TransactionListItem.carryoverCategory {
                        // 前月繰越は編集・削除不可（タップなし・スワイプなし）
                        TransactionRowComponent(item: item)
                    } else {
                        SwipeableTransactionRow(
                            openItemID: $openItemID,
                            itemID: item.sourceId,
                            onTap: {
                                guard !isDraggingList else { return }
                                onTap?(item)
                            },
                            onDelete: { onDelete(item) }
                        ) {
                            TransactionRowComponent(item: item)
                        }
                    }

                    if visibleItems.last?.id != item.id {
                        itemDivider
                    }
                }
            }
        }
    }

    // MARK: - 日付ヘッダー

    private var dateHeader: some View {
        Text(Self.dateFormatter.string(from: date))
            .font(.system(size: dateHeaderFontSize, weight: .regular))
            .foregroundStyle(Color.black.opacity(dateHeaderTextOpacity))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: dateHeaderHeight)
            .padding(.horizontal, horizontalPadding)
            .background(dateHeaderBackgroundColor)
            .overlay(alignment: .top) { dateHeaderBorder }
            .overlay(alignment: .bottom) { dateHeaderBorder }
    }

    private var dateHeaderBorder: some View {
        Rectangle()
            .fill(dateHeaderBorderColor.opacity(dateHeaderBorderOpacity))
            .frame(height: dateHeaderBorderWidth)
    }

    // MARK: - 区切り線

    private var itemDivider: some View {
        Divider()
            .background(Color.gray.opacity(itemDividerOpacity))
    }
}
