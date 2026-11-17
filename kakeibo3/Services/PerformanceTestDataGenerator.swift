import Foundation
import UIKit

// MARK: - 20年間のヘビーユーザーを想定した性能テストデータ生成
//
// TestDataGenerator（通常の動作確認用・数ヶ月〜数年分）とは別に、
// スナップショット化・検索・CSV・バックアップなど「データ量が増えた時に重くなりうる処理」を
// 実データに近いスケールで負荷測定するための専用ジェネレーター。
// 生成物にはすべて isTestData = true を付与し、通常のテストデータと同じ流儀で
// 安全に削除できるようにする（本番データには一切触れない）。

enum PerformanceTestDataGenerator {

    // MARK: - 生成結果サマリー（呼び出し側でUI表示・ログ出力に使う）

    struct Summary {
        var months = 0
        var bankAccounts = 0
        var creditCards = 0
        var otherMethods = 0
        var expenseCategories = 0
        var incomeCategories = 0
        var fixedExpenses = 0
        var recurringIncomes = 0
        var recurringTransfers = 0
        var expenseCount = 0
        var incomeCount = 0
        var transferCount = 0
        var photoCount = 0
        var elapsedSeconds: Double = 0

        var transactionCount: Int { expenseCount + incomeCount + transferCount }

        var description: String {
            """
            === 性能テストデータ生成完了（\(String(format: "%.1f", elapsedSeconds))秒） ===
            期間: \(months)ヶ月（約\(months / 12)年）
            銀行口座: \(bankAccounts) / クレジットカード: \(creditCards) / その他: \(otherMethods)
            支出カテゴリ: \(expenseCategories) / 収入カテゴリ: \(incomeCategories)
            固定費: \(fixedExpenses) / 定期収入: \(recurringIncomes) / 定期振替設定: \(recurringTransfers)
            取引件数: \(transactionCount)（支出\(expenseCount) / 収入\(incomeCount) / 振替\(transferCount)）
            添付写真: \(photoCount)枚
            """
        }
    }

    private static let cal = Calendar.current
    private static let monthsCount = 240 // 20年

    // 1トランザクションに溜め込みすぎないよう、この件数ごとにsaveする

    // MARK: - 確定的疑似乱数（TestDataGeneratorと同じ方式。再現性のため乱数は使わない）

    private static func h(_ a: Int, _ b: Int = 0, _ c: Int = 0) -> Int {
        let v = UInt64(bitPattern: Int64(a) &* 1664525 &+ Int64(b) &* 22695477 &+ Int64(c) &* 69069 &+ 1013904223)
        return Int(bitPattern: UInt(v & 0x7FFF_FFFF))
    }

    private static func pick(_ a: Int, _ b: Int = 0, _ c: Int = 0, lo: Int, hi: Int) -> Int {
        guard hi > lo else { return lo }
        return lo + h(a, b, c) % (hi - lo + 1)
    }

    private static func chance(_ a: Int, _ b: Int, _ c: Int, percent: Int) -> Bool {
        h(a, b, c) % 100 < percent
    }

    private static func md(_ d: Int, in ms: Date) -> Date {
        var comps = cal.dateComponents([.year, .month], from: ms)
        comps.day = min(d, cal.range(of: .day, in: .month, for: ms)!.count)
        return cal.date(from: comps)!
    }

    // MARK: - 生成エントリポイント

