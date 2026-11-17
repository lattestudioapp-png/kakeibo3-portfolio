import SwiftUI

struct BudgetSettingView: View {
    let year: Int
    let month: Int

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var budgetDataObserver = BudgetDataSync.observer()
    private var allBudgetDataRaw: [BudgetData] { budgetDataObserver.items }
    @StateObject private var recurringBudgetDataObserver = RecurringBudgetDataSync.observer()
    private var allRecurringBudgetDataRaw: [RecurringBudgetData] { recurringBudgetDataObserver.items }
    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var expenseDataObserver = ExpenseDataSync.observer()
    private var allExpenseDataRaw: [ExpenseData] { expenseDataObserver.items }

    private var allBudgetData: [BudgetData] {
        allBudgetDataRaw.filter { $0.bookId == currentBookId }
    }
    private var allRecurringBudgetData: [RecurringBudgetData] {
        allRecurringBudgetDataRaw.filter { $0.bookId == currentBookId }
    }
    private var categoryDataList: [CategoryData] {
        categoryDataListRaw.filter { $0.bookId == currentBookId }
    }
    private var allExpenseData: [ExpenseData] {
        allExpenseDataRaw.filter { $0.bookId == currentBookId }
    }

    @State private var inputAmounts: [String: String] = [:]
    @State private var recurringEnabled: [String: Bool] = [:]
    @State private var recurringAmounts: [String: String] = [:]

    private enum BudgetAmountField: Hashable {
        case current(String)
        case recurring(String)
    }

    @State private var activeAmountField: BudgetAmountField?
    @State private var isAmountKeyboardPresented = false

    // 数字キーボードでの入力のたびにbody全体が再評価され、その中で以前は
    // cachedExpenseCategoryNamesが毎回allExpenseData（全支出履歴）をmapし直していた。
    // カテゴリー一覧はcategoryDataList/allExpenseDataが変化した時だけ再計算すればよいため、
    // @Stateにキャッシュして.onAppear/.onChangeでのみ更新する。
    @State private var cachedExpenseCategoryNames: [String] = []

    private var activeAmountBinding: Binding<String> {
        Binding(
            get: {
                switch activeAmountField {
                case .current(let name): return inputAmounts[name] ?? ""
                case .recurring(let name): return recurringAmounts[name] ?? ""
                case nil: return ""
                }
            },
            set: { newValue in
                switch activeAmountField {
                case .current(let name): inputAmounts[name] = newValue
                case .recurring(let name): recurringAmounts[name] = newValue
                case nil: break
                }
            }
        )
    }

    private var thisMonthBudgets: [BudgetData] {
        allBudgetData.filter { $0.year == year && $0.month == month }
    }

    // データ変更検知キー（.onChangeの変化検知にのみ使用。集計には使わない）
    private var expenseCategoryVersionKey: String {
        let expenseCats = categoryDataList.filter { $0.type == "支出" }
        let categoryPart = expenseCats.sorted { $0.sortOrder < $1.sortOrder }.map { $0.name }.joined(separator: "|")
        return "\(allExpenseData.count)-\(categoryPart)"
    }

    private func rebuildExpenseCategoryNames() {
        let expenseCats = categoryDataList.filter { $0.type == "支出" && !$0.isSuspended }
        var names = expenseCats.sorted { $0.sortOrder < $1.sortOrder }.map { $0.name }
        let nameSet = Set(names)
        let allUsedCategories = Set(allExpenseData.map { $0.category })
        let extraNames = allUsedCategories.subtracting(nameSet)
        names.append(contentsOf: extraNames.sorted())
        cachedExpenseCategoryNames = names
    }

    private var monthTitle: String { "\(year)年\(month)月" }

