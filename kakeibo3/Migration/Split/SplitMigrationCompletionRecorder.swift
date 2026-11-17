import Foundation

// MARK: - Cloud/Local分割移行の完了記録(Manifest + UserDefaultsフラグ、Step 2B専用)
//
// 既存MigrationCompletionRecorderと同じ「複数の独立した証拠(UserDefaultsフラグ・
// Manifest JSON・本番ストアのNSStoreUUIDKey)の一致で完了判定する」方針を踏襲する。
// Cloud/Local2ストアぶんのStore UUIDが両方一致した場合のみ「済」とみなす。

enum SplitMigrationCompletionRecorder {

    static let manifestFileName = "SplitMigrationManifest.json"
    static let userDefaultsKey = "coreDataSplitMigrationCompletedV1"

    // MARK: - Manifest永続化

    static func loadPersistedManifest(from directory: URL) -> SplitMigrationManifest? {
        let url = directory.appendingPathComponent(manifestFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SplitMigrationManifest.self, from: data)
    }

    static func savePersistedManifest(_ manifest: SplitMigrationManifest, to directory: URL) throws {
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

    // MARK: - 完了判定(フラグ+Manifest+Cloud/Local両方のStore UUID一致が必要)

    static func isAlreadyCompleted(
        manifestDirectory: URL,
        currentCloudStoreIdentifier: String?,
        currentLocalStoreIdentifier: String?,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard isFlagSet(in: userDefaults) else { return false }
        guard let manifest = loadPersistedManifest(from: manifestDirectory) else { return false }
        guard manifest.migrationState == .promoted else { return false }
        guard let expectedCloud = manifest.cloudStoreIdentifier, let expectedLocal = manifest.localStoreIdentifier,
              let currentCloud = currentCloudStoreIdentifier, let currentLocal = currentLocalStoreIdentifier
        else { return false }
        return expectedCloud == currentCloud && expectedLocal == currentLocal
    }
}
