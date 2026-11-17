//
//  CategoryRepository.swift
//  kakeibo3
//
//  Created by 楠本陸 on 2026/05/30.
//


import Foundation
import SwiftUI

// MARK: - カテゴリーRepository

/**
 CategoryData の作成・更新・削除・並び替えを担当するRepository。

 ViewModelからSwiftDataの具体的な保存処理を分離する。
 */
protocol CategoryRepository {
    func createDefaultCategoriesIfNeeded(
        existingCategories: [CategoryData],
        bookId: UUID
    ) throws

    func categoryNames(
        type: String,
        categories: [CategoryData]
    ) -> [String]

    func sortedCategories(
        type: String,
        categories: [CategoryData]
    ) -> [CategoryData]

    func addCategory(
        name: String,
        type: String,
        existingCategories: [CategoryData],
        bookId: UUID
    ) throws

    func renameCategory(
        category: CategoryData,
        newName: String,
        existingCategories: [CategoryData]
    ) throws

    func deleteCategory(
        category: CategoryData
    ) throws

    func moveCategories(
        categories: [CategoryData],
        from source: IndexSet,
        to destination: Int
    ) throws
}

// MARK: - エラー

enum CategoryRepositoryError: Error {
    case duplicateName
    case protectedCategory
    case suspendedNameExists(CategoryData)
}

// MARK: - SwiftDataカテゴリーRepository

struct SwiftDataCategoryRepository: CategoryRepository {

    // MARK: - 初期カテゴリー

    /**
     支出・収入の初期カテゴリーをSwiftDataに作成する。

     すでに同じ種別のカテゴリーが存在する場合は、その種別は作成しない。
     */
    func createDefaultCategoriesIfNeeded(
        existingCategories: [CategoryData],
        bookId: UUID
    ) throws {
        let expenseSetting = ExpenseInputSetting()
        let incomeSetting = IncomeInputSetting()
        let bookCategories = existingCategories.filter { $0.bookId == bookId }

        // 【調査用診断ログ】existingCategoriesが呼び出し元から渡された(潜在的に古い可能性のある)
        // リストであり、Core Dataへの直接再フェッチではないことが原因かを確認するため、
        // 渡されたexistingCategories件数と、この時点でCore Dataへ直接再フェッチした件数を
        // 両方記録する（調査内容9：bookId不整合・タイミング不整合の切り分け）。
        let freshCount = CategoryDataSync.fetchAll(bookId: bookId).count
        DiagnosticLog.write(
            "CategoryRepository.createDefaultCategoriesIfNeeded: bookId=\(bookId.uuidString.prefix(8)) "
            + "passedInExistingCount(thisBook)=\(bookCategories.count) freshFetchCount=\(freshCount)"
        )

        if !bookCategories.contains(where: { $0.type == expenseSetting.typeName }) {
            insertDefaultCategories(
                names: expenseSetting.categories,
                type: expenseSetting.typeName,
                bookId: bookId
            )
        }

        if !bookCategories.contains(where: { $0.type == incomeSetting.typeName }) {
            insertDefaultCategories(
                names: incomeSetting.categories,
                type: incomeSetting.typeName,
                bookId: bookId
            )
        }
    }

    // MARK: - 取得補助

    /**
     指定した種別のカテゴリー名一覧を並び順どおりに返す。
     */
    func categoryNames(
        type: String,
        categories: [CategoryData]
    ) -> [String] {
        sortedCategories(type: type, categories: categories).map { $0.name }
    }

