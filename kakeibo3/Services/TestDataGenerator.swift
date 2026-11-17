import Foundation

// MARK: - テストデータ一括作成・削除（期間指定可能）

struct TestDataGenerator {

    private static let cal = Calendar.current

    // MARK: - 確定的疑似乱数

    private static func h(_ a: Int, _ b: Int = 0) -> Int {
        let v = UInt64(bitPattern: Int64(a) &* 1664525 &+ Int64(b) &* 22695477 &+ 1013904223)
        return Int(bitPattern: UInt(v & 0x7FFF_FFFF))
    }

    private static func pick(_ a: Int, _ b: Int = 0, lo: Int, hi: Int) -> Int {
        guard hi > lo else { return lo }
        return lo + h(a, b) % (hi - lo + 1)
    }

    // MARK: - 日付ヘルパー

    private static func md(_ d: Int, in ms: Date) -> Date {
        var comps = cal.dateComponents([.year, .month], from: ms)
        comps.day = min(d, cal.range(of: .day, in: .month, for: ms)!.count)
        return cal.date(from: comps)!
    }

    // MARK: - 作成エントリポイント

    static func createTestData(monthsCount: Int = 12) throws {
        try deleteTestData()

        let today = Date()
        let testStart = cal.date(from: cal.dateComponents(
            [.year, .month],
            from: cal.date(byAdding: .month, value: -(monthsCount - 1), to: today)!
        ))!

        var months: [Date] = []
        for i in 0..<monthsCount {
            months.append(cal.date(byAdding: .month, value: i, to: testStart)!)
        }

        // ---- 1. 銀行口座 ----
        var smbc  = makeBank("三井住友銀行", initial: 300_000, order: 1, pay: true,  receive: true)
        var nanto = makeBank("南都銀行",     initial: 120_000, order: 2, pay: true,  receive: true)
        var sbi   = makeBank("SBI証券",      initial: 200_000, order: 3, pay: false, receive: false)

        // 初期残高収入
        let smbcInc = makeIncome(300_000, date: testStart, method: "三井住友銀行", cat: "初期残高", bankId: smbc.id)
        smbc.initialBalanceIncomeId = smbcInc.id
        BankAccountDataSync.update(smbc)
        let nantoInc = makeIncome(120_000, date: testStart, method: "南都銀行", cat: "初期残高", bankId: nanto.id)
        nanto.initialBalanceIncomeId = nantoInc.id
        BankAccountDataSync.update(nanto)
        let sbiInc = makeIncome(200_000, date: testStart, method: "SBI証券", cat: "初期残高", bankId: sbi.id)
        sbi.initialBalanceIncomeId = sbiInc.id
        BankAccountDataSync.update(sbi)

        // ---- 2. クレジットカード ----
        let smCard  = makeCard("三井住友カード", closing: 31, withdrawal: 26, bankId: smbc.id,  order: 1)
        let rakuten = makeCard("楽天カード",     closing: 15, withdrawal: 27, bankId: nanto.id, order: 2)

        // ---- 3. その他 ----
        let cash   = makeOther("現金",  type: "cash",           initial: 20_000,  order: 3, pay: true,  receive: false)
        let paypay = makeOther("PayPay",type: "electronicMoney",initial:  8_000,  order: 4, pay: true,  receive: true)
        let suica  = makeOther("Suica", type: "electronicMoney",initial:  5_000,  order: 5, pay: true,  receive: false)
        makeOther("NISA",  type: "other",          initial: 100_000, order: 6, pay: false, receive: false)

        // ---- 4. 固定費設定 ----
        let fRent     = makeFixed("家賃",    amount: 70_000, cat: "住居",  payType: "bankAccount",    payId: smbc.id,   day: 27, start: testStart)
        let fPhone    = makeFixed("スマホ代", amount:  8_000, cat: "通信",  payType: "paymentMethod",  payId: smCard.id,  day: 25, start: testStart)
        let fNetflix  = makeFixed("Netflix",  amount:  1_490, cat: "サブスク",payType: "paymentMethod", payId: rakuten.id, day: 10, start: testStart)
        let fInsurance = makeFixed("保険",   amount:  5_000, cat: "保険",  payType: "bankAccount",    payId: nanto.id,  day: 15, start: testStart)

        // ---- 5. 定期収入設定 ----
        let rSalary   = makeRecurring("給料",    amount: 200_000, cat: "給料", recType: "bankAccount",   recId: smbc.id,   day: 25, start: testStart)
        let rRemit    = makeRecurring("仕送り",   amount:  30_000, cat: "仕送り", recType: "bankAccount",recId: nanto.id,  day:  1, start: testStart)
        let rFreelance = makeRecurring("副業収入", amount: 45_000, cat: "副業", recType: "paymentMethod", recId: paypay.id, day: 20, start: testStart)

        // ---- 副業収入の月別変動 ----
        let freelanceAmounts = [42000, 35000, 55000, 38000, 48000, 32000, 58000, 45000, 37000, 51000, 44000, 60000]

        // ---- 6〜9. 指定月数分 ----
        for (mi, ms) in months.enumerated() {
            let yr = cal.component(.year,  from: ms)
            let mo = cal.component(.month, from: ms)

            // 6. 定期収入履歴（recurringIncomeId 付き → カレンダーでマーク表示）
            addIncome(200_000,             date: md(25, in: ms), method: "三井住友銀行", cat: "給料", bankId: smbc.id,  recId: rSalary.id)
            addIncome(30_000,              date: md( 1, in: ms), method: "南都銀行",     cat: "仕送り", bankId: nanto.id, recId: rRemit.id)
            addIncome(freelanceAmounts[mi % freelanceAmounts.count],date: md(20, in: ms), method: "PayPay",       cat: "副業", bankId: nil,      recId: rFreelance.id)

            // 7. 固定費履歴（fixedExpenseId 付き → カレンダーでマーク表示）
            addExpense(70_000, date: md(27, in: ms), method: "三井住友銀行", cat: "住居",  bankId: smbc.id,  fixedId: fRent.id)
            addExpense( 8_000, date: md(25, in: ms), method: "三井住友カード",cat: "通信",  bankId: nil,      fixedId: fPhone.id)
            addExpense( 1_490, date: md(10, in: ms), method: "楽天カード",   cat: "サブスク",bankId: nil,    fixedId: fNetflix.id)
            addExpense( 5_000, date: md(15, in: ms), method: "南都銀行",     cat: "保険",  bankId: nanto.id, fixedId: fInsurance.id)

            // 8. 変動支出
            addVariableExpenses(mi: mi, mo: mo, ms: ms)

            // 9. 予算
            addBudget(year: yr, month: mo, mi: mi)
        }

        SnapshotRebuildQueue.shared.requestRebuild()
    }

