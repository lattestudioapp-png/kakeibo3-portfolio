import Foundation

// MARK: - 一時的な処理時間計測ツール
//
// log stream/Console経由でのos.Loggerデバッグ出力が実機・シミュレータで確実に拾えなかったため、
// アプリのDocumentsディレクトリに直接ファイルとして書き出す方式にしている。
// NSLock+一度開いたFileHandleの使い回しで、actor/MainActorどちらの文脈からも
// await無しで安全に呼べるようにする（計測対象の処理そのものに余計なactor切り替えを持ち込まないため）。
enum TimingDebugLog {
    nonisolated(unsafe) private static let lock = NSLock()

    private static nonisolated func fileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("timing_debug.log")
    }

    // 呼び出しのたびにFileHandleを開いて閉じる（キャッシュを持たない）。
    // FileHandleを使い回す実装だと、外部からファイルを削除・差し替えた際に
    // 古いinodeへ書き込み続けてしまい（見た目上はファイルが消えたように見える）、
    // 計測結果が一切見えなくなる問題があったため、あえて毎回オープンし直す設計にしている。
    static nonisolated func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL() else { return }
        let line = String(format: "[%.3f] %@\n", CFAbsoluteTimeGetCurrent(), message)
        guard let data = line.data(using: .utf8) else { return }

        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    static nonisolated func mark(_ label: String, since start: CFAbsoluteTime) {
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        write(String(format: "%@: %.2fms", label, elapsedMs))
    }
}
