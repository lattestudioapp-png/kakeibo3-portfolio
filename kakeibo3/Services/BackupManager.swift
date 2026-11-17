import Foundation
import Combine

// MARK: - エラー定義

enum BackupError: LocalizedError {
    case folderAccessDenied
    case bookmarkResolutionFailed

    var errorDescription: String? {
        switch self {
        case .folderAccessDenied:
            return "保存先にアクセスできません。保存先を選び直してください。"
        case .bookmarkResolutionFailed:
            return "保存先の情報を読み込めませんでした。保存先を選び直してください。"
        }
    }
}

// MARK: - BackupManager

final class BackupManager: ObservableObject {
    static let shared = BackupManager()

    private enum Keys {
        static let autoBackupEnabled        = "autoBackupEnabled"
        static let autoBackupFrequency      = "autoBackupFrequency"
        static let lastBackupDate           = "lastBackupDate"
        static let backupFolderBookmarkData = "backupFolderBookmarkData"
        static let backupFolderDisplayName  = "backupFolderDisplayName"
    }

    // MARK: - Published

    @Published var autoBackupEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: Keys.autoBackupEnabled) }
    }

    @Published var autoBackupFrequency: String {
        didSet { UserDefaults.standard.set(autoBackupFrequency, forKey: Keys.autoBackupFrequency) }
    }

    @Published private(set) var lastBackupDate: Date? {
        didSet {
            if let date = lastBackupDate {
                UserDefaults.standard.set(date, forKey: Keys.lastBackupDate)
            }
        }
    }

    @Published private(set) var hasCustomBackupFolder: Bool
    @Published private(set) var backupFolderDisplayName: String

    // MARK: - Init

    init() {
        autoBackupEnabled       = UserDefaults.standard.bool(forKey: Keys.autoBackupEnabled)
        lastBackupDate          = UserDefaults.standard.object(forKey: Keys.lastBackupDate) as? Date
        hasCustomBackupFolder   = UserDefaults.standard.data(forKey: Keys.backupFolderBookmarkData) != nil
        backupFolderDisplayName = UserDefaults.standard.string(forKey: Keys.backupFolderDisplayName) ?? ""

        // "onBackground" は廃止。残っていたら "daily" へ移行
        let stored = UserDefaults.standard.string(forKey: Keys.autoBackupFrequency) ?? "daily"
        autoBackupFrequency = (stored == "onBackground") ? "daily" : stored
        if stored == "onBackground" {
            UserDefaults.standard.set("daily", forKey: Keys.autoBackupFrequency)
        }
    }

    // MARK: - 保存先フォルダ管理

    func saveBackupFolderBookmark(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Keys.backupFolderBookmarkData)
            let displayName = url.lastPathComponent
            UserDefaults.standard.set(displayName, forKey: Keys.backupFolderDisplayName)
            hasCustomBackupFolder   = true
            backupFolderDisplayName = displayName
        } catch {
            print("[BackupManager] Failed to create bookmark: \(error)")
        }
    }

    func resolveBackupFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.backupFolderBookmarkData) else {
            return nil
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // bookmark が古くなっていたら更新を試みる
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let refreshed = try? url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: Keys.backupFolderBookmarkData)
                }
            }
            return url
        } catch {
            print("[BackupManager] Failed to resolve bookmark: \(error)")
            return nil
        }
    }

    func clearBackupFolder() {
        UserDefaults.standard.removeObject(forKey: Keys.backupFolderBookmarkData)
        UserDefaults.standard.removeObject(forKey: Keys.backupFolderDisplayName)
        hasCustomBackupFolder   = false
        backupFolderDisplayName = ""
    }

    // MARK: - 自動バックアップ

    func performAutoBackup() {
        guard autoBackupEnabled, shouldPerformAutoBackup() else { return }
        // 帳簿単位のバックアップになったため、自動バックアップは全帳簿ぶんを
        // 帳簿ごとに個別ファイルとして書き出す（1帳簿だけ選んで他が無防備になるのを防ぐ）。
        let books = BookDataSync.fetchAll()
        for book in books {
            do {
                try createBackup(bookId: book.id)
            } catch BackupError.folderAccessDenied, BackupError.bookmarkResolutionFailed {
                // 指定フォルダにアクセスできない場合はローカルへフォールバック
                print("[BackupManager] Custom folder inaccessible, falling back to local Documents")
                performLocalFallbackBackup(bookId: book.id, bookName: book.name)
            } catch {
                print("[BackupManager] Auto backup failed for book \(book.name): \(error)")
            }
        }
    }

    private func shouldPerformAutoBackup() -> Bool {
        guard let last = lastBackupDate else { return true }
        switch autoBackupFrequency {
        case "daily":   return Date().timeIntervalSince(last) >= 86_400
        case "weekly":  return Date().timeIntervalSince(last) >= 604_800
        case "monthly": return Date().timeIntervalSince(last) >= 2_592_000
        default:        return Date().timeIntervalSince(last) >= 86_400
        }
    }

    private func performLocalFallbackBackup(bookId: UUID, bookName: String) {
        do {
            let backup  = try collectBackupData(bookId: bookId)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data     = try encoder.encode(backup)
            let fileName = makeFileName(bookName: bookName)
            _ = try writeToLocalDocuments(data: data, fileName: fileName)
            lastBackupDate = Date()
        } catch {
            print("[BackupManager] Local fallback backup failed: \(error)")
        }
    }

    // MARK: - バックアップ作成

    /// 指定した帳簿1件ぶんのデータだけをバックアップする。他の帳簿のデータはファイルに含まれない。
    @discardableResult
    func createBackup(bookId: UUID) throws -> URL {
        let backup  = try collectBackupData(bookId: bookId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let fileName = makeFileName(bookName: backup.books?.first?.name ?? "")
        let url  = try writeToDestination(data, fileName: fileName)
        lastBackupDate = Date()
        return url
    }

    private func makeFileName(bookName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let sanitized = sanitizeForFileName(bookName)
        let suffix = sanitized.isEmpty ? "" : "_\(sanitized)"
        return "kakeibo_backup\(suffix)_\(formatter.string(from: Date())).json"
    }

    private func sanitizeForFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    private func writeToDestination(_ data: Data, fileName: String) throws -> URL {
        if hasCustomBackupFolder {
            guard let folderURL = resolveBackupFolderURL() else {
                throw BackupError.bookmarkResolutionFailed
            }
            let accessed = folderURL.startAccessingSecurityScopedResource()
            defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
            guard accessed else { throw BackupError.folderAccessDenied }

            let fileURL = folderURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } else {
            return try writeToLocalDocuments(data: data, fileName: fileName)
        }
    }

    private func writeToLocalDocuments(data: Data, fileName: String) throws -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 指定した帳簿(bookId)ぶんのデータだけを収集する。他の帳簿のデータは一切含めない。
    private func collectBackupData(bookId: UUID) throws -> BackupData {
        let allBooks           = BookDataSync.fetchAll()
        let books               = allBooks.filter { $0.id == bookId }
        // fetchAll(bookId:)はゴミ箱内を除外するのがデフォルトのため、ゴミ箱内データも
        // バックアップ対象に含めるためfetchTrashed(bookId:)の結果も合わせて集める。
        let expenses           = ExpenseDataSync.fetchAll(bookId: bookId) + ExpenseDataSync.fetchTrashed(bookId: bookId)
        let incomes            = IncomeDataSync.fetchAll(bookId: bookId) + IncomeDataSync.fetchTrashed(bookId: bookId)
        let transfers          = TransferDataSync.fetchAll(bookId: bookId) + TransferDataSync.fetchTrashed(bookId: bookId)
        let categories         = CategoryDataSync.fetchAll(bookId: bookId)
        let paymentMethods     = PaymentMethodSettingDataSync.fetchAll(bookId: bookId)
        let receiveMethods     = ReceiveMethodDataSync.fetchAll(bookId: bookId)
        let bankAccounts       = BankAccountDataSync.fetchAll(bookId: bookId)
        let budgets            = BudgetDataSync.fetchAll(bookId: bookId)
        let recurringBudgets   = RecurringBudgetDataSync.fetchAll(bookId: bookId)
        let fixedExpenses      = FixedExpenseDataSync.fetchAll(bookId: bookId)
        let recurringIncomes   = RecurringIncomeDataSync.fetchAll(bookId: bookId)
        let recurringTransfers = RecurringTransferSettingDataSync.fetchAll(bookId: bookId)

        let settings = BackupSettings(
            themeColorHex: UserDefaults.standard.string(forKey: AppColors.themeColorStorageKey),
            analysisSegmentOrder: UserDefaults.standard.string(forKey: "analysisSegmentOrder"),
            showPreviousMonthCarryover: UserDefaults.standard.bool(forKey: "showPreviousMonthCarryover"),
            creditCardAssetReflectionTiming: UserDefaults.standard.string(forKey: CreditCardAssetReflectionTiming.storageKey),
            accountingMonthStartDay: UserDefaults.standard.object(forKey: AccountingMonthSettings.startDayStorageKey) != nil
                ? UserDefaults.standard.integer(forKey: AccountingMonthSettings.startDayStorageKey) : nil,
            accountingMonthWeekendHolidayAdjustment: UserDefaults.standard.string(forKey: WeekendHolidayAdjustment.storageKey),
            accountingMonthLabelBasis: UserDefaults.standard.string(forKey: AccountingMonthLabelBasis.storageKey),
            calendarWeekStartWeekday: UserDefaults.standard.object(forKey: CalendarWeekStartSettings.storageKey) != nil
                ? UserDefaults.standard.integer(forKey: CalendarWeekStartSettings.storageKey) : nil
        )

        return BackupData(
            version: BackupData.currentVersion,
            createdAt: Date(),
            sourceBookId: bookId,
            books: books.map {
                BookBackupItem(
                    id: $0.id, name: $0.name, createdAt: $0.createdAt,
                    sortOrder: $0.sortOrder, isArchived: $0.isArchived, isMain: $0.isMain
                )
            },
            expenses: expenses.map {
                ExpenseBackupItem(
                    id: $0.id, amount: $0.amount, date: $0.date,
                    paymentMethod: $0.paymentMethod, category: $0.category,
                    memo: $0.memo, createdAt: $0.createdAt,
                    bankAccountId: $0.bankAccountId, fixedExpenseId: $0.fixedExpenseId,
                    receiptImagePath: $0.receiptImagePath, isTestData: $0.isTestData,
                    bookId: $0.bookId, isInTrash: $0.isInTrash, trashedAt: $0.trashedAt
                )
            },
            incomes: incomes.map {
                IncomeBackupItem(
                    id: $0.id, amount: $0.amount, date: $0.date,
                    receiveMethod: $0.receiveMethod, category: $0.category,
                    memo: $0.memo, createdAt: $0.createdAt,
                    bankAccountId: $0.bankAccountId, recurringIncomeId: $0.recurringIncomeId,
                    receiptImagePath: $0.receiptImagePath, isTestData: $0.isTestData,
                    bookId: $0.bookId, isInTrash: $0.isInTrash, trashedAt: $0.trashedAt
                )
            },
            transfers: transfers.map {
                TransferBackupItem(
                    id: $0.id, date: $0.date,
                    fromType: $0.fromType, fromId: $0.fromId, fromName: $0.fromName,
                    toType: $0.toType, toId: $0.toId, toName: $0.toName,
                    amount: $0.amount, feeAmount: $0.feeAmount, memo: $0.memo,
                    receiptImagePath: $0.receiptImagePath,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    recurringTransferSettingId: $0.recurringTransferSettingId,
                    bookId: $0.bookId, isTestData: $0.isTestData,
                    isInTrash: $0.isInTrash, trashedAt: $0.trashedAt
                )
            },
            categories: categories.map {
                CategoryBackupItem(
                    id: $0.id, name: $0.name, colorHex: $0.colorHex, type: $0.type,
                    sortOrder: $0.sortOrder, createdAt: $0.createdAt, bookId: $0.bookId,
                    isTestData: $0.isTestData, isSuspended: $0.isSuspended, isProtected: $0.isProtected
                )
            },
            paymentMethods: paymentMethods.map {
                PaymentMethodBackupItem(
                    id: $0.id, methodName: $0.methodName, type: $0.type,
                    closingDay: $0.closingDay, withdrawalDay: $0.withdrawalDay,
                    adjustPaymentDateToNextBusinessDay: $0.adjustPaymentDateToNextBusinessDay,
                    bankAccount: $0.bankAccount,
                    withdrawalBankAccountId: $0.withdrawalBankAccountId,
                    memo: $0.memo,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt, sortOrder: $0.sortOrder,
                    isActive: $0.isActive, isAsset: $0.isAsset,
                    assetInitialBalance: $0.assetInitialBalance,
                    includeInAnalysis: $0.includeInAnalysis,
                    assetInitialBalanceIncomeId: $0.assetInitialBalanceIncomeId,
                    assetInitialBalanceExpenseId: $0.assetInitialBalanceExpenseId,
                    showInInputPicker: $0.showInInputPicker, useForReceive: $0.useForReceive,
                    showInAnalysis: $0.showInAnalysis,
                    recurringTransferSettingId: $0.recurringTransferSettingId,
                    recurringTransferSettingIds: $0.recurringTransferSettingIds,
                    isTestData: $0.isTestData, bookId: $0.bookId, isLocked: $0.isLocked,
                    colorHex: $0.colorHex, holidayAdjustment: $0.holidayAdjustment
                )
            },
            receiveMethods: receiveMethods.map {
                ReceiveMethodBackupItem(
                    id: $0.id, methodName: $0.methodName, isActive: $0.isActive,
                    sortOrder: $0.sortOrder, createdAt: $0.createdAt, bookId: $0.bookId
                )
            },
            bankAccounts: bankAccounts.map {
                BankAccountBackupItem(
                    id: $0.id, accountName: $0.accountName, initialBalance: $0.initialBalance,
                    memo: $0.memo, isActive: $0.isActive, sortOrder: $0.sortOrder,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    initialBalanceIncomeId: $0.initialBalanceIncomeId,
                    showAsPaymentMethod: $0.showAsPaymentMethod,
                    showAsReceiveMethod: $0.showAsReceiveMethod,
                    showInAnalysis: $0.showInAnalysis,
                    recurringTransferSettingId: $0.recurringTransferSettingId,
                    recurringTransferSettingIds: $0.recurringTransferSettingIds,
                    isTestData: $0.isTestData, bookId: $0.bookId,
                    isAsset: $0.isAsset, isLocked: $0.isLocked,
                    colorHex: $0.colorHex
                )
            },
            budgets: budgets.map {
                BudgetBackupItem(
                    id: $0.id, year: $0.year, month: $0.month,
                    categoryName: $0.categoryName, amount: $0.amount,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt, isTestData: $0.isTestData,
                    bookId: $0.bookId
                )
            },
            recurringBudgets: recurringBudgets.map {
                RecurringBudgetBackupItem(
                    id: $0.id, categoryName: $0.categoryName, amount: $0.amount,
                    isEnabled: $0.isEnabled, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    bookId: $0.bookId
                )
            },
            fixedExpenses: fixedExpenses.map {
                FixedExpenseBackupItem(
                    id: $0.id, name: $0.name, amount: $0.amount,
                    categoryName: $0.categoryName, paymentMethodType: $0.paymentMethodType,
                    paymentMethodId: $0.paymentMethodId, dayOfMonth: $0.dayOfMonth,
                    startDate: $0.startDate, memo: $0.memo, isActive: $0.isActive,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt, isTestData: $0.isTestData,
                    bookId: $0.bookId, isLocked: $0.isLocked,
                    holidayAdjustment: $0.holidayAdjustment, generatedScheduleMonths: $0.generatedScheduleMonths
                )
            },
            recurringIncomes: recurringIncomes.map {
                RecurringIncomeBackupItem(
                    id: $0.id, name: $0.name, amount: $0.amount,
                    categoryName: $0.categoryName, receiveMethodType: $0.receiveMethodType,
                    receiveMethodId: $0.receiveMethodId, dayOfMonth: $0.dayOfMonth,
                    startDate: $0.startDate, memo: $0.memo, isActive: $0.isActive,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt, isTestData: $0.isTestData,
                    bookId: $0.bookId, isLocked: $0.isLocked,
                    holidayAdjustment: $0.holidayAdjustment, generatedScheduleMonths: $0.generatedScheduleMonths
                )
            },
            recurringTransfers: recurringTransfers.map {
                RecurringTransferBackupItem(
                    id: $0.id, fromMethodId: $0.fromMethodId, fromMethodName: $0.fromMethodName,
                    fromType: $0.fromType, toMethodId: $0.toMethodId, toMethodName: $0.toMethodName,
                    toType: $0.toType, amount: $0.amount, day: $0.day, startDate: $0.startDate,
                    isActive: $0.isActive, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    bookId: $0.bookId, isLocked: $0.isLocked, isTestData: $0.isTestData,
                    holidayAdjustment: $0.holidayAdjustment, generatedScheduleMonths: $0.generatedScheduleMonths
                )
            },
            settings: settings
        )
    }

    // MARK: - 復元

    /// targetBookId: 復元先の帳簿（通常は現在選択中の帳簿）。
    /// バックアップが帳簿単位（新方式）なら対象帳簿のデータだけを削除・再作成し、
    /// 他の帳簿には一切触れない。旧方式（帳簿単位対応前）のバックアップだった場合のみ、
    /// 従来通りアプリ全体を丸ごと置き換える（targetBookIdは使われない）。
    /// 復元の完了タイミング：この関数がreturn（または例外throw）した時点で、実データの復元・
    /// 資産グラフキャッシュの再生成（ベストエフォート、失敗しても例外にしない）の両方が
    /// 完了している。以前は資産グラフキャッシュの再生成だけ`Task { }`で生成したきりawaitしない
    /// 設計だったため、呼び出し元（≒このrestore自体）が返った後もバックグラウンドで動き続け、
    /// テストのCoreDataStack破棄タイミングと競合してクラッシュする不具合があった（調査の詳細は
    /// 本関数・applyScopedRestoreのコメント参照）。この関数をasyncにしてawaitすることで、
    /// 「resotre()が返った後に何かが裏で動いている」状態を一切作らない。
    func restore(from url: URL, targetBookId: UUID) async throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        if backup.sourceBookId != nil {
            try await applyScopedRestore(backup, targetBookId: targetBookId)
        } else {
            try applyLegacyFullRestore(backup)
        }
    }

    // MARK: - 復元（新方式：対象帳簿のみ）

    private func applyScopedRestore(_ backup: BackupData, targetBookId: UUID) async throws {
        // 対象帳簿ぶんの既存データだけを削除する。BookData自体（帳簿名・並び順・メイン帳簿フラグ）や
        // 他の帳簿のデータには一切触れない（DataResetServiceは帳簿リセット/削除でも使われている
        // 「対象帳簿だけを消す」の唯一の実装。資産グラフキャッシュもこの中で対象帳簿分だけ削除される）。
        DataResetService.deleteAllData(bookId: targetBookId)

        for e in backup.expenses {
            var obj = ExpenseData(
                amount: e.amount, date: e.date, paymentMethod: e.paymentMethod,
                category: e.category, memo: e.memo, bankAccountId: e.bankAccountId
            )
            obj.id               = e.id
            obj.createdAt        = e.createdAt
            obj.fixedExpenseId   = e.fixedExpenseId
            obj.receiptImagePath = e.receiptImagePath
            obj.isTestData       = e.isTestData
            obj.bookId           = targetBookId
            obj.isInTrash        = e.isInTrash ?? false
            obj.trashedAt        = e.trashedAt
            ExpenseDataSync.insert(obj)
        }

        for i in backup.incomes {
            var obj = IncomeData(
                amount: i.amount, date: i.date, receiveMethod: i.receiveMethod,
                category: i.category, memo: i.memo, bankAccountId: i.bankAccountId
            )
            obj.id                = i.id
            obj.createdAt         = i.createdAt
            obj.recurringIncomeId = i.recurringIncomeId
            obj.receiptImagePath  = i.receiptImagePath
            obj.isTestData        = i.isTestData
            obj.bookId            = targetBookId
            obj.isInTrash         = i.isInTrash ?? false
            obj.trashedAt         = i.trashedAt
            IncomeDataSync.insert(obj)
        }

        for t in backup.transfers {
            var obj = TransferData(
                id: t.id, date: t.date,
                fromType: t.fromType, fromId: t.fromId, fromName: t.fromName,
                toType: t.toType, toId: t.toId, toName: t.toName,
                amount: t.amount, feeAmount: t.feeAmount, memo: t.memo,
                createdAt: t.createdAt, updatedAt: t.updatedAt
            )
            obj.recurringTransferSettingId = t.recurringTransferSettingId
            obj.bookId = targetBookId
            obj.receiptImagePath = t.receiptImagePath
            obj.isTestData = t.isTestData ?? false
            obj.isInTrash = t.isInTrash ?? false
            obj.trashedAt = t.trashedAt
            TransferDataSync.insert(obj)
        }

        var seenCategoryKeys = Set<String>()
        for c in backup.categories {
            let key = "\(c.type)\u{0}\(c.name)"
            guard seenCategoryKeys.insert(key).inserted else { continue }
            var obj = CategoryData(
                name: c.name, colorHex: c.colorHex, type: c.type,
                sortOrder: c.sortOrder, createdAt: c.createdAt
            )
            obj.id = c.id ?? UUID()
            obj.bookId = targetBookId
            obj.isTestData = c.isTestData ?? false
            obj.isSuspended = c.isSuspended ?? false
            obj.isProtected = c.isProtected ?? false
            CategoryDataSync.insert(obj)
        }

        for p in backup.paymentMethods {
            var obj = PaymentMethodSettingData(
                id: p.id, methodName: p.methodName, type: p.type,
                closingDay: p.closingDay, withdrawalDay: p.withdrawalDay,
                bankAccount: p.bankAccount, withdrawalBankAccountId: p.withdrawalBankAccountId,
                createdAt: p.createdAt, updatedAt: p.updatedAt, sortOrder: p.sortOrder
            )
            obj.isActive                    = p.isActive
            obj.isAsset                     = p.isAsset
            obj.assetInitialBalance         = p.assetInitialBalance
            obj.includeInAnalysis           = p.includeInAnalysis
            obj.assetInitialBalanceIncomeId = p.assetInitialBalanceIncomeId
            obj.assetInitialBalanceExpenseId = p.assetInitialBalanceExpenseId
            obj.showInInputPicker           = p.showInInputPicker
            obj.useForReceive               = p.useForReceive
            obj.showInAnalysis              = p.showInAnalysis
            obj.recurringTransferSettingId  = p.recurringTransferSettingId
            obj.recurringTransferSettingIds = p.recurringTransferSettingIds
            obj.isTestData                  = p.isTestData
            obj.isLocked                    = p.isLocked ?? false
            obj.memo                        = p.memo
            obj.adjustPaymentDateToNextBusinessDay = p.adjustPaymentDateToNextBusinessDay ?? true
            obj.colorHex                    = p.colorHex
            obj.holidayAdjustment           = p.holidayAdjustment
            obj.bookId                      = targetBookId
            PaymentMethodSettingDataSync.insert(obj)
        }

        for r in backup.receiveMethods {
            var obj = ReceiveMethodData(
                id: r.id, methodName: r.methodName, isActive: r.isActive,
                sortOrder: r.sortOrder, createdAt: r.createdAt
            )
            obj.bookId = targetBookId
            ReceiveMethodDataSync.insert(obj)
        }

        for b in backup.bankAccounts {
            var obj = BankAccountData(
                id: b.id, accountName: b.accountName, initialBalance: b.initialBalance,
                memo: b.memo, isActive: b.isActive, sortOrder: b.sortOrder,
                createdAt: b.createdAt, updatedAt: b.updatedAt
            )
            obj.initialBalanceIncomeId      = b.initialBalanceIncomeId
            obj.showAsPaymentMethod         = b.showAsPaymentMethod
            obj.showAsReceiveMethod         = b.showAsReceiveMethod
            obj.showInAnalysis              = b.showInAnalysis
            obj.recurringTransferSettingId  = b.recurringTransferSettingId
            obj.recurringTransferSettingIds = b.recurringTransferSettingIds
            obj.isTestData                  = b.isTestData
            obj.isAsset                     = b.isAsset ?? true
            obj.isLocked                    = b.isLocked ?? false
            obj.colorHex                    = b.colorHex
            obj.bookId                      = targetBookId
            BankAccountDataSync.insert(obj)
        }

        for b in backup.budgets {
            var obj = BudgetData(
                id: b.id, year: b.year, month: b.month,
                categoryName: b.categoryName, amount: b.amount,
                createdAt: b.createdAt, updatedAt: b.updatedAt
            )
            obj.isTestData = b.isTestData
            obj.bookId     = targetBookId
            BudgetDataSync.insert(obj)
        }

        for r in backup.recurringBudgets {
            var obj = RecurringBudgetData(
                id: r.id, categoryName: r.categoryName, amount: r.amount, isEnabled: r.isEnabled,
                createdAt: r.createdAt, updatedAt: r.updatedAt
            )
            obj.bookId = targetBookId
            RecurringBudgetDataSync.insert(obj)
        }

        for f in backup.fixedExpenses {
            var obj = FixedExpenseData(
                id: f.id, name: f.name, amount: f.amount, categoryName: f.categoryName,
                paymentMethodType: f.paymentMethodType, paymentMethodId: f.paymentMethodId,
                dayOfMonth: f.dayOfMonth, startDate: f.startDate, memo: f.memo,
                createdAt: f.createdAt, updatedAt: f.updatedAt
            )
            obj.isActive   = f.isActive
            obj.isTestData = f.isTestData
            obj.isLocked   = f.isLocked ?? false
            obj.holidayAdjustment = f.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
            obj.generatedScheduleMonths = f.generatedScheduleMonths ?? []
            obj.bookId     = targetBookId
            FixedExpenseDataSync.insert(obj)
        }

        for r in backup.recurringIncomes {
            var obj = RecurringIncomeData(
                id: r.id, name: r.name, amount: r.amount, categoryName: r.categoryName,
                receiveMethodType: r.receiveMethodType, receiveMethodId: r.receiveMethodId,
                dayOfMonth: r.dayOfMonth, startDate: r.startDate, memo: r.memo,
                createdAt: r.createdAt, updatedAt: r.updatedAt
            )
            obj.isActive   = r.isActive
            obj.isTestData = r.isTestData
            obj.isLocked   = r.isLocked ?? false
            obj.holidayAdjustment = r.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
            obj.generatedScheduleMonths = r.generatedScheduleMonths ?? []
            obj.bookId     = targetBookId
            RecurringIncomeDataSync.insert(obj)
        }

        for r in backup.recurringTransfers {
            var obj = RecurringTransferSettingData(
                id: r.id, fromMethodId: r.fromMethodId, fromMethodName: r.fromMethodName,
                fromType: r.fromType, toMethodId: r.toMethodId, toMethodName: r.toMethodName,
                toType: r.toType, amount: r.amount, day: r.day,
                startDate: r.startDate ?? r.createdAt, createdAt: r.createdAt, updatedAt: r.updatedAt
            )
            obj.isActive  = r.isActive
            obj.isLocked  = r.isLocked ?? false
            obj.isTestData = r.isTestData ?? false
            obj.holidayAdjustment = r.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
            obj.generatedScheduleMonths = r.generatedScheduleMonths ?? []
            obj.bookId    = targetBookId
            RecurringTransferSettingDataSync.insert(obj)
        }

        // 対象帳簿のデータだけが総入れ替えされたので、全帳簿分のスナップショットを作り直す
        // （他帳簿のsnapshotは元データに触っていないため再計算しても値は変わらない）。
        SnapshotUpdateService.handle(.fullRebuildRequested)

        // 資産グラフキャッシュは対象帳簿分だけ再生成する（他帳簿のキャッシュには触れない）。
        // DataResetService.deleteAllDataで対象帳簿分のキャッシュは既に削除済みなので、
        // ここで再生成に失敗しても「次回表示時に再計算される空の状態」のままで済み、
        // 古い値が表示され続けることはない（＝実データの復元自体の成否とは独立させる。
        // そのためここで投げられた例外はrestore()全体の失敗にはしない）。
        //
        // 【重要】以前は`Task { try? await ... }`として生成したきりawaitしない設計だったため、
        // この関数（＝restore()）が返った後もバックグラウンドで動き続け、CoreDataStackが
        // 既に破棄された後にNSManagedObjectContext.save()を呼んでcrash（NSInternalInconsistencyException。
        // try?はSwiftのErrorしか捕捉できず、Core Dataが投げるNSExceptionは捕捉できないため防げなかった）
        // する不具合があった。ここでは必ずawaitし、「この関数が返った時点で再生成も完了している」
        // ことを保証する（失敗時はログに残すだけで、復元処理自体は成功として扱う）。
        let maxPoints = AssetGraphSettings.clamped(
            UserDefaults.standard.object(forKey: AssetGraphSettings.storageKey) != nil
                ? UserDefaults.standard.integer(forKey: AssetGraphSettings.storageKey)
                : AssetGraphSettings.defaultValue
        )
        do {
            try await AssetGraphCacheService.rebuildTotalAssetsCache(bookId: targetBookId, maxPoints: maxPoints)
        } catch {
            TimingDebugLog.write("BackupManager: restore後の資産グラフキャッシュ再生成に失敗（復元自体は成功扱い）: \(error)")
        }
    }

    // MARK: - 復元（旧方式：帳簿単位対応前のバックアップとの後方互換）

    private func applyLegacyFullRestore(_ backup: BackupData) throws {
        // 旧バックアップ（帳簿機能導入前）にはbooksが無いため、その場合は既存の帳簿構成を残し、
        // 復元後のBookMigrationService.migrateIfNeededでnilなbookIdをメイン帳簿へ割り当てる。
        if let books = backup.books {
            BookDataSync.replaceAll(with: books)
        }

        ExpenseDataSync.deleteAll()
        IncomeDataSync.deleteAll()
        TransferDataSync.deleteAll()
        // Core Data移行（手順4・CategoryData）：並行書き込み（全削除。挿入は復元ループ内で行う）
        CategoryDataSync.deleteAll()
        // Core Data移行（手順4・PaymentMethodSettingData）：並行書き込み（全削除。挿入は復元ループ内で行う）
        PaymentMethodSettingDataSync.deleteAll()
        ReceiveMethodDataSync.deleteAll()
        BankAccountDataSync.deleteAll()
        BudgetDataSync.deleteAll()
        RecurringBudgetDataSync.deleteAll()
        FixedExpenseDataSync.deleteAll()
        RecurringIncomeDataSync.deleteAll()
        RecurringTransferSettingDataSync.deleteAll()

        for e in backup.expenses {
            var obj = ExpenseData(
                amount: e.amount, date: e.date, paymentMethod: e.paymentMethod,
                category: e.category, memo: e.memo, bankAccountId: e.bankAccountId
            )
            obj.id               = e.id
            obj.createdAt        = e.createdAt
            obj.fixedExpenseId   = e.fixedExpenseId
            obj.receiptImagePath = e.receiptImagePath
            obj.isTestData       = e.isTestData
            obj.bookId           = e.bookId
            obj.isInTrash        = e.isInTrash ?? false
            obj.trashedAt        = e.trashedAt
            ExpenseDataSync.insert(obj)
        }

        for i in backup.incomes {
            var obj = IncomeData(
                amount: i.amount, date: i.date, receiveMethod: i.receiveMethod,
                category: i.category, memo: i.memo, bankAccountId: i.bankAccountId
            )
            obj.id                = i.id
            obj.createdAt         = i.createdAt
            obj.recurringIncomeId = i.recurringIncomeId
            obj.receiptImagePath  = i.receiptImagePath
            obj.isTestData        = i.isTestData
            obj.bookId            = i.bookId
            obj.isInTrash         = i.isInTrash ?? false
            obj.trashedAt         = i.trashedAt
            IncomeDataSync.insert(obj)
        }

        for t in backup.transfers {
            var obj = TransferData(
                id: t.id, date: t.date,
                fromType: t.fromType, fromId: t.fromId, fromName: t.fromName,
                toType: t.toType, toId: t.toId, toName: t.toName,
                amount: t.amount, feeAmount: t.feeAmount, memo: t.memo,
                createdAt: t.createdAt, updatedAt: t.updatedAt
            )
            obj.recurringTransferSettingId = t.recurringTransferSettingId
            obj.bookId = t.bookId
            obj.receiptImagePath = t.receiptImagePath
            obj.isTestData = t.isTestData ?? false
            obj.isInTrash = t.isInTrash ?? false
            obj.trashedAt = t.trashedAt
            TransferDataSync.insert(obj)
        }

        // バックアップファイル自体に同じ帳簿+種別+同名のカテゴリーが複数含まれていた場合に備えて、
        // 復元時にも重複を除去する（最初に出てきたものだけを残す）。
        var seenCategoryKeys = Set<String>()
        for c in backup.categories {
            let key = "\(c.bookId?.uuidString ?? "")\u{0}\(c.type)\u{0}\(c.name)"
            guard seenCategoryKeys.insert(key).inserted else { continue }
            var obj = CategoryData(
                name: c.name, colorHex: c.colorHex, type: c.type,
                sortOrder: c.sortOrder, createdAt: c.createdAt
            )
            // 旧バックアップ（idが無い）は新規UUIDを生成する。新しいバックアップは元のUUIDを維持する。
            obj.id = c.id ?? UUID()
            obj.bookId = c.bookId
            obj.isTestData = c.isTestData ?? false
            obj.isSuspended = c.isSuspended ?? false
            obj.isProtected = c.isProtected ?? false
            CategoryDataSync.insert(obj)
        }

        for p in backup.paymentMethods {
            var obj = PaymentMethodSettingData(
                id: p.id, methodName: p.methodName, type: p.type,
                closingDay: p.closingDay, withdrawalDay: p.withdrawalDay,
                bankAccount: p.bankAccount, withdrawalBankAccountId: p.withdrawalBankAccountId,
                createdAt: p.createdAt, updatedAt: p.updatedAt, sortOrder: p.sortOrder
            )
            obj.isActive                    = p.isActive
            obj.isAsset                     = p.isAsset
            obj.assetInitialBalance         = p.assetInitialBalance
            obj.includeInAnalysis           = p.includeInAnalysis
            obj.assetInitialBalanceIncomeId = p.assetInitialBalanceIncomeId
            obj.assetInitialBalanceExpenseId = p.assetInitialBalanceExpenseId
            obj.showInInputPicker           = p.showInInputPicker
            obj.useForReceive               = p.useForReceive
            obj.showInAnalysis              = p.showInAnalysis
            obj.recurringTransferSettingId  = p.recurringTransferSettingId
            obj.recurringTransferSettingIds = p.recurringTransferSettingIds
            obj.isTestData                  = p.isTestData
            obj.isLocked                    = p.isLocked ?? false
            obj.memo                        = p.memo
            obj.adjustPaymentDateToNextBusinessDay = p.adjustPaymentDateToNextBusinessDay ?? true
            obj.colorHex                    = p.colorHex
            obj.holidayAdjustment           = p.holidayAdjustment
            obj.bookId                      = p.bookId
            PaymentMethodSettingDataSync.insert(obj)
        }

        for r in backup.receiveMethods {
            var obj = ReceiveMethodData(
                id: r.id, methodName: r.methodName, isActive: r.isActive,
                sortOrder: r.sortOrder, createdAt: r.createdAt
            )
            obj.bookId = r.bookId
            ReceiveMethodDataSync.insert(obj)
        }

        for b in backup.bankAccounts {
            var obj = BankAccountData(
                id: b.id, accountName: b.accountName, initialBalance: b.initialBalance,
                memo: b.memo, isActive: b.isActive, sortOrder: b.sortOrder,
                createdAt: b.createdAt, updatedAt: b.updatedAt
            )
            obj.initialBalanceIncomeId      = b.initialBalanceIncomeId
            obj.showAsPaymentMethod         = b.showAsPaymentMethod
            obj.showAsReceiveMethod         = b.showAsReceiveMethod
            obj.showInAnalysis              = b.showInAnalysis
            obj.recurringTransferSettingId  = b.recurringTransferSettingId
            obj.recurringTransferSettingIds = b.recurringTransferSettingIds
            obj.isTestData                  = b.isTestData
            obj.isAsset                     = b.isAsset ?? true
            obj.isLocked                    = b.isLocked ?? false
            obj.colorHex                    = b.colorHex
            obj.bookId                      = b.bookId
            BankAccountDataSync.insert(obj)
        }

        for b in backup.budgets {
            var obj = BudgetData(
                id: b.id, year: b.year, month: b.month,
                categoryName: b.categoryName, amount: b.amount,
                createdAt: b.createdAt, updatedAt: b.updatedAt
            )
            obj.isTestData = b.isTestData
            obj.bookId     = b.bookId
            BudgetDataSync.insert(obj)
        }

        for r in backup.recurringBudgets {
            var obj = RecurringBudgetData(
                id: r.id, categoryName: r.categoryName, amount: r.amount, isEnabled: r.isEnabled,
                createdAt: r.createdAt, updatedAt: r.updatedAt
            )
            obj.bookId = r.bookId
            RecurringBudgetDataSync.insert(obj)
        }

        for f in backup.fixedExpenses {
            var obj = FixedExpenseData(
                id: f.id, name: f.name, amount: f.amount, categoryName: f.categoryName,
                paymentMethodType: f.paymentMethodType, paymentMethodId: f.paymentMethodId,
                dayOfMonth: f.dayOfMonth, startDate: f.startDate, memo: f.memo,
                createdAt: f.createdAt, updatedAt: f.updatedAt
            )
            obj.isActive   = f.isActive
            obj.isTestData = f.isTestData
            obj.isLocked   = f.isLocked ?? false
            obj.holidayAdjustment = f.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
            obj.generatedScheduleMonths = f.generatedScheduleMonths ?? []
            obj.bookId     = f.bookId
            FixedExpenseDataSync.insert(obj)
        }

        for r in backup.recurringIncomes {
            var obj = RecurringIncomeData(
                id: r.id, name: r.name, amount: r.amount, categoryName: r.categoryName,
                receiveMethodType: r.receiveMethodType, receiveMethodId: r.receiveMethodId,
                dayOfMonth: r.dayOfMonth, startDate: r.startDate, memo: r.memo,
                createdAt: r.createdAt, updatedAt: r.updatedAt
            )
            obj.isActive   = r.isActive
            obj.isTestData = r.isTestData
            obj.isLocked   = r.isLocked ?? false
            obj.holidayAdjustment = r.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
            obj.generatedScheduleMonths = r.generatedScheduleMonths ?? []
            obj.bookId     = r.bookId
            RecurringIncomeDataSync.insert(obj)
        }

        for r in backup.recurringTransfers {
            var obj = RecurringTransferSettingData(
                id: r.id, fromMethodId: r.fromMethodId, fromMethodName: r.fromMethodName,
                fromType: r.fromType, toMethodId: r.toMethodId, toMethodName: r.toMethodName,
                toType: r.toType, amount: r.amount, day: r.day,
                startDate: r.startDate ?? r.createdAt, createdAt: r.createdAt, updatedAt: r.updatedAt
            )
            obj.isActive  = r.isActive
            obj.isLocked  = r.isLocked ?? false
            obj.isTestData = r.isTestData ?? false
            obj.holidayAdjustment = r.holidayAdjustment ?? WeekendHolidayAdjustment.shiftLater.rawValue
            obj.generatedScheduleMonths = r.generatedScheduleMonths ?? []
            obj.bookId    = r.bookId
            RecurringTransferSettingDataSync.insert(obj)
        }

        let s = backup.settings
        if let hex = s.themeColorHex {
            UserDefaults.standard.set(hex, forKey: AppColors.themeColorStorageKey)
        }
        if let order = s.analysisSegmentOrder {
            UserDefaults.standard.set(order, forKey: "analysisSegmentOrder")
        }
        UserDefaults.standard.set(s.showPreviousMonthCarryover, forKey: "showPreviousMonthCarryover")
        if let timing = s.creditCardAssetReflectionTiming {
            UserDefaults.standard.set(timing, forKey: CreditCardAssetReflectionTiming.storageKey)
        }
        if let day = s.accountingMonthStartDay {
            UserDefaults.standard.set(day, forKey: AccountingMonthSettings.startDayStorageKey)
        }
        if let adjustment = s.accountingMonthWeekendHolidayAdjustment {
            UserDefaults.standard.set(adjustment, forKey: WeekendHolidayAdjustment.storageKey)
        }
        if let labelBasis = s.accountingMonthLabelBasis {
            UserDefaults.standard.set(labelBasis, forKey: AccountingMonthLabelBasis.storageKey)
        }
        if let weekday = s.calendarWeekStartWeekday {
            UserDefaults.standard.set(weekday, forKey: CalendarWeekStartSettings.storageKey)
        }

        // 旧バックアップ復元時など、bookIdがnilのまま残ったデータをメイン帳簿へ割り当てる
        // （帳簿機能導入前のバックアップにはbooks自体が無いため、既存の帳簿構成にバックフィルする）。
        BookMigrationService.migrateIfNeeded()
        // 全データが総入れ替えされるため、日次・月次スナップショットも全期間作り直す
        SnapshotUpdateService.handle(.fullRebuildRequested)
    }
}