    static func generate() throws -> Summary {
        let overallStart = CFAbsoluteTimeGetCurrent()
        try deleteAll()

        var summary = Summary()
        summary.months = monthsCount

        let today = Date()
        let testStart = cal.date(from: cal.dateComponents(
            [.year, .month],
            from: cal.date(byAdding: .month, value: -(monthsCount - 1), to: today)!
        ))!

        var months: [Date] = []
        for i in 0..<monthsCount {
            months.append(cal.date(byAdding: .month, value: i, to: testStart)!)
        }

        // ---- 1. 銀行口座 6件 ----
        let bankNames: [(String, Int, Bool, Bool)] = [
            ("三井住友銀行", 450_000, true, true),
            ("みずほ銀行", 280_000, true, true),
            ("南都銀行", 150_000, true, true),
            ("楽天銀行", 320_000, true, true),
            ("ゆうちょ銀行", 200_000, true, true),
            ("SBI証券", 800_000, false, false),
        ]
        var banks: [BankAccountData] = []
        for (i, entry) in bankNames.enumerated() {
            let (name, initial, pay, receive) = entry
            var b = makeBank(name, initial: initial, order: i + 1, pay: pay, receive: receive)
            let inc = makeIncome(initial, date: testStart, method: name, cat: "初期残高", bankId: b.id)
            b.initialBalanceIncomeId = inc.id
            BankAccountDataSync.update(b)
            banks.append(b)
        }
        summary.bankAccounts = banks.count

        // ---- 2. クレジットカード 6件（それぞれ異なる銀行口座に引き落とし紐付け） ----
        let cardDefs: [(String, Int, Int)] = [
            ("三井住友カード", 31, 26),
            ("楽天カード", 15, 27),
            ("JCBカード", 5, 10),
            ("セゾンカード", 10, 4),
            ("dカード", 20, 15),
            ("PayPayカード", 31, 1),
        ]
        var cards: [PaymentMethodSettingData] = []
        for (i, def) in cardDefs.enumerated() {
            let (name, closing, withdrawal) = def
            let bank = banks[i % (banks.count - 1)] // SBI証券（支払い不可）は引き落とし対象から除外
            let c = makeCard(name, closing: closing, withdrawal: withdrawal, bankId: bank.id, order: i + 1)
            cards.append(c)
        }
        summary.creditCards = cards.count

        // ---- 3. その他 20件 ----
        let otherDefs: [(String, String, Int, Bool, Bool)] = [
            ("現金", "cash", 30_000, true, false),
            ("PayPay", "electronicMoney", 15_000, true, true),
            ("Suica", "electronicMoney", 8_000, true, false),
            ("PASMO", "electronicMoney", 6_000, true, false),
            ("d払い", "electronicMoney", 5_000, true, true),
            ("au PAY", "electronicMoney", 4_000, true, true),
            ("メルペイ", "electronicMoney", 3_000, true, true),
            ("LINE Pay", "electronicMoney", 3_500, true, true),
            ("WAON", "electronicMoney", 2_000, true, false),
            ("nanaco", "electronicMoney", 2_000, true, false),
            ("楽天ポイント投資", "other", 50_000, false, false),
            ("NISA", "other", 600_000, false, false),
            ("つみたてNISA", "other", 400_000, false, false),
            ("iDeCo", "other", 900_000, false, false),
            ("財形貯蓄", "other", 1_200_000, false, false),
            ("個人年金保険", "other", 500_000, false, false),
            ("ビットコイン", "other", 150_000, false, false),
            ("商品券", "other", 5_000, true, false),
            ("小口現金", "cash", 10_000, true, false),
            ("プリペイドカード", "electronicMoney", 3_000, true, false),
        ]
        var others: [PaymentMethodSettingData] = []
        for (i, def) in otherDefs.enumerated() {
            let (name, type, initial, pay, receive) = def
            let m = makeOther(name, type: type, initial: initial, order: cards.count + i + 1, pay: pay, receive: receive, testStart: testStart)
            others.append(m)
        }
        summary.otherMethods = others.count

        // ---- 4. カテゴリー 支出50 / 収入25 ----
        let expenseCategoryNames = [
            "食費", "外食", "カフェ", "日用品", "交通費", "ガソリン代", "駐車場", "娯楽", "映画", "書籍",
            "ゲーム", "衣服", "美容院", "化粧品", "医療", "歯科", "薬代", "通信", "携帯代", "インターネット",
            "住居", "家賃", "住宅ローン", "水道光熱", "電気代", "ガス代", "水道代", "サブスク", "保険", "生命保険",
            "交際費", "冠婚葬祭", "教育", "学費", "習い事", "子供用品", "ペット", "旅行", "出張", "自己投資",
            "セミナー", "家具家電", "修理費", "税金", "手数料", "寄付", "プレゼント", "趣味", "スポーツジム", "その他支出",
        ]
        let incomeCategoryNames = [
            "給料", "賞与", "副業", "副収入", "フリーランス", "配当金", "利息", "株式売却益", "投資信託分配金", "不動産収入",
            "還付金", "医療費還付", "保険金", "お小遣い", "仕送り", "贈与", "臨時収入", "懸賞", "ポイント還元", "売却収入",
            "フリマ売上", "年金", "児童手当", "補助金", "その他収入",
        ]
        var usedExpenseColors: [String] = []
        for (i, name) in expenseCategoryNames.enumerated() {
            let colorHex = CategoryColorPalette.nextAvailableColorHex(usedColorHexes: usedExpenseColors)
            usedExpenseColors.append(colorHex)
            var cat = CategoryData(name: name, colorHex: colorHex, type: "支出", sortOrder: i)
            cat.isTestData = true
            CategoryDataSync.insert(cat)
        }
        var usedIncomeColors: [String] = []
        for (i, name) in incomeCategoryNames.enumerated() {
            let colorHex = CategoryColorPalette.nextAvailableColorHex(usedColorHexes: usedIncomeColors)
            usedIncomeColors.append(colorHex)
            var cat = CategoryData(name: name, colorHex: colorHex, type: "収入", sortOrder: i)
            cat.isTestData = true
            CategoryDataSync.insert(cat)
        }
        summary.expenseCategories = expenseCategoryNames.count
        summary.incomeCategories = incomeCategoryNames.count

        // ---- 支払い方法プール（バラエティを持たせて按分） ----
        let paymentPool: [String] = banks.map(\.accountName) + cards.map(\.methodName) + others.filter { $0.showInInputPicker }.map(\.methodName)
        let receivePool: [String] = banks.map(\.accountName) + others.filter { $0.useForReceive }.map(\.methodName)

        // ---- 5. 固定費 50件 ----
        let fixedNamePool = [
            "家賃", "住宅ローン", "管理費", "駐車場代", "スマホ代", "固定電話代", "インターネット代", "電気代(基本料金)",
            "ガス代(基本料金)", "水道代(基本料金)", "NHK受信料", "新聞代", "Netflix", "Amazonプライム", "Spotify",
            "YouTube Premium", "ジム会費", "学資保険", "生命保険料", "医療保険料", "自動車保険料", "自動車ローン",
            "火災保険料", "個人年金保険料", "塾代", "ピアノ教室", "水泳教室", "英会話教室", "通信教育費", "新聞購読料",
            "クラウドストレージ", "音楽サブスク", "動画配信サービス", "電子書籍サブスク", "新聞デジタル版", "駐輪場代",
            "町内会費", "マンション修繕積立金", "ペット保険料", "介護保険料", "貸金庫使用料", "会員制倉庫", "オンラインジム",
            "サブスクリプションA", "サブスクリプションB", "サブスクリプションC", "サブスクリプションD", "サブスクリプションE",
            "サブスクリプションF", "サブスクリプションG",
        ]
        var fixedExpenses: [FixedExpenseData] = []
        for i in 0..<50 {
            let name = fixedNamePool[i % fixedNamePool.count]
            let cat = expenseCategoryNames[pick(700, i, lo: 0, hi: expenseCategoryNames.count - 1)]
            let amount = pick(701, i, lo: 500, hi: 90_000)
            let day = pick(702, i, lo: 1, hi: 28)
            let startMonthIndex = (i * 4) % 200
            let start = months[startMonthIndex]
            let useCard = i % 3 != 0
            let payType = useCard ? "paymentMethod" : "bankAccount"
            let payId = useCard ? cards[i % cards.count].id : banks[i % (banks.count - 1)].id
            var f = FixedExpenseData(name: "\(name)\(i / fixedNamePool.count > 0 ? "\(i / fixedNamePool.count + 1)" : "")",
                                      amount: amount, categoryName: cat,
                                      paymentMethodType: payType, paymentMethodId: payId,
                                      dayOfMonth: day, startDate: start, memo: "性能テスト用固定費")
            f.isTestData = true
            FixedExpenseDataSync.insert(f)
            fixedExpenses.append(f)
        }
        summary.fixedExpenses = fixedExpenses.count

        // ---- 6. 定期収入 20件 ----
        let recurringIncomeNamePool = [
            "給料", "副業収入", "配当金", "家賃収入", "個人年金", "児童手当", "お小遣い", "仕送り",
            "業務委託報酬", "顧問料", "印税収入", "広告収入", "アフィリエイト収入", "配信収入",
            "投資信託分配金", "利息収入", "駐車場収入", "不動産収入2", "副業収入B", "副業収入C",
        ]
        var recurringIncomes: [RecurringIncomeData] = []
        for i in 0..<20 {
            let name = recurringIncomeNamePool[i % recurringIncomeNamePool.count]
            let cat = incomeCategoryNames[pick(710, i, lo: 0, hi: incomeCategoryNames.count - 1)]
            let amount = pick(711, i, lo: 5_000, hi: 300_000)
            let day = pick(712, i, lo: 1, hi: 28)
            let startMonthIndex = (i * 6) % 180
            let start = months[startMonthIndex]
            let useBank = i % 2 == 0
            let recType = useBank ? "bankAccount" : "paymentMethod"
            let recId = useBank ? banks[i % (banks.count - 1)].id : others[i % others.count].id
            var r = RecurringIncomeData(name: name, amount: amount, categoryName: cat,
                                        receiveMethodType: recType, receiveMethodId: recId,
                                        dayOfMonth: day, startDate: start, memo: "性能テスト用定期収入")
            r.isTestData = true
            RecurringIncomeDataSync.insert(r)
            recurringIncomes.append(r)
        }
        summary.recurringIncomes = recurringIncomes.count

        // ---- 7. 定期振替設定 30件（設定のみ。実際の履歴は下記の振替生成で別途作る） ----
        for i in 0..<30 {
            let fromIsBank = i % 2 == 0
            let from: any NamedAccount = fromIsBank ? banks[i % banks.count] : others[i % others.count]
            let fromId: UUID = fromIsBank ? banks[i % banks.count].id : others[i % others.count].id
            let toIsBank = i % 3 == 0
            let to: any NamedAccount = toIsBank ? banks[(i + 1) % banks.count] : others[(i + 1) % others.count]
            let toId: UUID = toIsBank ? banks[(i + 1) % banks.count].id : others[(i + 1) % others.count].id
            guard fromId != toId else { continue }
            var setting = RecurringTransferSettingData(
                fromMethodId: fromId, fromMethodName: from.accountNameOrMethodName,
                fromType: fromIsBank ? TransferAccountType.bank.rawValue : TransferAccountType.paymentMethod.rawValue,
                toMethodId: toId, toMethodName: to.accountNameOrMethodName,
                toType: toIsBank ? TransferAccountType.bank.rawValue : TransferAccountType.paymentMethod.rawValue,
                amount: pick(720, i, lo: 3_000, hi: 50_000),
                day: pick(721, i, lo: 1, hi: 28)
            )
            setting.isTestData = true
            RecurringTransferSettingDataSync.insert(setting)
        }
        summary.recurringTransfers = 30

        // ---- 8. 月ごとの取引生成（固定費履歴・定期収入履歴・振替・変動収支） ----
        let variableExpensesPerMonth = 95
        let variableIncomePerMonth = 8
        let transfersPerMonth = 2
        var photoCount = 0
        let photoChancePercent = 7 // 約7%の取引に写真を添付（36,500件換算で約2,500枚）

        for (mi, ms) in months.enumerated() {
            // 固定費履歴
            for (fi, f) in fixedExpenses.enumerated() {
                guard f.startDate <= ms else { continue }
                var e = ExpenseData(amount: f.amount, date: md(f.dayOfMonth, in: ms),
                                     paymentMethod: f.paymentMethodType == "paymentMethod"
                                        ? (paymentMethodName(id: f.paymentMethodId, cards: cards, others: others) ?? "現金")
                                        : (bankName(id: f.paymentMethodId, banks: banks) ?? "現金"),
                                     category: f.categoryName, memo: "", bankAccountId: f.paymentMethodType == "bankAccount" ? f.paymentMethodId : nil)
                e.fixedExpenseId = f.id
                e.isTestData = true
                if chance(mi, fi, 1, percent: photoChancePercent) {
                    if let path = attachSyntheticPhoto(seedA: mi, seedB: fi + 1000) {
                        e.receiptImagePath = path
                        photoCount += 1
                    }
                }
                ExpenseDataSync.insert(e)
                summary.expenseCount += 1
            }

            // 定期収入履歴
            for (ri, r) in recurringIncomes.enumerated() {
                guard r.startDate <= ms else { continue }
                let methodName = r.receiveMethodType == "bankAccount"
                    ? (bankName(id: r.receiveMethodId, banks: banks) ?? "現金")
                    : (otherMethodName(id: r.receiveMethodId, others: others) ?? "現金")
                var i = IncomeData(amount: r.amount, date: md(r.dayOfMonth, in: ms),
                                   receiveMethod: methodName, category: r.categoryName, memo: "",
                                   bankAccountId: r.receiveMethodType == "bankAccount" ? r.receiveMethodId : nil)
                i.recurringIncomeId = r.id
                i.isTestData = true
                IncomeDataSync.insert(i)
                summary.incomeCount += 1
            }

            // 振替（口座間・カード引落に近い実利用データ）
            for ti in 0..<transfersPerMonth {
                let fromBank = banks[pick(730, mi, ti, lo: 0, hi: banks.count - 1)]
                var toBank = banks[pick(731, mi, ti, lo: 0, hi: banks.count - 1)]
                if toBank.id == fromBank.id {
                    toBank = banks[(banks.firstIndex(where: { $0.id == fromBank.id })! + 1) % banks.count]
                }
                let amount = pick(732, mi, ti, lo: 5_000, hi: 80_000)
                var t = TransferData(
                    date: md(pick(733, mi, ti, lo: 1, hi: 28), in: ms),
                    fromType: TransferAccountType.bank.rawValue, fromId: fromBank.id, fromName: fromBank.accountName,
                    toType: TransferAccountType.bank.rawValue, toId: toBank.id, toName: toBank.accountName,
                    amount: amount, feeAmount: chance(mi, ti, 2, percent: 20) ? pick(734, mi, ti, lo: 110, hi: 440) : 0,
                    memo: "定期振替"
                )
                t.isTestData = true
                TransferDataSync.insert(t)
                summary.transferCount += 1
            }

            // 変動支出
            for si in 0..<variableExpensesPerMonth {
                let catIndex = pick(740, mi, si, lo: 0, hi: expenseCategoryNames.count - 1)
                let cat = expenseCategoryNames[catIndex]
                let method = paymentPool[pick(741, mi, si, lo: 0, hi: paymentPool.count - 1)]
                let amount = pick(742, mi, si, lo: 300, hi: 15_000)
                let day = pick(743, mi, si, lo: 1, hi: 28)
                let memo = chance(mi, si, 3, percent: 45) ? memoText(catIndex: catIndex, seed: mi * 1000 + si) : ""
                var e = ExpenseData(amount: amount, date: md(day, in: ms), paymentMethod: method, category: cat, memo: memo, bankAccountId: nil)
                e.isTestData = true
                if chance(mi, si, 4, percent: photoChancePercent) {
                    if let path = attachSyntheticPhoto(seedA: mi, seedB: si) {
                        e.receiptImagePath = path
                        photoCount += 1
                    }
                }
                ExpenseDataSync.insert(e)
                summary.expenseCount += 1
            }

            // 変動収入
            for si in 0..<variableIncomePerMonth {
                let catIndex = pick(750, mi, si, lo: 0, hi: incomeCategoryNames.count - 1)
                let cat = incomeCategoryNames[catIndex]
                let method = receivePool[pick(751, mi, si, lo: 0, hi: receivePool.count - 1)]
                let amount = pick(752, mi, si, lo: 1_000, hi: 60_000)
                let day = pick(753, mi, si, lo: 1, hi: 28)
                let memo = chance(mi, si, 5, percent: 30) ? "臨時収入" : ""
                var inc = IncomeData(amount: amount, date: md(day, in: ms), receiveMethod: method, category: cat, memo: memo, bankAccountId: nil)
                inc.isTestData = true
                IncomeDataSync.insert(inc)
                summary.incomeCount += 1
            }
        }

        summary.photoCount = photoCount

        // ---- 9. スナップショット生成（このまま普段通り利用できる状態にしておく） ----
        SnapshotManager.rebuildAll()
        AnalysisSnapshotManager.rebuildAll()

        summary.elapsedSeconds = CFAbsoluteTimeGetCurrent() - overallStart
        return summary
    }

