import SwiftUI
import UIKit

// MARK: - キーボード ButtonStyle

struct AmountKeyboardButtonStyle: ButtonStyle {
    let normalColor: Color
    let pressedColor: Color
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(configuration.isPressed ? pressedColor : normalColor)
                    .shadow(
                        color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.10),
                        radius: configuration.isPressed ? 0.5 : 2.5,
                        x: 0,
                        y: configuration.isPressed ? 0 : 1.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - 削除キー長押し状態管理

private final class DeletePressState {
    var longPressTimer: Timer?
    var repeatTimer: Timer?
    var isLongPressActive = false

    func startPress(onRepeat: @escaping () -> Void) {
        isLongPressActive = false
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            isLongPressActive = true
            onRepeat()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in onRepeat() }
            if let t = repeatTimer { RunLoop.main.add(t, forMode: .common) }
        }
        if let t = longPressTimer { RunLoop.main.add(t, forMode: .common) }
    }

    func endPress() -> Bool {
        let wasActive = isLongPressActive
        longPressTimer?.invalidate(); longPressTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
        isLongPressActive = false
        return wasActive
    }
}

// MARK: - 金額専用電卓キーボード

struct CalculatorKeyboardView: View {
    @Binding var amountText: String
    @Binding var isPresented: Bool

    private let calculator = ExpressionCalculator()

    // MARK: - 状態

    @Environment(\.scenePhase) private var scenePhase
    @State private var isCalcMode = false
    @State private var isDeletePressed = false
    @State private var deletePressState = DeletePressState()

    // MARK: - 色

    private let keyboardBg    = Color(UIColor.systemGray6)
    private let numKeyColor   = Color.white
    private let opKeyColor    = Color(red: 0.82, green: 0.82, blue: 0.84)
    private let pressedNum    = Color(UIColor.systemGray4)
    private let pressedOp     = Color(UIColor.systemGray3)
    private let pressedDelete = Color.black.opacity(0.10)
    private let keyText       = Color.black
    private let controlColor  = AppColors.main

    // MARK: - 固定定数

    private let horizontalPadding: CGFloat = 12
    private let maxKeyboardWidth: CGFloat  = 404
    private let operatorWidth: CGFloat     = 72
    private let keyboardTopRadius: CGFloat = 20
    private let kSpacing: CGFloat          = 7
    private let kInnerPad: CGFloat         = 6

    // MARK: - Body

