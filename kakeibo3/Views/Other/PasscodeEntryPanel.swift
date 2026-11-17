import SwiftUI

// MARK: - 4桁パスコード入力パネル（共通UI）
// PasscodeLockView と PasscodeSettingsView の両方で使う

struct PasscodeEntryPanel: View {
    let title: String
    var message: String = ""
    let errorMessage: String
    let onComplete: (String) -> Void

    @State private var input: String = ""
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)

            Text(title)
                .font(AppFonts.screenTitle)
                .foregroundStyle(Color.black)
                .padding(.bottom, 10)

            Group {
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(Color.red)
                } else {
                    Text(message)
                        .foregroundStyle(Color.black.opacity(0.40))
                }
            }
            .font(AppFonts.body)
            .frame(height: 20)
            .padding(.bottom, 44)

            HStack(spacing: 24) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < input.count ? AppColors.main : Color.clear)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(AppColors.main.opacity(0.65), lineWidth: 2)
                        )
                }
            }
            .offset(x: shakeOffset)
            .padding(.bottom, 56)

            numPad

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: errorMessage) { _, newValue in
            guard !newValue.isEmpty else { return }
            triggerShake()
        }
    }

    // MARK: - Number Pad

    private var numPad: some View {
        VStack(spacing: 18) {
            padRow([1, 2, 3])
            padRow([4, 5, 6])
            padRow([7, 8, 9])
            HStack(spacing: 28) {
                Color.clear.frame(width: 72, height: 72)
                numButton("0")
                deleteButton
            }
        }
    }

    private func padRow(_ numbers: [Int]) -> some View {
        HStack(spacing: 28) {
            ForEach(numbers, id: \.self) { n in
                numButton(String(n))
            }
        }
    }

    private func numButton(_ label: String) -> some View {
        Button {
            guard input.count < 4 else { return }
            input += label
            if input.count == 4 {
                let completed = input
                input = ""
                onComplete(completed)
            }
        } label: {
            Text(label)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.black)
                .frame(width: 72, height: 72)
                .background(Color.gray.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button {
            guard !input.isEmpty else { return }
            input.removeLast()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.65))
                .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shake

    private func triggerShake() {
        let d: Double = 0.08
        withAnimation(.easeInOut(duration: d)) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + d) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 2) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 3) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset = 0 }
        }
    }
}