    // MARK: - メモ文言プール

    private static let memoPool = [
        "スーパーで購入", "コンビニ利用", "ネット注文", "友人と", "家族で", "会社帰りに",
        "セール品", "まとめ買い", "急な出費", "月末の支払い", "先月分の精算", "ポイント利用あり",
        "領収書あり", "経費精算予定", "定期購入分", "特売日に購入", "予定外の出費", "自分へのご褒美",
    ]

    private static func memoText(catIndex: Int, seed: Int) -> String {
        memoPool[abs(h(seed, catIndex)) % memoPool.count]
    }

    // MARK: - 合成レシート画像（実写真は使わず、軽量なダミーJPEGをDocuments/receiptsへ書き出す）

    private static func attachSyntheticPhoto(seedA: Int, seedB: Int) -> String? {
        let size = CGSize(width: 240, height: 240)
        let renderer = UIGraphicsImageRenderer(size: size)
        let hue = CGFloat(abs(h(seedA, seedB)) % 360) / 360.0
        let color = UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1.0)
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.jpegData(compressionQuality: 0.4) else { return nil }
        return ReceiptImageHelper.save(data)
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
    private static func makeOther(_ name: String, type: String, initial: Int, order: Int, pay: Bool, receive: Bool, testStart: Date) -> PaymentMethodSettingData {
        var m = PaymentMethodSettingData(methodName: name, type: type, sortOrder: order)
        m.isAsset = true
        m.assetInitialBalance = Double(initial)
        m.showInInputPicker = pay
        m.useForReceive = receive
        m.showInAnalysis = true
        m.isTestData = true

        if initial > 0 {
            var inc = IncomeData(amount: initial, date: testStart, receiveMethod: name, category: "初期残高", memo: "", bankAccountId: nil)
            inc.isTestData = true
            IncomeDataSync.insert(inc)
            m.assetInitialBalanceIncomeId = inc.id
        }
        PaymentMethodSettingDataSync.insert(m)
        return m
    }

