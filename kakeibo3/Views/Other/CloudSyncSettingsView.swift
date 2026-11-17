import SwiftUI

// MARK: - iCloud同期 設定画面
//
// NSPersistentCloudKitContainerはストアロード時にしかCloudKit接続の有無を決められないため、
// このトグルの変更は次回アプリ起動時に反映される（アプリ側から強制終了はしない。
// CloudSyncSettings.swift冒頭コメント参照）。

struct CloudSyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = CloudSyncSettings.shared

    private var isUserEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isUserEnabled },
            set: { settings.isUserEnabled = $0 }
        )
    }

    var body: some View {
        ZStack {
            AppColors.sheetBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        toggleSection
                        if settings.needsRestartToApply {
                            restartNoticeView
                        }
                        statusSection
                        noteView
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            HeaderCloseButtonView { dismiss() }
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
            Spacer()
            AppHeaderTitleView(title: "iCloud同期")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
            Color.clear
                .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
        }
        .padding(.horizontal, AppLayout.headerButtonHorizontalPadding)
        .padding(.vertical, AppLayout.detailHeaderVerticalPadding)
        .frame(maxWidth: .infinity)
        .background {
            AppColors.main.ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Toggle本体

    private var toggleSection: some View {
        sectionCard(header: "iCloud同期") {
            HStack(spacing: 14) {
                Image(systemName: "icloud")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.main)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud同期")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Text(settings.isUserEnabled ? "この端末と他の端末で同期します" : "この端末だけに保存します")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: isUserEnabledBinding)
                    .labelsHidden()
                    .tint(AppColors.main)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 64)

            Divider().padding(.leading, 66)

            Text("iCloudを使って、このアプリのデータを同じApple Accountの端末間で同期します。")
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    // MARK: - 再起動が必要な旨の案内（強制終了はしない）

    private var restartNoticeView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.main)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("iCloud同期の設定は次回アプリ起動時に反映されます")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.75))
                Text("アプリを一度終了して、もう一度開いてください。")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.main.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    // MARK: - 現在の状態

    private var statusSection: some View {
        sectionCard(header: "状態") {
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 32)
                Text("同期状態")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Text(statusText)
                    .font(AppFonts.caption)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
        }
    }

    private var statusText: String {
        switch settings.state {
        case .disabled: return "同期OFF"
        case .enabling, .disabling: return "同期中"
        case .enabled: return "同期済み"
        case .error(let message): return "エラー: \(message)"
        }
    }

    private var statusIcon: String {
        switch settings.state {
        case .disabled: return "icloud.slash"
        case .enabling, .disabling: return "arrow.triangle.2.circlepath"
        case .enabled: return "checkmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    private var statusColor: Color {
        switch settings.state {
        case .disabled: return Color.black.opacity(0.45)
        case .enabling, .disabling: return AppColors.main
        case .enabled: return Color.green
        case .error: return Color.red
        }
    }

    // MARK: - 注意文

    private var noteView: some View {
        VStack(alignment: .leading, spacing: 10) {
            noteRow("iCloud上のデータや、この端末内のデータは、同期をOFFにしても削除されません。")
            noteRow("初めて同期するこの端末のデータは、iCloud上のデータに追加されます。他の端末で別々に作成した同名のデータ（例：帳簿名）は、自動では統合されず重複して表示されることがあります。")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 4)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)
            Text(text)
                .font(AppFonts.caption)
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - 共通セクションカード

    private func sectionCard<C: View>(header: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.line, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
}