    var body: some View {
        ZStack {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text(monthTitle)
                        .font(AppFonts.body)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    actionButtonsSection
                        .padding(.bottom, 24)

                    if cachedExpenseCategoryNames.isEmpty {
                        Text("支出カテゴリーがありません")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(cachedExpenseCategoryNames.enumerated()),
                                id: \.element
                            ) { index, name in
                                categoryInputRow(name: name)
                                if index < cachedExpenseCategoryNames.count - 1 {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppColors.line, lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(AppColors.sheetBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("予算設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.main)
                }
            }
        }
        .onAppear {
            rebuildExpenseCategoryNames()
            initializeInputAmounts()
        }
        .onChange(of: expenseCategoryVersionKey) { _, _ in
            rebuildExpenseCategoryNames()
        }

        if isAmountKeyboardPresented {
            SheetAmountKeyboardContainer(amountText: activeAmountBinding, isPresented: $isAmountKeyboardPresented)
        }
        }
        .animation(.easeOut(duration: 0.25), value: isAmountKeyboardPresented)
    }

    private var actionButtonsSection: some View {
        Button(action: copyFromPreviousMonth) {
            Text("前月の予算をコピー")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.main)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.main.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func categoryInputRow(name: String) -> some View {
        let isRecurring = recurringEnabled[name] == true
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.75))
                    Text("今月のみ")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.38))
                }
                Spacer()
                HStack(spacing: 2) {
                    Text((inputAmounts[name]?.isEmpty ?? true) ? "0" : inputAmounts[name]!)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle((inputAmounts[name]?.isEmpty ?? true) ? Color.black.opacity(0.35) : Color.black.opacity(0.75))

                    if isAmountKeyboardPresented && activeAmountField == .current(name) {
                        BlinkingCursorView(height: 18)
                    }
                }
                .frame(width: 110, alignment: .trailing)
                Text("円")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                activeAmountField = .current(name)
                isAmountKeyboardPresented = true
            }

            HStack(spacing: 8) {
                Text("毎月設定")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.55))
                Toggle("", isOn: Binding(
                    get: { recurringEnabled[name] ?? false },
                    set: { recurringEnabled[name] = $0 }
                ))
                .labelsHidden()
                .tint(Color(red: 0.2, green: 0.48, blue: 0.78))

                Spacer()

                if isRecurring {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Text((recurringAmounts[name]?.isEmpty ?? true) ? "0" : recurringAmounts[name]!)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14))
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 0.2, green: 0.48, blue: 0.78))

                            if isAmountKeyboardPresented && activeAmountField == .recurring(name) {
                                BlinkingCursorView(height: 16, color: Color(red: 0.2, green: 0.48, blue: 0.78))
                            }
                        }
                        .frame(width: 110, alignment: .trailing)
                        Text("円")
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.38))
                    }
                    .frame(width: 140, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeAmountField = .recurring(name)
                        isAmountKeyboardPresented = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private func initializeInputAmounts() {
        for budget in thisMonthBudgets where budget.amount > 0 {
            inputAmounts[budget.categoryName] = "\(budget.amount)"
        }
        for recurring in allRecurringBudgetData where recurring.isEnabled && recurring.amount > 0 {
            recurringAmounts[recurring.categoryName] = "\(recurring.amount)"
            recurringEnabled[recurring.categoryName] = true
        }
    }

    // year/monthは会計期間ラベルのため、「前月」はラベルの単純な-1ではなく、
    // 一度anchorへ逆引きしてから暦月単位で1つ前に進め、そのanchorのラベルを使う
    // （通常はlabel==anchorなので単純な-1と一致するが、年月表示設定次第でズレることがある）。
    private func copyFromPreviousMonth() {
        let anchor = AccountingMonthCalculator.anchor(forLabelYear: year, labelMonth: month)
        let prevAnchor = AccountingMonthCalculator.adjacentAnchor(year: anchor.year, month: anchor.month, offset: -1)
        guard let prevRange = AccountingMonthCalculator.range(anchorYear: prevAnchor.year, anchorMonth: prevAnchor.month) else { return }
        let prevBudgets = allBudgetData.filter { $0.year == prevRange.labelYear && $0.month == prevRange.labelMonth }
        for budget in prevBudgets where budget.amount > 0 {
            inputAmounts[budget.categoryName] = "\(budget.amount)"
        }
    }

    private func save() {
        for name in cachedExpenseCategoryNames {
            let amount = Int(inputAmounts[name] ?? "") ?? 0
            let existing = thisMonthBudgets.first { $0.categoryName == name }
            if amount > 0 {
                if var existing {
                    existing.amount = amount
                    existing.updatedAt = Date()
                    BudgetDataSync.update(existing)
                } else {
                    var budget = BudgetData(year: year, month: month, categoryName: name, amount: amount)
                    budget.bookId = currentBookId
                    BudgetDataSync.insert(budget)
                }
            } else if let existing {
                BudgetDataSync.delete(id: existing.id)
            }

            let recurringAmount = Int(recurringAmounts[name] ?? "") ?? 0
            let isRecurring = recurringEnabled[name] == true
            let existingRecurring = allRecurringBudgetData.first { $0.categoryName == name }
            if isRecurring && recurringAmount > 0 {
                if var existingRecurring {
                    existingRecurring.amount = recurringAmount
                    existingRecurring.isEnabled = true
                    existingRecurring.updatedAt = Date()
                    RecurringBudgetDataSync.update(existingRecurring)
                } else {
                    var recurring = RecurringBudgetData(categoryName: name, amount: recurringAmount)
                    recurring.bookId = currentBookId
                    RecurringBudgetDataSync.insert(recurring)
                }
            } else if let existingRecurring {
                RecurringBudgetDataSync.delete(id: existingRecurring.id)
            }
        }
        dismiss()
    }
}
