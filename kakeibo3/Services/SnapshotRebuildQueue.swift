import Foundation
import os

// MARK: - SnapshotManager/AnalysisSnapshotManagerの再構築を、メインスレッドを塞がずに実行するためのキュー
//
// SnapshotManager.rebuildAll/AnalysisSnapshotManager.rebuildAllは全期間の取引を読み直す重い処理のため、
// 呼び出し元のView（onAppear/onDisappear/保存ボタンなど）から直接同期呼び出しすると、
// そのタイミングでメインスレッドが固まる。
//
// Core Data移行（Phase 1・Snapshot系）：SnapshotManager/AnalysisSnapshotManagerが
// CoreDataStack.shared.container.viewContextを直接使うようになったため、ModelContainer/ModelContextの
// 受け渡しは不要になった。actorによる直列化（同時に複数のジョブが積まれても順序を守って処理する）・
// 重複合流・「呼んだ順序で処理される」保証という役割は変わらず維持する。
//
// このactorは以下を保証する:
// 1. request系メソッドは即座に返る（呼び出し元のView処理をブロックしない）
// 2. 実際の処理はactorの実行コンテキスト（メインスレッド外）で行われる
// 3. 同時に複数のジョブが積まれても直列に処理し、同じCoreDataStackに対する
//    競合を避ける
// 4. request系メソッドを呼んだ順序 = ジョブがキューに積まれる順序（下記コメント参照）

actor SnapshotRebuildQueue {
    static let shared = SnapshotRebuildQueue()

    private static let logger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "SnapshotRebuildQueue")

    // Equatable: enqueue側で「同じジョブが既に積まれていれば積まない」重複合流に使う。
    private enum Job: Equatable {
        case fullRebuild
        case bankAccountTouch(UUID)
        case methodTouch(String)
    }

    // 【重要】pendingJobsはactor隔離から意図的に外し、NSLockで保護した static var にしている。
    //
    // 以前は pendingJobs が actor-isolated var で、nonisolated な enqueue() から
    // `Task { await push(job:) }` で積んでいた。しかしこの Task { } は生成しただけで、
    // 実際に pendingJobs.append が走るのはそのTaskがactorの実行コンテキストへ入れた瞬間であり、
    // 複数の enqueue() 呼び出しが短時間に重なると「呼んだ順序」と「実際にキューへ積まれる順序」が
    // 一致する保証がなかった（Swiftの非構造化Taskはスケジューリング順序を保証しない）。
    //
    // これにより、ロック切替のtouchジョブとreconcileLocksによるフル再構築ジョブの処理順序が
    // 入れ替わり得ることが実際にデータ破損の原因になった（差分加算/減算方式を試した際に発覚）。
    // 現在の再計算ロジック自体は冪等なので実害はないが、「呼んだ順序で処理される」という
    // 直感的な保証がないこと自体がバグの温床になるため、根本から直す。
    //
    // enqueue() 自体を同期処理にしてロック内で直接appendすることで、
    // 「呼び出したスレッド上でappendが完了してから次の行に進む」＝呼んだ順序が保証される。
    nonisolated(unsafe) private static var pendingJobs: [Job] = []
    nonisolated(unsafe) private static let jobsLock = NSLock()

    // isRunningはactor-isolatedのままでよい（actorのメソッドは常に直列実行されるため、
    // 複数のkick()呼び出しがこのフラグを同時に読み書きすることはない）。
    private var isRunning = false

    private init() {}

    // 即座に返る。
    nonisolated func requestRebuild() {
        Self.logger.debug("requestRebuild queued")
        enqueue(.fullRebuild)
    }

    // ロックのON/OFFなど、影響が1つの銀行口座（+紐づくクレジットカード）に閉じる場合はこちらを使う
    nonisolated func requestBankAccountTouch(bankAccountId: UUID) {
        Self.logger.debug("requestBankAccountTouch queued: \(bankAccountId)")
        enqueue(.bankAccountTouch(bankAccountId))
    }

    // ロックのON/OFFなど、影響が1つの支払い方法（クレジットカード・その他・受け取り方法）に閉じる場合はこちらを使う
    nonisolated func requestMethodTouch(methodName: String) {
        Self.logger.debug("requestMethodTouch queued: \(methodName)")
        enqueue(.methodTouch(methodName))
    }

    // 呼び出したスレッド上で同期的にpendingJobsへ積む（＝呼んだ順序が保証される）。
    // 積んだ後、実処理を進めるためのkick()呼び出しだけを非同期に投げる。
    //
    // 同じジョブが既にpendingJobs内に積まれていれば重複追加しない（合流）。
    // 実処理中の1件と重複した場合は合流しないが、再計算ロジックが冪等（何度実行しても
    // 常に最新の生データから正しく再計算する）なので、重複実行が起きても結果は変わらず安全。
    private nonisolated func enqueue(_ job: Job) {
        Self.jobsLock.lock()
        if !Self.pendingJobs.contains(job) {
            Self.pendingJobs.append(job)
        }
        Self.jobsLock.unlock()
        Task { await kick() }
    }

    private func kick() async {
        guard !isRunning else { return }
        isRunning = true
        await drain()
    }

    private func drain() async {
        while true {
            Self.jobsLock.lock()
            guard !Self.pendingJobs.isEmpty else {
                Self.jobsLock.unlock()
                break
            }
            let job = Self.pendingJobs.removeFirst()
            Self.jobsLock.unlock()

            let jobStart = CFAbsoluteTimeGetCurrent()
            switch job {
            case .fullRebuild:
                Self.logger.debug("running fullRebuild")
                let snapshotResult = SnapshotManager.rebuildAll()
                let analysisResult = AnalysisSnapshotManager.rebuildAll()
                if snapshotResult.hasFailures {
                    Self.logger.error("SnapshotManager.rebuildAll failed for \(snapshotResult.failedBooks.count) book(s)")
                }
                if analysisResult.hasFailures {
                    Self.logger.error("AnalysisSnapshotManager.rebuildAll failed for \(analysisResult.failedBooks.count) book(s)")
                }
                TimingDebugLog.mark("SnapshotRebuildQueue.fullRebuild", since: jobStart)
            case .bankAccountTouch(let id):
                Self.logger.debug("running bankAccountTouch: \(id)")
                SnapshotManager.touchBankAccount(id)
                AnalysisSnapshotManager.touchBankAccount(id)
                TimingDebugLog.mark("SnapshotRebuildQueue.bankAccountTouch(\(id))", since: jobStart)
            case .methodTouch(let name):
                Self.logger.debug("running methodTouch: \(name)")
                SnapshotManager.touchMethodName(name)
                AnalysisSnapshotManager.touchMethodName(name)
                TimingDebugLog.mark("SnapshotRebuildQueue.methodTouch(\(name))", since: jobStart)
            }
        }
        isRunning = false
        Self.logger.debug("queue drained")
    }
}
