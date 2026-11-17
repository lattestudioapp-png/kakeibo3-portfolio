import SwiftUI
import Combine

// MARK: - 収支リスト1行分

/**
 収支リストの1行分を表示するComponent。

 表示内容:
 - 左側: カテゴリ名
 - カテゴリ横: 支払い方法 / 受け取り方法
 - 支払い方法 / 受け取り方法の右側: メモ
 - 右側: 金額

 メモは、金額に被らない範囲で自動的に省略される。
 */
struct TransactionRowComponent: View {

    // MARK: - 受け取るデータ

    /**
     表示する収支データ。
     IncomeData / ExpenseData を共通化した TransactionListItem を受け取る。
     */
    let item: TransactionListItem

    // MARK: - 見た目の設定

    /**
     1行の高さ。
     数字を大きくすると、行が縦に広くなる。
     */
    private let rowHeight: CGFloat = 42

    /**
     左右の余白。
     数字を大きくすると、文字が内側に寄る。
     */
    private let horizontalPadding: CGFloat = 25

    /**
     カテゴリ名と支払い方法/受け取り方法の間隔。
     */
    private let categoryMethodSpacing: CGFloat = 8

    /**
     支払い方法/受け取り方法とメモの間隔。
     */
    private let methodMemoSpacing: CGFloat = 4

    /**
     左側表示と金額の最低間隔。
     金額にメモが近づきすぎる場合はここを大きくする。
     */
    private let amountSpacing: CGFloat = 10

    // MARK: - カテゴリ文字設定

    /**
     カテゴリ名の文字色。
     */
    private let categoryBaseColor = Color.black

    /**
     カテゴリ名の文字の濃さ。
     0.0 に近いほど薄い。
     1.0 に近いほど濃い。
     */
    private let categoryTextOpacity: Double = 0.75

    // MARK: - 支払い方法 / 受け取り方法 文字設定

    /**
     支払い方法 / 受け取り方法の文字サイズ。
     カテゴリ名より小さくする。
     */
    private let methodFontSize: CGFloat = 11

    /**
     支払い方法 / 受け取り方法の文字の太さ。
     */
    private let methodFontWeight: Font.Weight = .regular

    /**
     支払い方法 / 受け取り方法の文字色。
     */
    private let methodBaseColor = Color.black

    /**
     支払い方法 / 受け取り方法の文字の濃さ。
     */
    private let methodTextOpacity: Double = 0.45

    /**
     支払い方法 / 受け取り方法を囲む背景を表示するか。
     true: 小さいラベルっぽく表示
     false: ただの文字として表示
     */
    private let showsMethodBackground: Bool = true

    /**
     支払い方法 / 受け取り方法ラベルの左右余白。
     */
    private let methodHorizontalPadding: CGFloat = 6

    /**
     支払い方法 / 受け取り方法ラベルの上下余白。
     */
    private let methodVerticalPadding: CGFloat = 2

    /**
     支払い方法 / 受け取り方法ラベルの背景の濃さ。
     */
    private let methodBackgroundOpacity: Double = 0.08

    // MARK: - メモ文字設定

    /**
     メモの文字サイズ。
     */
    private let memoFontSize: CGFloat = 14

    /**
     メモの文字の太さ。
     */
    private let memoFontWeight: Font.Weight = .regular

    /**
     メモの文字色。
     */
    private let memoBaseColor = Color.black

    /**
     メモの文字の濃さ。
     */
    private let memoTextOpacity: Double = 0.35

    /**
     メモを括弧付きで表示するか。
     true: （あああ）
     false: あああ
     */
    private let showsMemoParentheses: Bool = true

    // MARK: - 金額文字設定

    /**
     金額の文字色。
     */
    private let amountBaseColor = Color.black

    /**
     金額の文字の濃さ。
     */
    private let amountTextOpacity: Double = 0.65

    // MARK: - 背景色設定（設定画面「リスト表示色」でユーザーが変更可能）

    /**
     収入行の背景色設定。
     初期値: 薄い青。
     */
    @AppStorage(TransactionListColorSettings.incomeRowColorStorageKey)
    private var incomeRowColorRaw: String = TransactionListColorSettings.defaultIncomeRowColor.rawValue

    /**
     支出行の背景色設定。
     初期値: 薄い赤。
     */
    @AppStorage(TransactionListColorSettings.expenseRowColorStorageKey)
    private var expenseRowColorRaw: String = TransactionListColorSettings.defaultExpenseRowColor.rawValue

    private var incomeBackgroundColor: Color {
        (TransactionListRowColorOption(rawValue: incomeRowColorRaw) ?? TransactionListColorSettings.defaultIncomeRowColor).color
    }

    private var expenseBackgroundColor: Color {
        (TransactionListRowColorOption(rawValue: expenseRowColorRaw) ?? TransactionListColorSettings.defaultExpenseRowColor).color
    }