    // MARK: - 変動支出

    private static func addVariableExpenses(mi: Int, mo: Int, ms: Date) {

        // 食費（10件 / 月）
        let foodDays   = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
        let foodMethods = ["PayPay", "三井住友カード", "現金", "PayPay", "三井住友カード",
                           "PayPay", "現金", "三井住友カード", "PayPay", "現金"]
        for (i, d) in foodDays.enumerated() {
            addExpense(pick(mi, i,    lo: 1000, hi: 3800), date: md(d, in: ms),
                       method: foodMethods[i], cat: "食費", bankId: nil, fixedId: nil)
        }

        // 外食（4件 / 月）
        let diningData: [(Int, Int, String)] = [
            (pick(mi, 10, lo: 1000, hi: 4000),  4, "楽天カード"),
            (pick(mi, 11, lo: 1500, hi: 5000), 13, "PayPay"),
            (pick(mi, 12, lo: 1200, hi: 4000), 22, "楽天カード"),
            (pick(mi, 13, lo: 1000, hi: 3500), 29, "現金"),
        ]
        for (amt, d, meth) in diningData {
            addExpense(amt, date: md(d, in: ms), method: meth, cat: "外食", bankId: nil, fixedId: nil)
        }

        // 日用品（4件 / 月。3・4月は増量）
        let dailyData: [(Int, Int, String)] = [
            (pick(mi, 20, lo:  600, hi: 2500),  3, "PayPay"),
            (pick(mi, 21, lo: 1000, hi: 3500),  7, "PayPay"),
            (pick(mi, 22, lo: 1000, hi: 3800), 16, "楽天カード"),
            (pick(mi, 23, lo:  600, hi: 2200), 25, "PayPay"),
        ]
        for (amt, d, meth) in dailyData {
            let bonus = (mo == 3 || mo == 4) ? pick(mi, d + 100, lo: 500, hi: 1800) : 0
            addExpense(amt + bonus, date: md(d, in: ms), method: meth, cat: "日用品", bankId: nil, fixedId: nil)
        }

        // 交通費（7件 / 月）Suica
        let transDays = [2, 5, 9, 15, 21, 27, 28]
        for (i, d) in transDays.enumerated() {
            addExpense(pick(mi, 30 + i, lo: 400, hi: 1200), date: md(d, in: ms),
                       method: "Suica", cat: "交通費", bankId: nil, fixedId: nil)
        }

        // 娯楽（12月・8月は3件、偶数月は2件、それ以外は1件）
        let entertCount = (mo == 12 || mo == 8) ? 3 : (mi % 2 == 0 ? 2 : 1)
        let entertDays   = [8, 18, 26]
        let entertMethods = ["三井住友カード", "楽天カード", "三井住友カード"]
        for i in 0..<entertCount {
            let base  = pick(mi, 40 + i, lo: 1500, hi: 7000)
            let bonus = (mo == 12 || mo == 8) ? pick(mi, 50 + i, lo: 1000, hi: 3000) : 0
            addExpense(base + bonus, date: md(entertDays[i % 3], in: ms),
                       method: entertMethods[i % 3], cat: "娯楽", bankId: nil, fixedId: nil)
        }

        // 衣服・美容（2〜3ヶ月に1回）
        if mi % 3 == 0 || (mi % 2 == 1 && mi % 4 == 1) {
            addExpense(pick(mi, 55, lo: 5000, hi: 18000), date: md(19, in: ms),
                       method: "楽天カード", cat: "衣服・美容", bankId: nil, fixedId: nil)
        }

        // 医療（3〜4ヶ月に1回）
        if mi % 4 == 1 || mi % 4 == 3 {
            addExpense(pick(mi, 60, lo: 1000, hi: 5000), date: md(6, in: ms),
                       method: "現金", cat: "医療", bankId: nil, fixedId: nil)
        }

        // 交際費（月1〜3件。12月・1月は増量）
        let socialCount   = (mo == 12 || mo == 1) ? 3 : 1 + mi % 3
        let socialDays    = [6, 15, 25]
        let socialMethods = ["PayPay", "現金", "楽天カード"]
        for i in 0..<min(socialCount, 3) {
            let base  = pick(mi, 70 + i, lo: 2000, hi: 7000)
            let bonus = (mo == 12 || mo == 1) ? pick(mi, 80 + i, lo: 1000, hi: 3000) : 0
            addExpense(base + bonus, date: md(socialDays[i % 3], in: ms),
                       method: socialMethods[i % 3], cat: "交際費", bankId: nil, fixedId: nil)
        }
    }

