import SwiftUI

// MARK: - カレンダー日付タップ時のアクションモーダル

struct CalendarDayActionView: View {
    let targetDate: Date
    /// 表示中の会計月の繰越セル日付（カレンダーグリッドと同じ基準。nilなら繰越は表示しない）
    let periodStartDate: Date?
    /// 表示中の会計月の繰越金額（CalendarViewModel.monthAggregateから渡される）
    let carryoverAmount: Int
    let onCreateNew: () -> Void
    let onSelectTransaction: (TransactionListItem) -> Void
    let onDismiss: () -> Void

    @StateObject private var incomeDataObserver: CoreDataListObserver<CDIncomeData, IncomeData>
    private var incomeDataList: [IncomeData] { incomeDataObserver.items }
    @StateObject private var expenseDataObserver: CoreDataListObserver<CDExpenseData, ExpenseData>
    private var expenseDataList: [ExpenseData] { expenseDataObserver.items }
    @StateObject private var transferDataObserver: CoreDataListObserver<CDTransferData, TransferData>
    private var transferDataList: [TransferData] { transferDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethodsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    private let bookId: UUID

    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == bookId }
    }
    private var paymentMethods: [PaymentMethodSettingData] {
        paymentMethodsRaw.filter { $0.bookId == bookId }
    }

    // ロック中の口座/支払い方法に紐づく取引を除いたリスト
    private var visibleIncomeDataList: [IncomeData] {
        DowngradeLockService.visibleIncomes(incomeDataList, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
    }
    private var visibleExpenseDataList: [ExpenseData] {
        DowngradeLockService.visibleExpenses(expenseDataList, bankAccounts: bankAccounts, paymentMethods: paymentMethods)
    }

    @AppStorage("showPreviousMonthCarryover") private var showCarryover = false

    // MARK: - Init
    //
    // 全期間の取引を@Queryで取得すると件数増加に比例して重くなるため、
    // targetDateの当日ぶんだけに絞った#Predicate付き@Queryにする
    // （このViewは日付タップのたびに新しいインスタンスとして生成されるため、
    // initで一度だけ範囲を確定させれば十分）。

    init(
        targetDate: Date,
        periodStartDate: Date?,
        carryoverAmount: Int,
        bookId: UUID,
        onCreateNew: @escaping () -> Void,
        onSelectTransaction: @escaping (TransactionListItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.targetDate = targetDate
        self.periodStartDate = periodStartDate
        self.carryoverAmount = carryoverAmount
        self.onCreateNew = onCreateNew
        self.onSelectTransaction = onSelectTransaction
        self.onDismiss = onDismiss
        self.bookId = bookId

        let cal = Calendar.current
        let day = cal.startOfDay(for: targetDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day

        let incomePredicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", day as NSDate, dayEnd as NSDate, bookId as CVarArg)
        _incomeDataObserver = StateObject(wrappedValue: IncomeDataSync.observer(matching: incomePredicate))
        let expensePredicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", day as NSDate, dayEnd as NSDate, bookId as CVarArg)
        _expenseDataObserver = StateObject(wrappedValue: ExpenseDataSync.observer(matching: expensePredicate))
        let transferPredicate = NSPredicate(format: "date >= %@ AND date < %@ AND bookId == %@", day as NSDate, dayEnd as NSDate, bookId as CVarArg)
        _transferDataObserver = StateObject(wrappedValue: TransferDataSync.observer(matching: transferPredicate))
    }

    private let calendarService = CalendarTransactionService()

    // MARK: - 定数

    private let backdropOpacity: Double = 0.45
    private let panelCornerRadius: CGFloat = 20
    private let panelHorizontalPadding: CGFloat = 28
    private let panelShadowRadius: CGFloat = 24

    private let headerVerticalPadding: CGFloat = 18

    private let createButtonHeight: CGFloat = 50
    private let createButtonCornerRadius: CGFloat = 14

    private let capsuleHeight: CGFloat = 50
    private let capsuleCornerRadius: CGFloat = 14
    private let capsuleFontSize: CGFloat = 15
    private let capsuleBackgroundColor = Color.gray.opacity(0.10)
    private let incomeAmountColor = AppColors.incomeColor
    private let expenseAmountColor = AppColors.expenseColor

    private let itemSpacing: CGFloat = 10
    private let contentHorizontalPadding: CGFloat = 18
    private let contentVerticalPadding: CGFloat = 14
    private let transactionListMaxHeight: CGFloat = 320

    private var transactionListHeight: CGFloat {
        let count = dailyItems.count
        guard count > 0 else { return 0 }
        let raw = CGFloat(count) * capsuleHeight
            + CGFloat(count - 1) * itemSpacing
        return min(raw, transactionListMaxHeight)
    }

    private let cancelVerticalPadding: CGFloat = 16

    // MARK: - 当日の取引一覧（収入・支出・振替・前月繰越）

    private var dailyItems: [TransactionListItem] {
        let cal = Calendar.current

        // incomeDataList/expenseDataList/transferDataListはinitの#Predicateで
        // 既にtargetDateの当日ぶんだけに絞られている
        let incomeItems = visibleIncomeDataList.map { TransactionListItem.income(from: $0) }
        let expenseItems = visibleExpenseDataList.map { TransactionListItem.expense(from: $0) }
        let transferItems = transferDataList.map { TransactionListItem.transfer(from: $0) }

        var items = (incomeItems + expenseItems + transferItems)
            .sorted { $0.createdAt > $1.createdAt }

        // 会計月の区切り日（periodStartDate。カレンダーグリッドの繰越セルと同じ日）をタップした
        // 時だけ、前月繰越を先頭に追加する（設定ON・表示専用）。
        if showCarryover, let periodStartDate, cal.isDate(targetDate, inSameDayAs: periodStartDate),
           carryoverAmount != 0 {
            items.insert(TransactionListItem.carryover(firstDayOfMonth: periodStartDate, amount: carryoverAmount), at: 0)
        }

        return items
    }

    // MARK: - body

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            panel
                .padding(.horizontal, panelHorizontalPadding)
        }
    }

    // MARK: - パネル

    private var panel: some View {
        VStack(spacing: 0) {
            dateHeader
            Divider()
            scrollableContent
            Divider()
            cancelButton
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .shadow(
            color: Color.black.opacity(0.18),
            radius: panelShadowRadius,
            x: 0,
            y: 8
        )
    }

    // MARK: - 日付ヘッダー

    private var dateHeader: some View {
        Text(formattedDate)
            .font(AppFonts.sectionTitle)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, headerVerticalPadding)
    }

    // MARK: - スクロール可能コンテンツ

    private var scrollableContent: some View {
        VStack(spacing: 0) {
            createNewButton
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.top, contentVerticalPadding)
                .padding(.bottom, dailyItems.isEmpty ? contentVerticalPadding : itemSpacing)

            if !dailyItems.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: itemSpacing) {
                        ForEach(dailyItems) { item in
                            transactionCapsule(item)
                                .frame(height: capsuleHeight)
                        }
                    }
                    .padding(.horizontal, contentHorizontalPadding)
                }
                .frame(height: transactionListHeight)
                .padding(.bottom, contentVerticalPadding)
            }
        }
    }

    // MARK: - 新規作成ボタン

    private var createNewButton: some View {
        Button { onCreateNew() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("新規作成")
                    .font(AppFonts.button)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: createButtonHeight)
            .background(AppColors.main)
            .clipShape(RoundedRectangle(cornerRadius: createButtonCornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 取引カプセル

    private let recurringIconWidth: CGFloat = 18

    private func transactionCapsule(_ item: TransactionListItem) -> some View {
        Button {
            guard item.category != TransactionListItem.carryoverCategory else { return }
            onSelectTransaction(item)
        } label: {
            HStack(spacing: 8) {
                Text(item.kind == .transfer ? item.method : item.category)
                    .font(.system(size: capsuleFontSize, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)

                Spacer()

                Text(capsuleFormattedAmount(item))
                    .font(.system(size: capsuleFontSize, weight: .regular))
                    .foregroundStyle(amountColor(for: item))
                    .lineLimit(1)
                    .fixedSize()

                if item.isRecurring {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .frame(width: recurringIconWidth)
                } else {
                    Color.clear
                        .frame(width: recurringIconWidth)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: capsuleHeight)
            .background(capsuleBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: capsuleCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func capsuleFormattedAmount(_ item: TransactionListItem) -> String {
        if item.category == TransactionListItem.carryoverCategory {
            let abs = Swift.abs(item.amount)
            let sign = item.amount >= 0 ? "+" : "-"
            return "\(sign)\(abs.formatted())円"
        }
        return calendarService.formatYen(item.amount)
    }

    private func amountColor(for item: TransactionListItem) -> Color {
        if item.category == TransactionListItem.carryoverCategory {
            return item.amount >= 0 ? incomeAmountColor : expenseAmountColor
        }
        switch item.kind {
        case .income:   return incomeAmountColor
        case .expense:  return expenseAmountColor
        case .transfer: return Color.black.opacity(0.50)
        }
    }

    // MARK: - キャンセルボタン

    private var cancelButton: some View {
        Button { onDismiss() } label: {
            Text("キャンセル")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, cancelVerticalPadding)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 日付フォーマット

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd (E)"
        return formatter.string(from: targetDate)
    }
}