    /**
     振替行の背景色。
     薄いグレー（支出でも収入でもない移動のため中立色）。
     */
    private let transferBackgroundColor = Color(red: 0.96, green: 0.96, blue: 0.96)


    // MARK: - body

    var body: some View {
        HStack(spacing: amountSpacing) {
            leftContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            // 金額＋定期マークを内側HStackにまとめて右端に固定
            HStack(spacing: 4) {
                amountText
                    .fixedSize(horizontal: true, vertical: false)

                // 固定費 / 定期収入マーク（常に同幅を確保して金額の位置を揃える）
                if item.isRecurring {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .frame(width: recurringIconWidth)
                } else {
                    Color.clear.frame(width: recurringIconWidth)
                }
            }
            .layoutPriority(2)
        }
        .padding(.leading, horizontalPadding)
        .padding(.trailing, 6)
        .frame(height: rowHeight)
        .background(rowBackgroundColor)
    }

    // MARK: - 左側表示

    /**
     左側にカテゴリ名、支払い方法/受け取り方法、メモを並べる。

     金額側を優先するため、メモは残り幅に合わせて自動的に省略される。
     */
    private var leftContent: some View {
        HStack(spacing: categoryMethodSpacing) {
            categoryText
                .fixedSize(horizontal: true, vertical: false)

            if !item.method.isEmpty {
                methodText
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !displayMemo.isEmpty {
                memoText
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .layoutPriority(0)
    }

    // MARK: - カテゴリ名

    /**
     左側に表示するカテゴリ名。
     文字サイズ・太さ・濃さは設定変数で変更する。
     */
    private var categoryText: some View {
        Text(item.category)
            .font(AppFonts.rowTitle)
            .foregroundStyle(categoryBaseColor.opacity(categoryTextOpacity))
    }

    // MARK: - 支払い方法 / 受け取り方法

    /**
     カテゴリ名の横に表示する支払い方法 / 受け取り方法。

     例:
     - 現金
     - クレジット
     - 銀行
     - 振込
     */
    private var methodText: some View {
        Text(item.method)
            .font(.system(size: methodFontSize, weight: methodFontWeight))
            .foregroundStyle(methodBaseColor.opacity(methodTextOpacity))
            .padding(.horizontal, showsMethodBackground ? methodHorizontalPadding : 0)
            .padding(.vertical, showsMethodBackground ? methodVerticalPadding : 0)
            .background {
                if showsMethodBackground {
                    Capsule()
                        .fill(methodBaseColor.opacity(methodBackgroundOpacity))
                }
            }
    }

    // MARK: - メモ

    /**
     支払い方法 / 受け取り方法の右側に表示するメモ。

     lineLimit と truncationMode により、
     金額に被る前に「…」で省略される。
     */
    private var memoText: some View {
        Text(displayMemo)
            .font(.system(size: memoFontSize, weight: memoFontWeight))
            .foregroundStyle(memoBaseColor.opacity(memoTextOpacity))
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(-1)
    }

    /**
     表示用のメモ文字列を作る。
     空白だけなら表示しない。
     ここでは文字数で切らず、画面幅に合わせてSwiftUI側で省略させる。
     */
    private var displayMemo: String {
        let trimmedMemo = item.memo.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedMemo.isEmpty else {
            return ""
        }

        if showsMemoParentheses {
            return "（\(trimmedMemo)）"
        } else {
            return trimmedMemo
        }
    }

    // MARK: - 金額

    // 定期マーク（固定費 / 定期収入）アイコン幅（非定期行でも同幅を確保してレイアウトを揃える）
    private let recurringIconWidth: CGFloat = 16

    /**
     右側に表示する金額。

     fixedSize により、金額は省略されず必ず表示される。
     */
    private var amountText: some View {
        Text(formattedAmount)
            .font(AppFonts.listAmount)
            .monospacedDigit()
            .foregroundStyle(amountTextColor)
            .lineLimit(1)
    }

    // 前月繰越（マイナスの場合は符号付きで保持している）も含め、金額は常に絶対値で表示する。
    // 通常の収入/支出データの amount は元々正の値のみなので abs は実質no-op。
    private var formattedAmount: String {
        "\(Swift.abs(item.amount).formatted())円"
    }

    // MARK: - 金額テキスト色

    // 前月繰越も含め、金額の色分けは行わず通常行と同じ色にする
    // （収入/支出の区別は rowBackgroundColor（kind由来）だけで表現する）
    private var amountTextColor: Color {
        amountBaseColor.opacity(amountTextOpacity)
    }

    // MARK: - 背景色

    private var rowBackgroundColor: Color {
        switch item.kind {
        case .income:
            return incomeBackgroundColor
        case .expense:
            return expenseBackgroundColor
        case .transfer:
            return transferBackgroundColor
        }
    }
}