    // MARK: - 予算

    private static func addBudget(year: Int, month: Int, mi: Int) {
        var cats: [(String, Int)] = [
            ("食費",     35_000),
            ("外食",     15_000),
            ("日用品",   10_000),
            ("交通費",    8_000),
            ("娯楽",     15_000),
            ("衣服・美容",10_000),
            ("医療",      5_000),
            ("通信",      8_000),
            ("住居",     70_000),
            ("水道光熱", 12_000),
            ("サブスク",  2_000),
            ("保険",      5_000),
            ("交際費",   10_000),
            ("教育",      5_000),
            ("その他",   10_000),
        ]
        cats = cats.map { (cat, amt) in
            var a = amt
            switch cat {
            case "娯楽":     if month == 12 { a = 25_000 } else if month == 8 { a = 22_000 }
            case "交際費":   if month == 12 { a = 18_000 } else if month == 1 { a = 15_000 }
            case "日用品":   if month == 3 || month == 4 { a = 14_000 }
            default: break
            }
            return (cat, a)
        }
        for (cat, amt) in cats {
            var b = BudgetData(year: year, month: month, categoryName: cat, amount: amt)
            b.isTestData = true
            BudgetDataSync.insert(b)
        }
    }

    // MARK: - ヘルパー：モデル生成

    @discardableResult
    private static func makeBank(_ name: String, initial: Int, order: Int, pay: Bool, receive: Bool) -> BankAccountData {
        var b = BankAccountData(accountName: name, initialBalance: Double(initial))
        b.showAsPaymentMethod = pay
        b.showAsReceiveMethod = receive
        b.showInAnalysis = true
        b.sortOrder = order
        b.isTestData = true
        BankAccountDataSync.insert(b)
        return b
    }

    @discardableResult
    private static func makeCard(_ name: String, closing: Int, withdrawal: Int, bankId: UUID, order: Int) -> PaymentMethodSettingData {
        var c = PaymentMethodSettingData(
            methodName: name, type: PaymentMethodType.creditCard.rawValue,
            closingDay: closing, withdrawalDay: withdrawal,
            withdrawalBankAccountId: bankId, sortOrder: order
        )
        c.showInInputPicker = true
        c.showInAnalysis = true
        c.isTestData = true
        PaymentMethodSettingDataSync.insert(c)
        return c
    }

