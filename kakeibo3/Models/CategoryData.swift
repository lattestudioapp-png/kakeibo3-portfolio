import Foundation

// MARK: - カテゴリーデータ

/**
 カテゴリーの設定を表すドメインモデル（Core Data移行 Phase 1）。

 保存する内容:
 - カテゴリー名
 - グラフなどで使う色
 - 支出カテゴリーか収入カテゴリーか
 - 並び順
 - 作成日時

 ExpenseData / IncomeData は category 文字列だけを持ち、
 色はこの CategoryData 側で管理する。永続化はCore Data（`CDCategoryData`）が担い、
 このstructは画面・ロジック層が触るフレームワーク非依存のドメイン表現
 （`CategoryDataSync`がCDCategoryDataとの変換を担当する）。
 */
struct CategoryData: Identifiable, Hashable {

    /**
     安定した識別子。分析Viewの集計スナップショットがカテゴリーを
     名前ではなくIDで参照するために使う（名前変更に対して堅牢）。
     */
    var id: UUID

    /**
     カテゴリー名。
     例:
     - 食費
     - 外食
     - 給料
     */
    var name: String

    /**
     カテゴリー色。
     16進カラー文字列で保存する。
     例:
     - "#4A7DBA"
     - "#FF9999"
     */
    var colorHex: String

    /**
     カテゴリー種別。
     "支出" または "収入" を入れる。
     */
    var type: String

    /**
     並び順。
     カテゴリー編集画面で並び替えるときに使う。
     */
    var sortOrder: Int

    /**
     作成日時。
     */
    var createdAt: Date

    var isTestData: Bool = false

    // 紐づく BookData の UUID（nil = マイグレーション未実施。BookMigrationService参照）
    var bookId: UUID? = nil

    /**
     使用停止フラグ。
     true の場合、新規入力などのカテゴリー選択画面からは非表示になるが、
     過去の取引データ・分析・カレンダー・履歴・検索結果には影響しない。
     */
    var isSuspended: Bool = false

    /**
     削除不可カテゴリー用フラグ（初期残高カテゴリーなど）。
     true の場合、カテゴリー詳細画面からの削除を拒否する。
     */
    var isProtected: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        type: String,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.type = type
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
