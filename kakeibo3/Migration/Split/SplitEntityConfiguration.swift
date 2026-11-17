import CoreData

// MARK: - Cloud/Local Entity一覧(Step 1のxcdatamodel Configuration割り当てが唯一の正)
//
// ハードコードした固定リストを別途持つと、将来Step 1のConfiguration割り当てを変更した際に
// ここだけ更新漏れするリスクがあるため、実行時に`NSManagedObjectModel.entities(forConfigurationName:)`
// でモデル自身から動的に取得する(モデルのConfiguration定義が唯一のソース)。

enum SplitEntityConfiguration {

    static func cloudEntityNames(model: NSManagedObjectModel) -> [String] {
        entityNames(model: model, configurationName: CoreDataStack.cloudConfigurationName)
    }

    static func localEntityNames(model: NSManagedObjectModel) -> [String] {
        entityNames(model: model, configurationName: CoreDataStack.localConfigurationName)
    }

    static func allEntityNames(model: NSManagedObjectModel) -> [String] {
        cloudEntityNames(model: model) + localEntityNames(model: model)
    }

    private static func entityNames(model: NSManagedObjectModel, configurationName: String) -> [String] {
        (model.entities(forConfigurationName: configurationName) ?? [])
            .compactMap(\.name)
            .sorted()
    }
}
