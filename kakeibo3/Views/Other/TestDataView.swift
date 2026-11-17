import SwiftUI

// MARK: - 開発用テストデータ管理画面

struct TestDataView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showsCreateConfirm = false
    @State private var showsDeleteConfirm = false
    @State private var resultMessage: String? = nil
    @State private var selectedYears = 1
    // テストデータ生成（特に長期間）は数千件規模の挿入になりうるため、
    // メインスレッドで同期実行するとUIが固まる。バックグラウンドで実行する。
    @State private var isGenerating = false

    // 性能テストデータ・性能測定モード用
    @State private var showsPerfCreateConfirm = false
    @State private var showsPerfDeleteConfirm = false
    @State private var perfResultMessage: String? = nil
    @State private var isRunningBenchmark = false

    private let yearOptions = [1, 3, 5, 10]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // 注意書き
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("この機能は開発用です。\nテスト用データには isTestData フラグが付与され、削除時も本番データには一切影響しません。")
                            .font(AppFonts.body)
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))

                    // 作成内容の説明
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("作成されるテストデータ")

                        VStack(spacing: 0) {
                            descRow(icon: "building.columns", text: "銀行口座 3件（三井住友銀行・南都銀行・SBI証券）")
                            Divider().padding(.leading, 44)
                            descRow(icon: "creditcard.fill", text: "クレジットカード 2件（三井住友カード・楽天カード）")
                            Divider().padding(.leading, 44)
                            descRow(icon: "yensign.circle", text: "その他 4件（現金・PayPay・Suica・NISA）")
                            Divider().padding(.leading, 44)
                            descRow(icon: "repeat", text: "固定費 4件（家賃・スマホ代・Netflix・保険）")
                            Divider().padding(.leading, 44)
                            descRow(icon: "arrow.down.circle", text: "定期収入 3件（給料・仕送り・副業収入）")
                            Divider().padding(.leading, 44)
                            descRow(icon: "list.bullet", text: "取引履歴 7件（支出5件・収入2件）")
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
                        .padding(.horizontal, 0)
                    }

                    // 作成する期間
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("作成する期間")

                        Picker("作成する期間", selection: $selectedYears) {
                            ForEach(yearOptions, id: \.self) { years in
                                Text("\(years)年分").tag(years)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // ボタン
                    VStack(spacing: 12) {
                        Button {
                            showsCreateConfirm = true
                        } label: {
                            Label("テストデータを作成", systemImage: "plus.circle.fill")
                                .font(AppFonts.button)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(AppColors.main)
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)

                        Button {
                            showsDeleteConfirm = true
                        } label: {
                            Label("テストデータを削除", systemImage: "trash.fill")
                                .font(AppFonts.button)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .foregroundStyle(Color.red.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)
                    }

                    // 進行中インジケーター
                    if isGenerating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("処理中…")
                                .font(AppFonts.body)
                                .foregroundStyle(Color.black.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    // 結果メッセージ
                    if let msg = resultMessage {
                        Text(msg)
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.main)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.main.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Divider().padding(.vertical, 4)

                    // 性能テストデータ・性能測定モード
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("性能テストデータ（20年ヘビーユーザー想定）")

                        VStack(spacing: 0) {
                            descRow(icon: "clock.arrow.circlepath", text: "期間 20年・取引 約36,500件")
                            Divider().padding(.leading, 44)
                            descRow(icon: "building.columns", text: "銀行口座6・クレジットカード6・その他20")
                            Divider().padding(.leading, 44)
                            descRow(icon: "tag", text: "支出カテゴリ50・収入カテゴリ25")
                            Divider().padding(.leading, 44)
                            descRow(icon: "repeat", text: "固定費50・定期収入20・定期振替30")
                            Divider().padding(.leading, 44)
                            descRow(icon: "photo", text: "添付写真 約2,500枚")
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
                    }

                    VStack(spacing: 12) {
                        Button {
                            showsPerfCreateConfirm = true
                        } label: {
                            Label("性能テストデータを作成", systemImage: "gauge.with.dots.needle.67percent")
                                .font(AppFonts.button)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(AppColors.main)
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating || isRunningBenchmark)

                        Button {
                            showsPerfDeleteConfirm = true
                        } label: {
                            Label("性能テストデータを削除", systemImage: "trash.fill")
                                .font(AppFonts.button)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .foregroundStyle(Color.red.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating || isRunningBenchmark)

                        Button {
                            runBenchmark()
                        } label: {
                            Label("性能測定モードを実行", systemImage: "speedometer")
                                .font(AppFonts.button)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .foregroundStyle(AppColors.main)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.main.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating || isRunningBenchmark)
                    }

                    Text("計測結果はXcodeのコンソールに出力されます。")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.4))

                    if isGenerating || isRunningBenchmark {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(isRunningBenchmark ? "計測中…" : "処理中…")
                                .font(AppFonts.body)
                                .foregroundStyle(Color.black.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    if let msg = perfResultMessage {
                        Text(msg)
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.main)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(AppColors.main.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("開発用テストデータ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        // 作成確認
        .confirmationDialog(
            "テストデータを作成しますか？",
            isPresented: $showsCreateConfirm,
            titleVisibility: .visible
        ) {
            Button("作成する（既存のテストデータを削除して再作成）") {
                runInBackground(
                    successMessage: "テストデータ（\(selectedYears)年分）を作成しました",
                    failureMessagePrefix: "作成に失敗しました"
                ) {
                    try TestDataGenerator.createTestData(monthsCount: selectedYears * 12)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("既存のテストデータ（isTestData = true）を削除してから\(selectedYears)年分の新しいデータを作成します。")
        }
        // 削除確認
        .confirmationDialog(
            "テストデータを削除しますか？",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                runInBackground(
                    successMessage: "テストデータを削除しました",
                    failureMessagePrefix: "削除に失敗しました"
                ) {
                    try TestDataGenerator.deleteTestData()
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("作成済みのテストデータだけを削除します。\n手動で作成したデータは削除されません。")
        }
        // 性能テストデータ作成確認
        .confirmationDialog(
            "性能テストデータを作成しますか？",
            isPresented: $showsPerfCreateConfirm,
            titleVisibility: .visible
        ) {
            Button("作成する（既存のテストデータを削除して再作成・数十秒かかります）") {
                isGenerating = true
                perfResultMessage = nil
                Task.detached(priority: .userInitiated) {
                    do {
                        // 【Swift Concurrency】PerformanceTestDataGenerator.generate()は
                        // (プロジェクトの既定MainActor分離設定により)@MainActor隔離されている。
                        // Task.detachedの非隔離コンテキストから直接呼ぶとactor hopが一切
                        // 挿入されず、未同期のままCore Data層に触れてしまうため、
                        // 明示的にawait MainActor.run{}でhopしてから呼ぶ。
                        let summaryDescription = try await MainActor.run { try PerformanceTestDataGenerator.generate().description }
                        print(summaryDescription)
                        await MainActor.run {
                            perfResultMessage = summaryDescription
                            isGenerating = false
                        }
                    } catch {
                        await MainActor.run {
                            perfResultMessage = "作成に失敗しました: \(error.localizedDescription)"
                            isGenerating = false
                        }
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("20年分・約36,500件の性能テストデータを作成します。写真も約2,500枚生成するため数十秒かかります。")
        }
        // 性能テストデータ削除確認
        .confirmationDialog(
            "性能テストデータを削除しますか？",
            isPresented: $showsPerfDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                runInBackground(
                    successMessage: "性能テストデータを削除しました",
                    failureMessagePrefix: "削除に失敗しました"
                ) {
                    try PerformanceTestDataGenerator.deleteAll()
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("性能テストデータ（添付写真ファイルを含む）を削除します。")
        }
    }

    // MARK: - 性能測定モード
    //
    // CSV/バックアップ/Snapshot再構築はそれ自体が実際の処理そのものであり、
    // この計測中は数秒〜十数秒UIが反応しなくなる（開発者向け診断モードのため許容する）。

    private func runBenchmark() {
        isRunningBenchmark = true
        perfResultMessage = nil
        Task { @MainActor in
            // "計測中…" 表示を1フレーム描画させてから重い処理に入る
            try? await Task.sleep(nanoseconds: 50_000_000)
            let results = PerformanceBenchmark.runAll()
            let summaryText = results.map { r in
                let detail = r.detail.map { " (\($0))" } ?? ""
                return String(format: "%@: %.2f ms%@", r.label, r.milliseconds, detail)
            }.joined(separator: "\n")
            perfResultMessage = "=== 性能測定結果 ===\n\(summaryText)"
            isRunningBenchmark = false
        }
    }

    // MARK: - バックグラウンド実行ヘルパー
    //
    // 【Swift Concurrency違反の修正】TestDataGenerator.createTestData/deleteTestData、
    // PerformanceTestDataGenerator.deleteAllは、いずれも(プロジェクトの既定MainActor分離
    // 設定により)@MainActor隔離されている。以前はTask.detachedの非隔離コンテキストから
    // `operation()`を直接(awaitを付けずに)呼んでおり、actor hopが一切挿入されないまま
    // Core Data層に触れていた。`operation`の型が素の`() throws -> Void`で、呼び出し元の
    // MainActor隔離が型として伝播しなかったため、コンパイラにも検知されず警告すら
    // 出ていなかった(CoreDataConcurrencyStressTests.swiftで見つかった、MainActor隔離
    // APIをasync文脈から未同期に呼んでいた問題と同種の違反)。
    //
    // 修正：`operation()`自体をawait MainActor.run{}で正しくhopしてから呼ぶ。これにより
    // Swift Concurrencyのルール通りに安全になる。この画面は開発者専用の診断ツールであり、
    // このファイルの既存のrunBenchmark()も同様の理由でメインスレッドをブロックする設計を
    // 既に採用している(「この計測中は数秒〜十数秒UIが反応しなくなる（開発者向け診断モード
    // のため許容する）」と明記済み)ため、同じ考え方を踏襲する。
    private func runInBackground(
        successMessage: String,
        failureMessagePrefix: String,
        operation: @escaping () throws -> Void
    ) {
        isGenerating = true
        resultMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                try await MainActor.run { try operation() }
                await MainActor.run {
                    resultMessage = successMessage
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    resultMessage = "\(failureMessagePrefix): \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }

    private func descRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.main.opacity(0.7))
                .frame(width: 22)
            Text(text)
                .font(AppFonts.body)
                .foregroundStyle(Color.black.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}
