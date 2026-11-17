import SwiftUI

// MARK: - パスコードロック設定画面

struct PasscodeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var passcodeManager: PasscodeManager

    // MARK: - 状態マシン

    private enum Mode: Hashable {
        case idle
        case enableStep1           // 新パスコード入力（有効化）
        case enableStep2(String)   // 確認入力（有効化）
        case disableVerify         // 現在パスコード確認（無効化）
        case changeVerify          // 現在パスコード確認（変更前）
        case changeStep1           // 新パスコード入力（変更）
        case changeStep2(String)   // 確認入力（変更）
    }

    @State private var mode: Mode = .idle
    @State private var errorMessage: String = ""
    @State private var showsTimeoutPicker = false

    // MARK: - body

    var body: some View {
        ZStack {
            AppColors.sheetBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                if mode == .idle {
                    settingsList
                } else {
                    PasscodeEntryPanel(
                        title: panelTitle,
                        message: panelMessage,
                        errorMessage: errorMessage,
                        onComplete: handleEntry
                    )
                    .id(modeIdentity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showsTimeoutPicker) {
            SessionTimeoutPickerView()
        }
    }

    // MARK: - ヘッダー

    private var headerView: some View {
        HStack(spacing: 0) {
            if mode == .idle {
                HeaderCloseButtonView { dismiss() }
                    .frame(width: AppLayout.headerButtonSize, height: AppLayout.headerButtonSize)
            } else {
                Button {
                    errorMessage = ""
                    mode = .idle
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: AppLayout.headerButtonIconSize, weight: .medium))
                        .foregroundStyle(AppColors.headerButtonIcon)
                        .frame(
                            width: AppLayout.headerButtonSize,
                            height: AppLayout.headerButtonSize
                        )
                        .background(AppColors.headerButtonBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            AppHeaderTitleView(title: "パスコードロック")
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

    // MARK: - 設定リスト（idle）

    private var settingsList: some View {
        ScrollView {
            VStack(spacing: 20) {
                sectionCard {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppColors.main)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("パスコードロック")
                                .font(AppFonts.rowTitle)
                                .foregroundStyle(Color.black.opacity(0.8))
                            Text(passcodeManager.isEnabled ? "ONにしています" : "OFFにしています")
                                .font(AppFonts.caption)
                                .foregroundStyle(Color.black.opacity(0.4))
                        }
                        Spacer()
                        Toggle("", isOn: Binding<Bool>(
                            get: { passcodeManager.isEnabled },
                            set: { newValue in
                                if newValue {
                                    mode = .enableStep1
                                } else {
                                    mode = .disableVerify
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(AppColors.main)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 64)
                }

                if passcodeManager.isEnabled {
                    sectionCard {
                        settingRow(
                            icon: "timer",
                            title: "セッションタイムアウト",
                            value: passcodeManager.sessionTimeoutOption.displayName
                        ) {
                            showsTimeoutPicker = true
                        }
                    }

                    sectionCard {
                        VStack(spacing: 0) {
                            settingRow(icon: "key.fill", title: "パスコードを変更") {
                                mode = .changeVerify
                            }
                            Divider().padding(.leading, 66)
                            settingRow(icon: "trash", title: "パスコードを削除",
                                       titleColor: .red) {
                                mode = .disableVerify
                            }
                        }
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
            .padding(.horizontal, 24)
        }
    }

    private func sectionCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.line, lineWidth: 1)
            )
    }

    private func settingRow(
        icon: String,
        title: String,
        value: String? = nil,
        titleColor: Color = Color.black.opacity(0.8),
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.main)
                    .frame(width: 32)
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(titleColor)
                Spacer()
                if let value {
                    Text(value)
                        .font(AppFonts.body)
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
        }
        .buttonStyle(.plain)
    }

    // MARK: - パネルテキスト

    private var panelTitle: String {
        switch mode {
        case .idle:           return ""
        case .enableStep1:    return "パスコードを入力"
        case .enableStep2:    return "もう一度入力"
        case .disableVerify:  return "現在のパスコード"
        case .changeVerify:   return "現在のパスコード"
        case .changeStep1:    return "新しいパスコード"
        case .changeStep2:    return "もう一度入力"
        }
    }

    private var panelMessage: String {
        switch mode {
        case .idle:           return ""
        case .enableStep1:    return "4桁のパスコードを入力してください"
        case .enableStep2:    return "もう一度入力して確認"
        case .disableVerify:  return "パスコードを入力してください"
        case .changeVerify:   return "変更前のパスコードを入力してください"
        case .changeStep1:    return "新しい4桁のパスコードを入力してください"
        case .changeStep2:    return "もう一度入力して確認"
        }
    }

    private var modeIdentity: String {
        switch mode {
        case .idle:            return "idle"
        case .enableStep1:     return "enableStep1"
        case .enableStep2(let s): return "enableStep2-\(s)"
        case .disableVerify:   return "disableVerify"
        case .changeVerify:    return "changeVerify"
        case .changeStep1:     return "changeStep1"
        case .changeStep2(let s): return "changeStep2-\(s)"
        }
    }

    // MARK: - 入力ハンドラ

    private func handleEntry(_ input: String) {
        errorMessage = ""

        switch mode {
        case .idle:
            break

        case .enableStep1:
            mode = .enableStep2(input)

        case .enableStep2(let first):
            if first == input {
                passcodeManager.save(passcode: input)
                mode = .idle
            } else {
                showError("パスコードが一致しません")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    mode = .enableStep1
                    errorMessage = ""
                }
            }

        case .disableVerify:
            if passcodeManager.verify(input) {
                passcodeManager.disable()
                mode = .idle
            } else {
                showError("パスコードが違います")
            }

        case .changeVerify:
            if passcodeManager.verify(input) {
                mode = .changeStep1
            } else {
                showError("パスコードが違います")
            }

        case .changeStep1:
            mode = .changeStep2(input)

        case .changeStep2(let first):
            if first == input {
                passcodeManager.save(passcode: input)
                mode = .idle
            } else {
                showError("パスコードが一致しません")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    mode = .changeStep1
                    errorMessage = ""
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            errorMessage = message
        }
    }
}