    var body: some View {
        // キーボード本体の高さを共通定数で固定。
        // 以前は proxy.size.height * 0.38 で動的計算していたが、
        // TabView 内 (InputView) とシート画面 (TransferFormView 等) でコンテキストが異なり
        // キーボード高さが変わるため、全画面共通定数に統一する。
        let totalKbH: CGFloat  = AppLayout.calculatorKeyboardBodyHeight
        let ctrlH: CGFloat     = min(max(totalKbH * 0.22, 48), 62)
        let kbBodyH: CGFloat   = totalKbH - ctrlH

        let kAvail  = kbBodyH - kInnerPad * 2 - kSpacing * 3
        let kh: CGFloat  = min(max(kAvail / 4, 48), 66)
        let kcr: CGFloat = min(kh * 0.20, 13)

        let extraH: CGFloat  = isCalcMode ? kh + kSpacing : 0

        GeometryReader { proxy in
            // GeometryReader はスペーサー高さの計算のみに使用（キーボード高さは定数）
            let spacerH: CGFloat = max(proxy.size.height - totalKbH - extraH, 0)

            VStack(spacing: 0) {
                // フォームへタッチを通過させる透明エリア
                Color.clear
                    .frame(height: spacerH)
                    .allowsHitTesting(false)

                // 閉じる/電卓バー + キーグリッドを統一グレー背景で包む
                ZStack(alignment: .top) {
                    keyboardBg
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: keyboardTopRadius,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: keyboardTopRadius
                        ))

                    VStack(spacing: 0) {
                        controlBarView(height: ctrlH)

                        GeometryReader { geo in
                            let kw = min(geo.size.width - horizontalPadding * 2, maxKeyboardWidth)
                            // calcRow 用 4 等分幅 / mainGrid 数字3列幅
                            let nw = (kw - operatorWidth - kSpacing * 3) / 3
                            let cw = (kw - kSpacing * 3) / 4

                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                keyContentView(nw: nw, cw: cw, kh: kh, kcr: kcr)
                                    .padding(.top, kInnerPad)
                                    .padding(.bottom, kInnerPad)
                                    .frame(width: kw)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: kbBodyH + extraH)
                    }
                }
            }
        }
        .onDisappear {
            _ = deletePressState.endPress()
            isDeletePressed = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                _ = deletePressState.endPress()
                isDeletePressed = false
            }
        }
    }

    // MARK: - コントロールバー

    private func controlBarView(height: CGFloat) -> some View {
        HStack(alignment: .center) {
            Button { isPresented = false } label: {
                Text("閉じる")
                    .font(AppFonts.button)
                    .foregroundStyle(controlColor)
                    .frame(width: 70, height: 36)
                    .background(Color.white.opacity(0.90))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.22)) { isCalcMode.toggle() }
            } label: {
                Text("電卓")
                    .font(.system(size: 15, weight: isCalcMode ? .bold : .semibold))
                    .foregroundStyle(isCalcMode ? Color.white : controlColor)
                    .frame(width: 54, height: 36)
                    .background(isCalcMode ? controlColor : Color.white.opacity(0.90))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
    }

    // MARK: - キー全体

    @ViewBuilder
    private func keyContentView(nw: CGFloat, cw: CGFloat, kh: CGFloat, kcr: CGFloat) -> some View {
        VStack(spacing: 0) {
            if isCalcMode {
                calcRowView(cellWidth: cw, kh: kh, kcr: kcr)
                    .padding(.bottom, kSpacing)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            mainGridView(nw: nw, kh: kh, kcr: kcr)
        }
    }

    // MARK: - 電卓モード行（÷ × ( )）

    private func calcRowView(cellWidth: CGFloat, kh: CGFloat, kcr: CGFloat) -> some View {
        HStack(spacing: kSpacing) {
            calcKeyView("÷", w: cellWidth, kh: kh, kcr: kcr)
            calcKeyView("×", w: cellWidth, kh: kh, kcr: kcr)
            calcKeyView("(", w: cellWidth, kh: kh, kcr: kcr)
            calcKeyView(")", w: cellWidth, kh: kh, kcr: kcr)
        }
    }

    private func calcKeyView(_ title: String, w: CGFloat, kh: CGFloat, kcr: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleTap(title)
        } label: {
            Text(title)
                .font(.system(size: max(kh * 0.38, 16), weight: .regular))
                .foregroundStyle(keyText)
                .frame(width: w, height: kh)
        }
        .buttonStyle(AmountKeyboardButtonStyle(
            normalColor: opKeyColor,
            pressedColor: pressedOp,
            cornerRadius: kcr
        ))
    }

    // MARK: - メイングリッド
    //
    // 数字ゾーン（3列）を VStack-of-HStack で構成。
    // 最下行: 0 ワイド（2列分）+ ⌫
    // 演算子ゾーン（1列）: - / + / = (縦長)

    private func mainGridView(nw: CGFloat, kh: CGFloat, kcr: CGFloat) -> some View {
        HStack(alignment: .top, spacing: kSpacing) {

            // 数字ゾーン
            VStack(spacing: kSpacing) {
                HStack(spacing: kSpacing) {
                    numKeyView("1", w: nw, kh: kh, kcr: kcr)
                    numKeyView("2", w: nw, kh: kh, kcr: kcr)
                    numKeyView("3", w: nw, kh: kh, kcr: kcr)
                }
                HStack(spacing: kSpacing) {
                    numKeyView("4", w: nw, kh: kh, kcr: kcr)
                    numKeyView("5", w: nw, kh: kh, kcr: kcr)
                    numKeyView("6", w: nw, kh: kh, kcr: kcr)
                }
                HStack(spacing: kSpacing) {
                    numKeyView("7", w: nw, kh: kh, kcr: kcr)
                    numKeyView("8", w: nw, kh: kh, kcr: kcr)
                    numKeyView("9", w: nw, kh: kh, kcr: kcr)
                }
                // 0 ワイド（2列分） + ⌫
                HStack(spacing: kSpacing) {
                    numKeyView("0", w: nw * 2 + kSpacing, kh: kh, kcr: kcr)
                    deleteKeyView(w: nw, kh: kh, kcr: kcr)
                }
            }

            // 演算子ゾーン
            VStack(spacing: kSpacing) {
                opKeyView("-", kh: kh, kcr: kcr)
                opKeyView("+", kh: kh, kcr: kcr)
                tallEqualsView(kh: kh, kcr: kcr)
            }
        }
    }

    // MARK: - 数字キー

    private func numKeyView(_ title: String, w: CGFloat, kh: CGFloat, kcr: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleTap(title)
        } label: {
            Text(title)
                .font(.system(size: max(kh * 0.56, 20), weight: .regular))
                .foregroundStyle(keyText)
                .frame(width: w, height: kh)
        }
        .buttonStyle(AmountKeyboardButtonStyle(
            normalColor: numKeyColor,
            pressedColor: pressedNum,
            cornerRadius: kcr
        ))
    }

    // MARK: - 演算子キー（- / +）

    private func opKeyView(_ title: String, kh: CGFloat, kcr: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleTap(title)
        } label: {
            Text(title)
                .font(.system(size: max(kh * 0.50, 20), weight: .regular))
                .foregroundStyle(keyText)
                .frame(width: operatorWidth, height: kh)
        }
        .buttonStyle(AmountKeyboardButtonStyle(
            normalColor: opKeyColor,
            pressedColor: pressedOp,
            cornerRadius: kcr
        ))
    }

    // MARK: - = キー（縦長・行 3〜4 を占有）

    private func tallEqualsView(kh: CGFloat, kcr: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handleTap("=")
        } label: {
            Text("=")
                .font(.system(size: max(kh * 0.52, 22), weight: .regular))
                .foregroundStyle(keyText)
                .frame(width: operatorWidth, height: kh * 2 + kSpacing)
        }
        .buttonStyle(AmountKeyboardButtonStyle(
            normalColor: opKeyColor,
            pressedColor: pressedOp,
            cornerRadius: kcr
        ))
    }

    // MARK: - 削除キー（長押し対応）

    private func deleteKeyView(w: CGFloat, kh: CGFloat, kcr: CGFloat) -> some View {
        Text("⌫")
            .font(.system(size: max(kh * 0.38, 16), weight: .regular))
            .foregroundStyle(keyText)
            .frame(width: w, height: kh)
            .background(
                RoundedRectangle(cornerRadius: kcr)
                    .fill(isDeletePressed ? pressedDelete : numKeyColor)
                    .shadow(
                        color: Color.black.opacity(isDeletePressed ? 0.04 : 0.10),
                        radius: isDeletePressed ? 0.5 : 2.5,
                        x: 0,
                        y: isDeletePressed ? 0 : 1.5
                    )
            )
            .scaleEffect(isDeletePressed ? 0.96 : 1.0)
            .opacity(isDeletePressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isDeletePressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isDeletePressed else { return }
                        isDeletePressed = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        deletePressState.startPress {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            deleteOneCharacter()
                        }
                    }
                    .onEnded { _ in
                        let wasLongPress = deletePressState.endPress()
                        isDeletePressed = false
                        if !wasLongPress { deleteOneCharacter() }
                    }
            )
    }

    // MARK: - 削除

    private func deleteOneCharacter() {
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
    }

    // MARK: - ボタン処理

    private func handleTap(_ title: String) {
        switch title {
        case "0"..."9":
            amountText += title
        case "+", "-", "×", "÷", "(", ")":
            amountText += title
        case "=":
            calculateExpression()
        default:
            break
        }
    }

    private func calculateExpression() {
        do {
            let result = try calculator.calculate(amountText)
            amountText = String(result)
        } catch {
            print("計算できません")
        }
    }
}
