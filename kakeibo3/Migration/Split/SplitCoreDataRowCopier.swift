import CoreData
import CryptoKit

// MARK: - 同一スキーマのCore Data間でのEntity単位コピー(Step 2B専用)
//
// Step 2Bの移行元(旧Kakeibo3.sqlite)と移行先(Kakeibo3Cloud.sqlite/Kakeibo3Local.sqlite)は
// SwiftData→Core Data移行(B1)の時と違い、モデルのスキーマそのものは完全に同一
// (Cloud/Localへ分割される前と後でEntity定義・属性は1つも変わっていない。Step 1で
// Configurationの割り当てを追加しただけ)。そのためLegacyDTO相当の個別struct変換は不要で、
// NSManagedObjectの属性をKVCで汎用的にコピーするだけで、UUID・bookId・金額を含む
// 全属性値をそのまま維持できる(名前による再紐づけは一切行わない)。
// このモデルはrelationshipを1つも持たない(フラットなUUID外部キー設計)ため、
// オブジェクトグラフの再構築も不要で、Entity単位の独立コピーで安全に完結する。

struct SplitMigrationRow {
    let entityName: String
    let attributes: [String: Any?]
}

enum SplitCoreDataRowCopier {

    /// 指定したcontext上で、そのEntityの全行を属性値のみのプレーンな行として読み取る。
    /// 呼び出し側がcontext.perform/performAndWaitの内側から呼ぶこと。
    static func fetchAllRows(entityName: String, context: NSManagedObjectContext) throws -> [SplitMigrationRow] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let objects = try context.fetch(request)
        return objects.map { object in
            var attributes: [String: Any?] = [:]
            for (attributeName, _) in object.entity.attributesByName {
                attributes[attributeName] = object.value(forKey: attributeName)
            }
            return SplitMigrationRow(entityName: entityName, attributes: attributes)
        }
    }

    /// 行をcontext上へ新規挿入する(save()は呼び出し側の責任)。
    static func insert(_ row: SplitMigrationRow, into context: NSManagedObjectContext) {
        let object = NSEntityDescription.insertNewObject(forEntityName: row.entityName, into: context)
        for (key, value) in row.attributes {
            object.setValue(value, forKey: key)
        }
    }

    // MARK: - チェックサム
    //
    // 行の全属性(UUID・bookId・金額を含む)を正規化した文字列へ変換し、行の並び順に
    // 依存しないようソートしてから連結し、SHA256でハッシュ化する。件数一致だけでは
    // 検出できない「値の入れ替わり」を検知するための、コピー前後の内容一致確認に使う。

    static func checksum(for rows: [SplitMigrationRow]) -> String {
        let canonicalRows = rows.map(canonicalRowString).sorted()
        let joined = canonicalRows.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalRowString(_ row: SplitMigrationRow) -> String {
        let sortedKeys = row.attributes.keys.sorted()
        let parts = sortedKeys.map { key -> String in
            "\(key)=\(canonicalValueString(row.attributes[key] ?? nil))"
        }
        return parts.joined(separator: "&")
    }

    private static func canonicalValueString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "<nil>" }
        if let date = value as? Date {
            return "date:\(date.timeIntervalSince1970)"
        }
        if let uuid = value as? UUID {
            return "uuid:\(uuid.uuidString)"
        }
        if let data = value as? Data {
            return "data:\(data.base64EncodedString())"
        }
        if let number = value as? NSNumber {
            return "num:\(number)"
        }
        return "str:\(value)"
    }

    // MARK: - 値ヘルパー(bookId/id/amountの取り出し。Manifest集計・件数照合で使う)

    static func bookId(of row: SplitMigrationRow) -> UUID? {
        row.attributes["bookId"] as? UUID
    }

    static func idString(of row: SplitMigrationRow) -> String? {
        if let uuid = row.attributes["id"] as? UUID { return uuid.uuidString }
        if let string = row.attributes["id"] as? String { return string }
        return nil
    }

    static func amount(of row: SplitMigrationRow, key: String = "amount") -> Int {
        if let value = row.attributes[key] as? Int64 { return Int(value) }
        if let value = row.attributes[key] as? Int { return value }
        return 0
    }
}
