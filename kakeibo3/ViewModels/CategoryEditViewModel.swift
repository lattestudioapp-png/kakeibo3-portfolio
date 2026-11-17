import Foundation
import Combine

// MARK: - カテゴリー編集ViewModel

/**
 カテゴリー編集画面の状態と操作を管理するViewModel。

 実際の保存・更新・削除は CategoryRepository に任せる。
 */
final class CategoryEditViewModel: ObservableObject {

    // MARK: - 入力状態

    /**
     追加アラートで入力中のカテゴリー名。
     */
    @Published var newCategoryName = ""

    /**
     リネームアラートで入力中のカテゴリー名。
     */
    @Published var editingCategoryName = ""

    // MARK: - 表示状態

    /**
     カテゴリー追加アラートを表示するかどうか。
     */
    @Published var isAddAlertPresented = false

    /**
     カテゴリー名変更アラートを表示するかどうか。
     */
    @Published var isRenameAlertPresented = false

    /**
     エラーアラートに表示するメッセージ（nilでない間、アラート表示中）。
     */
    @Published var errorAlertMessage: String?

    /**
     使用停止中の同名カテゴリーが見つかり、再開確認アラートを表示すべき対象（nilでない間、アラート表示中）。
     */
    @Published var suspendedCategoryPendingReactivation: CategoryData?

    // MARK: - Repository

    private let categoryRepository: any CategoryRepository

    // MARK: - 初期化

    init(categoryRepository: any CategoryRepository = SwiftDataCategoryRepository()) {
        self.categoryRepository = categoryRepository
    }

    // MARK: - 初期カテゴリー作成

    /**
     カテゴリーがない場合、初期カテゴリーを作成する。
     */
    func createDefaultCategoriesIfNeeded(
        existingCategories: [CategoryData],
        bookId: UUID
    ) {
        do {
            try categoryRepository.createDefaultCategoriesIfNeeded(
                existingCategories: existingCategories,
                bookId: bookId
            )
        } catch {
            print("初期カテゴリー作成エラー: \(error)")
        }
    }

    // MARK: - 取得補助

    /**
     指定種別のカテゴリーを並び順どおりに返す。
     */
    func sortedCategories(
        type: String,
        categories: [CategoryData]
    ) -> [CategoryData] {
        categoryRepository.sortedCategories(
            type: type,
            categories: categories
        )
    }

    /**
     指定種別のカテゴリー名だけを並び順どおりに返す。
     */
    func categoryNames(
        type: String,
        categories: [CategoryData]
    ) -> [String] {
        categoryRepository.categoryNames(
            type: type,
            categories: categories
        )
    }

    // MARK: - 追加

    /**
     カテゴリーを追加する。
     */
    /// 【重要】以前はこの関数の最後で常に`newCategoryName = ""`していたため、
    /// Core Dataへの永続化が実際に失敗した場合でも入力したカテゴリー名が消え、
    /// かつその失敗がどこにも表示されない（duplicateName/suspendedNameExists以外の
    /// 例外はprint()のみ）ため、ユーザーからは「何も起きず追加できない」ように見えていた。
    /// 成功時のみ入力をクリアし、それ以外の失敗も必ずerrorAlertMessageへ反映する。
    func addCategory(
        type: String,
        existingCategories: [CategoryData],
        bookId: UUID
    ) {
        do {
            try categoryRepository.addCategory(
                name: newCategoryName,
                type: type,
                existingCategories: existingCategories,
                bookId: bookId
            )
            newCategoryName = ""
        } catch CategoryRepositoryError.duplicateName {
            errorAlertMessage = DuplicateNameChecker.errorMessage
        } catch CategoryRepositoryError.suspendedNameExists(let suspended) {
            suspendedCategoryPendingReactivation = suspended
        } catch let error as TransactionSaveError {
            errorAlertMessage = error.errorDescription
        } catch {
            errorAlertMessage = "カテゴリーの追加に失敗しました: \(error.localizedDescription)"
        }
    }

    /**
     使用停止中のカテゴリーを再開する（isSuspendedをfalseに戻す）。
     */
    func reactivateSuspendedCategory(
        _ category: CategoryData
    ) {
        var reactivated = category
        reactivated.isSuspended = false
        CategoryDataSync.update(reactivated)
        suspendedCategoryPendingReactivation = nil
    }

    // MARK: - 名前変更

    /**
     カテゴリー名を変更する。
     */
    func renameCategory(
        category: CategoryData,
        newName: String,
        existingCategories: [CategoryData]
    ) {
        do {
            try categoryRepository.renameCategory(
                category: category,
                newName: newName,
                existingCategories: existingCategories
            )
        } catch CategoryRepositoryError.duplicateName {
            errorAlertMessage = DuplicateNameChecker.errorMessage
        } catch {
            print("カテゴリー名変更エラー: \(error)")
        }
    }

    // MARK: - 削除

    /**
     カテゴリーを削除する。
     */
    func deleteCategory(
        category: CategoryData
    ) {
        do {
            try categoryRepository.deleteCategory(
                category: category
            )
        } catch CategoryRepositoryError.protectedCategory {
            errorAlertMessage = "初期残高カテゴリーは削除できません。"
        } catch {
            print("カテゴリー削除エラー: \(error)")
        }
    }

    // MARK: - 並び替え

    /**
     カテゴリーを並び替える。
     */
    func moveCategories(
        categories: [CategoryData],
        from source: IndexSet,
        to destination: Int
    ) {
        do {
            try categoryRepository.moveCategories(
                categories: categories,
                from: source,
                to: destination
            )
        } catch {
            print("カテゴリー並び替えエラー: \(error)")
        }
    }
}