    @discardableResult
    private static func makeIncome(_ amount: Int, date: Date, method: String, cat: String, bankId: UUID?) -> IncomeData {
        var d = IncomeData(amount: amount, date: date, receiveMethod: method, category: cat, memo: "", bankAccountId: bankId)
        d.isTestData = true
        IncomeDataSync.insert(d)
        return d
    }

    // MARK: - ヘルパー：名前解決

    private static func bankName(id: UUID?, banks: [BankAccountData]) -> String? {
        guard let id else { return nil }
        return banks.first { $0.id == id }?.accountName
    }

    private static func otherMethodName(id: UUID?, others: [PaymentMethodSettingData]) -> String? {
        guard let id else { return nil }
        return others.first { $0.id == id }?.methodName
    }

    private static func paymentMethodName(id: UUID?, cards: [PaymentMethodSettingData], others: [PaymentMethodSettingData]) -> String? {
        guard let id else { return nil }
        return (cards + others).first { $0.id == id }?.methodName
    }

    // MARK: - 削除

    static func deleteAll() throws {
        // レシート画像ファイルも一緒に削除する
        let expensePaths = ExpenseDataSync.fetch(matching: NSPredicate(format: "isTestData == YES"))
            .compactMap(\.receiptImagePath)
        let incomePaths = IncomeDataSync.fetch(matching: NSPredicate(format: "isTestData == YES"))
            .compactMap(\.receiptImagePath)
        ReceiptImageHelper.deleteAll(expensePaths + incomePaths)

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
        for recurringTransfer in RecurringTransferSettingDataSync.fetchAll() where recurringTransfer.isTestData {
            RecurringTransferSettingDataSync.delete(id: recurringTransfer.id)
        }
        for expense in ExpenseDataSync.fetchAll() where expense.isTestData {
            ExpenseDataSync.delete(id: expense.id)
        }
        for income in IncomeDataSync.fetchAll() where income.isTestData {
            IncomeDataSync.delete(id: income.id)
        }
        for transfer in TransferDataSync.fetchAll() where transfer.isTestData {
            TransferDataSync.delete(id: transfer.id)
        }
        for category in CategoryDataSync.fetchAll() where category.isTestData {
            CategoryDataSync.delete(id: category.id)
        }
        SnapshotManager.rebuildAll()
        AnalysisSnapshotManager.rebuildAll()
    }
}

// MARK: - BankAccountData/PaymentMethodSettingDataから共通の表示名を取り出す小ヘルパー

private protocol NamedAccount {
    var accountNameOrMethodName: String { get }
}

extension BankAccountData: NamedAccount {
    var accountNameOrMethodName: String { accountName }
}

extension PaymentMethodSettingData: NamedAccount {
    var accountNameOrMethodName: String { methodName }
}
