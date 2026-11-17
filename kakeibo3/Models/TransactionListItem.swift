import Foundation
import Combine

// MARK: - 収支リスト表示用データ

struct TransactionListItem: Identifiable, Hashable {

    /// SwiftUI の ForEach が使う安定ID。"income-{uuid}" / "expense-{uuid}" / "transfer-{uuid}" 形式。
    /// 種別をプレフィックスで区別することで収入・支出・振替でIDが衝突しない。
    let id: String

    /// 元の SwiftData モデルの UUID。削除・編集時の検索キーとして使う。
    let sourceId: UUID

    let kind: TransactionKind
    let date: Date
    let category: String
    let method: String
    let memo: String
    let amount: Int
    let createdAt: Date
    let receiptImagePaths: [String]
    /// 固定費 or 定期収入から生成された取引かどうか
    let isRecurring: Bool
    /// 紐づく BankAccountData の UUID（nil = 銀行口座以外の支払い/受け取り方法、または振替）。
    /// ロック状態の表示（🔒）解決に使う。
    let bankAccountId: UUID?
    /// 紐づく BookData の UUID（nil = 振替・前月繰越など帳簿の対象外）。
    /// 編集時に帳簿間を移動させないため、元の値をそのまま引き継ぐのに使う。
    let bookId: UUID?
    /// ゴミ箱に入れた日時（nil = ゴミ箱に入っていない）。ゴミ箱画面での並び替え・表示に使う。
    let trashedAt: Date?
}

// MARK: - ファクトリ

extension TransactionListItem {
    static func income(from data: IncomeData) -> TransactionListItem {
        TransactionListItem(
            id: "income-\(data.id)",
            sourceId: data.id,
            kind: .income,
            date: data.date,
            category: data.category,
            method: data.receiveMethod,
            memo: data.memo,
            amount: data.amount,
            createdAt: data.createdAt,
            receiptImagePaths: ReceiptImageHelper.decodePaths(data.receiptImagePath),
            isRecurring: data.recurringIncomeId != nil,
            bankAccountId: data.bankAccountId,
            bookId: data.bookId,
            trashedAt: data.trashedAt
        )
    }

    static func expense(from data: ExpenseData) -> TransactionListItem {
        TransactionListItem(
            id: "expense-\(data.id)",
            sourceId: data.id,
            kind: .expense,
            date: data.date,
            category: data.category,
            method: data.paymentMethod,
            memo: data.memo,
            amount: data.amount,
            createdAt: data.createdAt,
            receiptImagePaths: ReceiptImageHelper.decodePaths(data.receiptImagePath),
            isRecurring: data.fixedExpenseId != nil,
            bankAccountId: data.bankAccountId,
            bookId: data.bookId,
            trashedAt: data.trashedAt
        )
    }

    static func transfer(from data: TransferData) -> TransactionListItem {
        TransactionListItem(
            id: "transfer-\(data.id)",
            sourceId: data.id,
            kind: .transfer,
            date: data.date,
            category: "振替",
            method: "\(data.fromName) → \(data.toName)",
            memo: data.memo,
            amount: data.amount,
            createdAt: data.createdAt,
            receiptImagePaths: [],
            isRecurring: data.recurringTransferSettingId != nil,
            bankAccountId: nil,
            bookId: data.bookId,
            trashedAt: data.trashedAt
        )
    }

    /// SwiftData に保存しない表示専用の前月繰越アイテム。
    /// プラスなら収入、マイナスなら支出として kind を振り分けることで、
    /// TransactionRowComponent 側の背景色・文字色をそのまま（重複定義せず）流用できるようにする。
    static func carryover(firstDayOfMonth: Date, amount: Int) -> TransactionListItem {
        TransactionListItem(
            id: "carryover-virtual-\(firstDayOfMonth.timeIntervalSince1970)",
            sourceId: UUID(),
            kind: amount >= 0 ? .income : .expense,
            date: firstDayOfMonth,
            category: carryoverCategory,
            method: "",
            memo: "",
            amount: amount,
            // distantFuture にすることで同日内の先頭に表示される
            createdAt: Date.distantFuture,
            receiptImagePaths: [],
            isRecurring: false,
            bankAccountId: nil,
            bookId: nil,
            trashedAt: nil
        )
    }
}

// MARK: - 前月繰越カテゴリー名

extension TransactionListItem {
    /// 前月繰越アイテムを識別するカテゴリー名。
    /// SwiftData には保存しない表示専用アイテムの判別に使う。
    static let carryoverCategory = "前月繰越"
}

// MARK: - 収支リストの種類

enum TransactionKind: Hashable {
    case income
    case expense
    case transfer
}
