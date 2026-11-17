import Foundation

// MARK: - 固定費 / 定期収入から取引データを生成するサービス
//
// FixedExpenseEditView / RecurringIncomeEditView の保存時と、
// プレミアム再登録によるロック解除直後のバックフィル（未生成月の埋め合わせ）の
// 両方から呼ばれる共通ロジック。startDate から今月まで、未生成の月だけを埋める
// （既に生成済みの月はスキップするため、複数回呼んでも安全＝冪等）。

enum RecurringEntryGenerator {

    // startDateから今月まで（startDateが未来ならその月のみ）ExpenseDataを生成する。
    // ただし当月ぶんは、設定日がまだ来ていなければ生成しない
    // （例: 今日7日・設定日9日 なら7日時点ではまだ登録しない。9日になった時点でこの関数が
    // 再度呼ばれて初めて登録される＝Kakeibo3Appのbackfillからの定期的な呼び出しが必要）。
    // 過去月ぶんは無条件で生成する（既に過ぎた日付なので即時反映してよい）。
    static func generateExpenseEntries(for fixedExpense: FixedExpenseData, methodName: String, bookId: UUID) {
        var fixedExpense = fixedExpense
        let cal = Calendar.current
        let today = Date()
        let todayStart = cal.startOfDay(for: today)

        guard let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)),
              let fixedStartMonth = cal.date(from: cal.dateComponents([.year, .month], from: fixedExpense.startDate))
        else { return }

        let generateUpTo = fixedStartMonth > currentMonthStart ? fixedStartMonth : currentMonthStart

        let fixedId = fixedExpense.id
        // ルール（固定費）ごとに全支出履歴を毎回fetchするとO(ルール数 × 支出件数)になるため、
        // このfixedExpenseIdに紐づく分だけをCore Data側に絞り込ませる。
        let matchingExpenses = ExpenseDataSync.fetch(matching: NSPredicate(format: "fixedExpenseId == %@", fixedId as CVarArg))

        // 後方互換：休日調整機能を追加する前に生成されたデータはgeneratedScheduleMonthsを
        // 持たないため、既存の支出のdateから一度だけ復元する（旧ロジックと同じ計算）。
        // 休日調整機能追加前は反映日=予定日そのものだったため、この復元は常に正確。
        var didChangeSchedule = false
        if fixedExpense.generatedScheduleMonths.isEmpty && !matchingExpenses.isEmpty {
            fixedExpense.generatedScheduleMonths = Array(Set(
                matchingExpenses
                    .map { "\(cal.component(.year, from: $0.date))-\(cal.component(.month, from: $0.date))" }
            ))
            didChangeSchedule = true
        }
        var generatedMonthKeys = Set(fixedExpense.generatedScheduleMonths)

        let isBankAccount = fixedExpense.paymentMethodType == "bankAccount"
        let bankId: UUID? = isBankAccount ? fixedExpense.paymentMethodId : nil
        let adjustment = WeekendHolidayAdjustment(rawValue: fixedExpense.holidayAdjustment) ?? .none

        var cursor = fixedStartMonth
        while cursor <= generateUpTo {
            let y = cal.component(.year, from: cursor)
            let m = cal.component(.month, from: cursor)
            let key = "\(y)-\(m)"

            if !generatedMonthKeys.contains(key) {
                let daysInMonth = cal.range(of: .day, in: .month, for: cursor)?.count ?? 28
                let day = min(fixedExpense.dayOfMonth, daysInMonth)
                var comps = DateComponents()
                comps.year = y; comps.month = m; comps.day = day
                let scheduledDate = cal.date(from: comps) ?? cursor

                if cal.startOfDay(for: scheduledDate) <= todayStart {
                    // 銀行口座の場合のみ休業日調整を適用する（現金・クレカ等には「金融機関の休業日」は無関係）。
                    // 月またぎ・年またぎはHolidayCalendarService側の日単位ループでそのまま処理される。
                    let entryDate = isBankAccount
                        ? HolidayCalendarService.adjustedDate(for: scheduledDate, adjustment: adjustment)
                        : scheduledDate

                    var entry = ExpenseData(
                        amount: fixedExpense.amount,
                        date: entryDate,
                        paymentMethod: methodName,
                        category: fixedExpense.categoryName,
                        memo: fixedExpense.memo,
                        bankAccountId: bankId
                    )
                    entry.fixedExpenseId = fixedId
                    entry.bookId = bookId
                    ExpenseDataSync.insert(entry)
                    SnapshotUpdateService.handle(.expenseCreated(date: entryDate, bookId: bookId))

                    // 実際の反映日（entryDate）ではなく、本来の予定月（key）を記録する。
                    // こうしないと休日調整で月をまたいだ場合に同じ月をもう一度生成してしまう。
                    fixedExpense.generatedScheduleMonths.append(key)
                    generatedMonthKeys.insert(key)
                    didChangeSchedule = true
                }
            }

            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        if didChangeSchedule {
            FixedExpenseDataSync.update(fixedExpense)
        }
    }

    // startDateから今月まで（startDateが未来ならその月のみ）IncomeDataを生成する。
    // 当月ぶんの「まだ来ていない日は生成しない」ルールはgenerateExpenseEntriesと同じ。
    static func generateIncomeEntries(for recurringIncome: RecurringIncomeData, methodName: String, bookId: UUID) {
        var recurringIncome = recurringIncome
        let cal = Calendar.current
        let today = Date()
        let todayStart = cal.startOfDay(for: today)

        guard let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)),
              let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: recurringIncome.startDate))
        else { return }

        let generateUpTo = startMonth > currentMonthStart ? startMonth : currentMonthStart

        let recurringId = recurringIncome.id
        // ルール（定期収入）ごとに全収入履歴を毎回fetchするとO(ルール数 × 収入件数)になるため、
        // このrecurringIncomeIdに紐づく分だけをCore Data側に絞り込ませる。
        let matchingIncomes = IncomeDataSync.fetch(matching: NSPredicate(format: "recurringIncomeId == %@", recurringId as CVarArg))

        // 後方互換：休日調整機能を追加する前に生成されたデータはgeneratedScheduleMonthsを
        // 持たないため、既存の収入のdateから一度だけ復元する（旧ロジックと同じ計算）。
        // 休日調整機能追加前は反映日=予定日そのものだったため、この復元は常に正確。
        var didChangeSchedule = false
        if recurringIncome.generatedScheduleMonths.isEmpty && !matchingIncomes.isEmpty {
            recurringIncome.generatedScheduleMonths = Array(Set(
                matchingIncomes
                    .map { "\(cal.component(.year, from: $0.date))-\(cal.component(.month, from: $0.date))" }
            ))
            didChangeSchedule = true
        }
        var generatedMonthKeys = Set(recurringIncome.generatedScheduleMonths)

        let isBankAccount = recurringIncome.receiveMethodType == "bankAccount"
        let bankId: UUID? = isBankAccount ? recurringIncome.receiveMethodId : nil
        let adjustment = WeekendHolidayAdjustment(rawValue: recurringIncome.holidayAdjustment) ?? .none

        var cursor = startMonth
        while cursor <= generateUpTo {
            let y = cal.component(.year, from: cursor)
            let m = cal.component(.month, from: cursor)
            let key = "\(y)-\(m)"

            if !generatedMonthKeys.contains(key) {
                let daysInMonth = cal.range(of: .day, in: .month, for: cursor)?.count ?? 28
                let day = min(recurringIncome.dayOfMonth, daysInMonth)
                var comps = DateComponents()
                comps.year = y; comps.month = m; comps.day = day
                let scheduledDate = cal.date(from: comps) ?? cursor

                if cal.startOfDay(for: scheduledDate) <= todayStart {
                    // 銀行口座の場合のみ休業日調整を適用する（現金等には「金融機関の休業日」は無関係）。
                    // 月またぎ・年またぎはHolidayCalendarService側の日単位ループでそのまま処理される。
                    let entryDate = isBankAccount
                        ? HolidayCalendarService.adjustedDate(for: scheduledDate, adjustment: adjustment)
                        : scheduledDate

                    var entry = IncomeData(
                        amount: recurringIncome.amount,
                        date: entryDate,
                        receiveMethod: methodName,
                        category: recurringIncome.categoryName,
                        memo: recurringIncome.memo,
                        bankAccountId: bankId
                    )
                    entry.recurringIncomeId = recurringId
                    entry.bookId = bookId
                    IncomeDataSync.insert(entry)
                    SnapshotUpdateService.handle(.incomeCreated(date: entryDate, bookId: bookId))

                    // 実際の反映日（entryDate）ではなく、本来の予定月（key）を記録する。
                    // こうしないと休日調整で月をまたいだ場合に同じ月をもう一度生成してしまう。
                    recurringIncome.generatedScheduleMonths.append(key)
                    generatedMonthKeys.insert(key)
                    didChangeSchedule = true
                }
            }

            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        if didChangeSchedule {
            RecurringIncomeDataSync.update(recurringIncome)
        }
    }

    // startDateから今月まで（startDateが未来ならその月のみ）TransferDataを生成する。
    // 当月ぶんの「まだ来ていない日は生成しない」ルールはgenerateExpenseEntriesと同じ。
    static func generateTransferEntries(for recurringTransfer: RecurringTransferSettingData, bookId: UUID) {
        var recurringTransfer = recurringTransfer
        let cal = Calendar.current
        let today = Date()
        let todayStart = cal.startOfDay(for: today)

        guard let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)),
              let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: recurringTransfer.startDate))
        else { return }

        let generateUpTo = startMonth > currentMonthStart ? startMonth : currentMonthStart

        let recurringId = recurringTransfer.id
        // ルール（定期振替）ごとに全振替履歴を毎回fetchするとO(ルール数 × 振替件数)になるため、
        // このrecurringTransferSettingIdに紐づく分だけをCore Data側に絞り込ませる。
        let matchingTransfers = TransferDataSync.fetch(matching: NSPredicate(format: "recurringTransferSettingId == %@", recurringId as CVarArg))

        // 後方互換：休日調整機能を追加する前に生成されたデータはgeneratedScheduleMonthsを
        // 持たないため、既存の振替のdateから一度だけ復元する（旧ロジックと同じ計算）。
        // 休日調整機能追加前は反映日=予定日そのものだったため、この復元は常に正確。
        var didChangeSchedule = false
        if recurringTransfer.generatedScheduleMonths.isEmpty && !matchingTransfers.isEmpty {
            recurringTransfer.generatedScheduleMonths = Array(Set(
                matchingTransfers
                    .map { "\(cal.component(.year, from: $0.date))-\(cal.component(.month, from: $0.date))" }
            ))
            didChangeSchedule = true
        }
        var generatedMonthKeys = Set(recurringTransfer.generatedScheduleMonths)

        let isBankAccountInvolved = recurringTransfer.fromType == TransferAccountType.bank.rawValue
            || recurringTransfer.toType == TransferAccountType.bank.rawValue
        let adjustment = WeekendHolidayAdjustment(rawValue: recurringTransfer.holidayAdjustment) ?? .none

        var cursor = startMonth
        while cursor <= generateUpTo {
            let y = cal.component(.year, from: cursor)
            let m = cal.component(.month, from: cursor)
            let key = "\(y)-\(m)"

            if !generatedMonthKeys.contains(key) {
                let daysInMonth = cal.range(of: .day, in: .month, for: cursor)?.count ?? 28
                let day = min(recurringTransfer.day, daysInMonth)
                var comps = DateComponents()
                comps.year = y; comps.month = m; comps.day = day
                let scheduledDate = cal.date(from: comps) ?? cursor

                if cal.startOfDay(for: scheduledDate) <= todayStart {
                    // 移動元/移動先のどちらかが銀行口座の場合のみ休業日調整を適用する。
                    // 月またぎ・年またぎはHolidayCalendarService側の日単位ループでそのまま処理される。
                    let entryDate = isBankAccountInvolved
                        ? HolidayCalendarService.adjustedDate(for: scheduledDate, adjustment: adjustment)
                        : scheduledDate

                    var entry = TransferData(
                        date: entryDate,
                        fromType: recurringTransfer.fromType, fromId: recurringTransfer.fromMethodId, fromName: recurringTransfer.fromMethodName,
                        toType: recurringTransfer.toType, toId: recurringTransfer.toMethodId, toName: recurringTransfer.toMethodName,
                        amount: recurringTransfer.amount
                    )
                    entry.recurringTransferSettingId = recurringId
                    entry.bookId = bookId
                    TransferDataSync.insert(entry)
                    SnapshotUpdateService.handle(.transferCreated(date: entryDate, bookId: bookId))

                    // 実際の反映日（entryDate）ではなく、本来の予定月（key）を記録する。
                    // こうしないと休日調整で月をまたいだ場合に同じ月をもう一度生成してしまう。
                    recurringTransfer.generatedScheduleMonths.append(key)
                    generatedMonthKeys.insert(key)
                    didChangeSchedule = true
                }
            }

            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        if didChangeSchedule {
            RecurringTransferSettingDataSync.update(recurringTransfer)
        }
    }

    // MARK: - 全件バックフィル
    //
    // 固定費/定期収入/定期振替のうちアクティブなものすべてについて、まだ生成されていない
    // （＝設定日が到来した）月ぶんの取引をまとめて生成する。保存時だけでなく、アプリ起動時・
    // フォアグラウンド復帰時にも呼ぶことで「日付が来たら自動で登録される」を実現する
    // （バックグラウンド処理が無いモバイルアプリでは、次にアプリを開いたタイミングが
    // 「日付が来た」ことを検知できる最初の機会になるため）。

    // 帳簿ごとにループし、それぞれの帳簿に属する固定費/定期収入/定期振替・口座・支払い方法だけを
    // 使って生成する（帳簿は「ほぼ別アプリ」として扱うため、他の帳簿のルール・口座は一切参照しない）。
    static func backfillAllIfNeeded() {
        let books = BookDataSync.fetchAll()

        for book in books {
            let bookId = book.id
            let bankAccounts = BankAccountDataSync.fetchAll(bookId: bookId)
            let paymentMethods = PaymentMethodSettingDataSync.fetchAll(bookId: bookId)

            let fixedExpenses = FixedExpenseDataSync.fetch(matching: NSPredicate(format: "isActive == YES AND bookId == %@", bookId as CVarArg))
            for fixed in fixedExpenses {
                let methodName = resolveMethodName(
                    type: fixed.paymentMethodType, id: fixed.paymentMethodId,
                    bankAccounts: bankAccounts, paymentMethods: paymentMethods
                )
                generateExpenseEntries(for: fixed, methodName: methodName, bookId: bookId)
            }

            let recurringIncomes = RecurringIncomeDataSync.fetch(matching: NSPredicate(format: "isActive == YES AND bookId == %@", bookId as CVarArg))
            for income in recurringIncomes {
                let methodName = resolveMethodName(
                    type: income.receiveMethodType, id: income.receiveMethodId,
                    bankAccounts: bankAccounts, paymentMethods: paymentMethods
                )
                generateIncomeEntries(for: income, methodName: methodName, bookId: bookId)
            }

            let recurringTransfers = RecurringTransferSettingDataSync.fetch(matching: NSPredicate(format: "isActive == YES AND bookId == %@", bookId as CVarArg))
            for transfer in recurringTransfers {
                generateTransferEntries(for: transfer, bookId: bookId)
            }
        }
    }

    // MARK: - 定期振替の紐づけ同期
    //
    // BankAccountData/PaymentMethodSettingData の recurringTransferSettingIds に、
    // この定期振替設定のIDを現在のfrom/toだけに紐づけ直す（口座削除時、紐づく定期振替も
    // 一緒に削除するための逆引き用。BankAccountEditView.deleteAllRecurringTransfers参照）。
    // 呼び出すたびに一旦全口座/支払い方法から外してから現在のfrom/toにだけ付け直すため、
    // from/toを変更した場合も古い紐づけが残らない。

    static func syncRecurringTransferLinkage(
        settingId: UUID,
        fromType: String, fromId: UUID,
        toType: String, toId: UUID,
        bankAccounts: [BankAccountData],
        paymentMethods: [PaymentMethodSettingData]
    ) {
        for bank in bankAccounts where bank.recurringTransferSettingIds.contains(settingId) {
            var updated = bank
            updated.recurringTransferSettingIds.removeAll { $0 == settingId }
            BankAccountDataSync.update(updated)
        }
        for method in paymentMethods where method.recurringTransferSettingIds.contains(settingId) {
            var updated = method
            updated.recurringTransferSettingIds.removeAll { $0 == settingId }
            PaymentMethodSettingDataSync.update(updated)
        }

        func attach(type: String, id: UUID) {
            if type == TransferAccountType.bank.rawValue {
                if var b = bankAccounts.first(where: { $0.id == id }), !b.recurringTransferSettingIds.contains(settingId) {
                    b.recurringTransferSettingIds.append(settingId)
                    BankAccountDataSync.update(b)
                }
            } else if type == TransferAccountType.paymentMethod.rawValue {
                if var m = paymentMethods.first(where: { $0.id == id }), !m.recurringTransferSettingIds.contains(settingId) {
                    m.recurringTransferSettingIds.append(settingId)
                    PaymentMethodSettingDataSync.update(m)
                }
            }
        }
        attach(type: fromType, id: fromId)
        attach(type: toType, id: toId)
    }

    // 支払い/受け取り方法IDから表示名を解決する（"bankAccount" | "paymentMethod"）
    static func resolveMethodName(
        type: String, id: UUID?, bankAccounts: [BankAccountData], paymentMethods: [PaymentMethodSettingData]
    ) -> String {
        guard let id else { return "" }
        switch type {
        case "bankAccount":   return bankAccounts.first(where: { $0.id == id })?.accountName ?? ""
        case "paymentMethod": return paymentMethods.first(where: { $0.id == id })?.methodName ?? ""
        default: return ""
        }
    }
}