    /**
     指定した種別のカテゴリーをsortOrder順に返す。
     使用停止中（isSuspended）のカテゴリーは、新規入力などの選択候補から除外するため含めない。
     */
    func sortedCategories(
        type: String,
        categories: [CategoryData]
    ) -> [CategoryData] {
        categories
            .filter { $0.type == type && !$0.isSuspended }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                } else {
                    return $0.sortOrder < $1.sortOrder
                }
            }
    }

    // MARK: - 追加

    /**
     カテゴリーを追加する。
     同じ種別に同名カテゴリーがある場合は追加しない。
     */
    func addCategory(
        name: String,
        type: String,
        existingCategories: [CategoryData],
        bookId: UUID
    ) throws {
        let trimmedName = normalizedName(name)

        guard !trimmedName.isEmpty else {
            return
        }

        // existingCategories は呼び出し側の@Queryスナップショットで、
        // 直前の保存がまだ反映されていない可能性がある（連続操作での重複作成を防ぐため、
        // 追加直前にCore Data側から取り直したものでも重複チェックする）。
        // 重複チェック・並び順・色選択は同じ帳簿内のカテゴリーだけを対象にする。
        let freshCategories = CategoryDataSync.fetchAll(bookId: bookId)

        let sameNameMatches = freshCategories.filter { $0.type == type && $0.name == trimmedName }

        guard !sameNameMatches.contains(where: { !$0.isSuspended }) else {
            throw CategoryRepositoryError.duplicateName
        }

        // 使用停止中の同名カテゴリーがある場合は新規作成せず、呼び出し側で再開確認する
        if let suspended = sameNameMatches.first(where: { $0.isSuspended }) {
            throw CategoryRepositoryError.suspendedNameExists(suspended)
        }

        let sameTypeCategories = freshCategories.filter { $0.type == type }
        let nextSortOrder = (sameTypeCategories.map { $0.sortOrder }.max() ?? -1) + 1

        let usedColorHexes = sameTypeCategories.map { $0.colorHex }
        let newColorHex = CategoryColorPalette.nextDistinctColor(existingColors: usedColorHexes)

        var category = CategoryData(
            name: trimmedName,
            colorHex: newColorHex,
            type: type,
            sortOrder: nextSortOrder
        )
        category.bookId = bookId

        guard CategoryDataSync.insertChecked(category) else {
            throw TransactionSaveError.persistenceFailed
        }
    }

    // MARK: - 名前変更

    /**
     カテゴリー名を変更する。
     同じ種別に同名カテゴリーがある場合は変更しない。
     */
    func renameCategory(
        category: CategoryData,
        newName: String,
        existingCategories: [CategoryData]
    ) throws {
        let trimmedName = normalizedName(newName)

        guard !trimmedName.isEmpty else {
            return
        }

        // existingCategoriesの代わりにCore Dataから取り直した最新データで重複チェックする。
        // 自分自身の除外はidの一致で判定する。
        // 重複チェックは同じ帳簿内のカテゴリーだけを対象にする。
        let freshCategories = CategoryDataSync.fetchAll()
        let duplicated = freshCategories.contains { otherCategory in
            otherCategory.id != category.id &&
            otherCategory.type == category.type &&
            otherCategory.name == trimmedName &&
            otherCategory.bookId == category.bookId
        }

        guard !duplicated else {
            throw CategoryRepositoryError.duplicateName
        }

        var renamed = category
        renamed.name = trimmedName
        CategoryDataSync.update(renamed)
        SnapshotUpdateService.handle(.categoryRenamed)
    }

    // MARK: - 削除

    /**
     カテゴリーを削除する。
     */
    func deleteCategory(
        category: CategoryData
    ) throws {
        // 初期残高カテゴリーなど削除不可カテゴリーは削除しない。
        // isProtectedフラグに加え、旧データ（フラグ未付与）への安全網として
        // 同一帳簿内の「初期残高」収入カテゴリーも保護対象とする。
        let isLegacyInitialBalanceCategory = category.name == "初期残高" && category.type == "収入"
        guard !category.isProtected && !isLegacyInitialBalanceCategory else {
            throw CategoryRepositoryError.protectedCategory
        }

        CategoryDataSync.delete(id: category.id)
        SnapshotUpdateService.handle(.categoryDeleted)
    }

    // MARK: - 並び替え

    /**
     同じ種別のカテゴリーを並び替え、sortOrderを更新する。
     */
    func moveCategories(
        categories: [CategoryData],
        from source: IndexSet,
        to destination: Int
    ) throws {
        var sortedCategories = categories.sorted { $0.sortOrder < $1.sortOrder }
        sortedCategories.move(fromOffsets: source, toOffset: destination)

        for index in sortedCategories.indices {
            sortedCategories[index].sortOrder = index
        }

        for category in sortedCategories {
            CategoryDataSync.update(category)
        }
    }

    // MARK: - 内部処理

    private static let defaultColorMap: [String: String] = [
        // 支出
        "食費": "#6FA58C",
        "交通費": "#7FA6D8",
        "日用品": "#B9DCC8",
        "娯楽": "#D0B8E8",
        "その他支出": "#C8C8C8",
        // 収入
        "給料": "#5A9ED8",
        "お小遣い": "#A8C8F0",
        "副業": "#9AB8D8",
        "その他収入": "#C8C8C8",
    ]

    private func insertDefaultCategories(
        names: [String],
        type: String,
        bookId: UUID
    ) {
        for (index, name) in names.enumerated() {
            let colorHex = Self.defaultColorMap[name] ?? "#CFCFCF"
            var category = CategoryData(
                name: name,
                colorHex: colorHex,
                type: type,
                sortOrder: index
            )
            category.bookId = bookId
            CategoryDataSync.insert(category)
        }
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