    @discardableResult
    private static func makeOther(_ name: String, type: String, initial: Int, order: Int, pay: Bool, receive: Bool) -> PaymentMethodSettingData {
        var m = PaymentMethodSettingData(methodName: name, type: type, sortOrder: order)
        m.isAsset = true
        m.assetInitialBalance = Double(initial)
        m.showInInputPicker = pay
        m.useForReceive = receive
        m.showInAnalysis = true
        m.isTestData = true

        // 初期残高を income エントリとして記録（bankSummaries と同様の方式）
        if initial > 0 {
            let now = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
            var inc = IncomeData(amount: initial, date: now, receiveMethod: name, category: "初期残高", memo: "", bankAccountId: nil)
            inc.isTestData = true
            IncomeDataSync.insert(inc)
            m.assetInitialBalanceIncomeId = inc.id
        }
        PaymentMethodSettingDataSync.insert(m)
        return m
    }

    @discardableResult
    private static func makeFixed(_ name: String, amount: Int, cat: String, payType: String, payId: UUID, day: Int, start: Date) -> FixedExpenseData {
        var f = FixedExpenseData(name: name, amount: amount, categoryName: cat,
                                  paymentMethodType: payType, paymentMethodId: payId,
                                  dayOfMonth: day, startDate: start, memo: "テスト用")
        f.isTestData = true
        FixedExpenseDataSync.insert(f)
        return f
    }

    @discardableResult
    private static func makeRecurring(_ name: String, amount: Int, cat: String, recType: String, recId: UUID, day: Int, start: Date) -> RecurringIncomeData {
        var r = RecurringIncomeData(name: name, amount: amount, categoryName: cat,
                                     receiveMethodType: recType, receiveMethodId: recId,
                                     dayOfMonth: day, startDate: start, memo: "テスト用")
        r.isTestData = true
        RecurringIncomeDataSync.insert(r)
        return r
    }

    @discardableResult
    private static func makeIncome(_ amount: Int, date: Date, method: String, cat: String, bankId: UUID?) -> IncomeData {
        var d = IncomeData(amount: amount, date: date, receiveMethod: method, category: cat, memo: "", bankAccountId: bankId)
        d.isTestData = true
        IncomeDataSync.insert(d)
        return d
    }

    // 定期収入履歴（recurringIncomeId 付き）
    private static func addIncome(_ amount: Int, date: Date, method: String, cat: String, bankId: UUID?, recId: UUID) {
        var d = IncomeData(amount: amount, date: date, receiveMethod: method, category: cat, memo: "", bankAccountId: bankId)
        d.recurringIncomeId = recId
        d.isTestData = true
        IncomeDataSync.insert(d)
    }

    // 固定費履歴（fixedExpenseId 付き）、または通常支出
    private static func addExpense(_ amount: Int, date: Date, method: String, cat: String, bankId: UUID?, fixedId: UUID?) {
        var d = ExpenseData(amount: amount, date: date, paymentMethod: method, category: cat, memo: "", bankAccountId: bankId)
        d.fixedExpenseId = fixedId
        d.isTestData = true
        ExpenseDataSync.insert(d)
    }

    // MARK: - 削除

    static func deleteTestData() throws {
        for account in BankAccountDataSync.fetchAll() where account.isTestData {
            BankAccountDataSync.delete(id: account.id)
        }
        for method in PaymentMethodSettingDataSync.fetchAll() where method.isTestData {
            PaymentMethodSettingDataSync.delete(id: method.id)
        }
        for fixedExpense in FixedExpenseDataSync.fetchAll() where fixedExpense.isTestData {
            FixedExpenseDataSync.delete(id: fixedExpense.id)
        }
        for recurringIncome in RecurringIncomeDataSync.fetchAll() where recurringIncome.isTestData {
            RecurringIncomeDataSync.delete(id: recurringIncome.id)
        }
        for expense in ExpenseDataSync.fetchAll() where expense.isTestData {
            ExpenseDataSync.delete(id: expense.id)
        }
        for income in IncomeDataSync.fetchAll() where income.isTestData {
            IncomeDataSync.delete(id: income.id)
        }
        for budget in BudgetDataSync.fetchAll() where budget.isTestData {
            BudgetDataSync.delete(id: budget.id)
        }
        SnapshotRebuildQueue.shared.requestRebuild()
    }
}
