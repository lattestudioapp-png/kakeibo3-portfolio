import Foundation

// MARK: - 移行完了の永続記録(Manifest + UserDefaultsフラグ)
//
// 「移行済みフラグだけでなくCore Data側の状態も確認する」方針のため、完了判定は
// 常に3つ(UserDefaultsフラグ・MigrationManifest.json・本番ストアのNSStoreUUIDKey)の
// 一致で行う。いずれか欠落・不一致なら「未完了」として扱い、Case A/B/C判定へ戻す。

enum MigrationCompletionRecorder {

    static let manifestFileName = "MigrationManifest.json"
    static let userDefaultsKey = "swiftDataMigrationCompletedV1"

    // MARK: - Manifest永続化

    /// 存在しない・壊れている場合はnilを返す(クラッシュしない)。
    static func loadPersistedManifest(from directory: URL) -> MigrationManifest? {
        let url = directory.appendingPathComponent(manifestFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MigrationManifest.self, from: data)
    }

    static func savePersistedManifest(_ manifest: MigrationManifest, to directory: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent(manifestFileName), options: .atomic)
    }

    // MARK: - UserDefaultsフラグ

    static func markCompleted(in userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: userDefaultsKey)
    }

    static func isFlagSet(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: userDefaultsKey)
    }

    // MARK: - 完了判定(3点の一致が必要)

    static func isAlreadyCompleted(
        manifestDirectory: URL,
        currentStoreIdentifier: String?,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard isFlagSet(in: userDefaults) else { return false }
        guard let manifest = loadPersistedManifest(from: manifestDirectory) else { return false }
        guard let targetId = manifest.targetStoreIdentifier, let currentId = currentStoreIdentifier else { return false }
        return targetId == currentId
    }
}
