import CoreData

// MARK: - 一時Cloud/Localストアへの書き込み(Step 2B専用)
//
// Cloud/Local両方の行を同一のviewContext(CoreDataStack(cloudLocalDirectory:)由来。
// Cloud/Local 2ストアを内部で保持する)へinsertし、最後に1回だけsaveする。
// Core Dataは各Entityの属性値だけで自動的に正しいストア(Cloud/Local)へ振り分けて保存する
// (Entity→Configuration→Storeの対応はStep 1のxcdatamodel設定に従う。呼び出し側で
// 明示的にどちらのストアへ、と指定する必要は無い)。保存失敗時は必ずrollbackする。

enum SplitMigrationTempWriter {
    static func write(_ snapshot: SplitMigrationSourceSnapshot, context: NSManagedObjectContext) throws {
        var thrownError: Error?
        context.performAndWait {
            for (_, rows) in snapshot.cloudRowsByEntity {
                for row in rows {
                    SplitCoreDataRowCopier.insert(row, into: context)
                }
            }
            for (_, rows) in snapshot.localRowsByEntity {
                for row in rows {
                    SplitCoreDataRowCopier.insert(row, into: context)
                }
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                thrownError = error
            }
        }
        if let thrownError {
            throw thrownError
        }
    }
}
