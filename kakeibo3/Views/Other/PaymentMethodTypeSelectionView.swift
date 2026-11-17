import SwiftUI

enum PaymentAddType: Hashable, Identifiable {
    case cash
    case creditCard
    case electronicMoney
    case debitCard
    case bankAccount
    case securities
    case crypto
    case other

    var id: Self { self }
}

struct PaymentMethodTypeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PaymentAddType) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text("追加する種類を選択")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    typeCard(icon: "yensign.circle", title: "現金") {
                        dismiss()
                        onSelect(.cash)
                    }

                    typeCard(icon: "creditcard.fill", title: "クレジットカード") {
                        dismiss()
                        onSelect(.creditCard)
                    }

                    typeCard(icon: "wave.3.right.circle", title: "電子マネー") {
                        dismiss()
                        onSelect(.electronicMoney)
                    }

                    typeCard(icon: "creditcard", title: "デビットカード") {
                        dismiss()
                        onSelect(.debitCard)
                    }

                    typeCard(icon: "building.columns.fill", title: "銀行口座") {
                        dismiss()
                        onSelect(.bankAccount)
                    }

                    typeCard(icon: "chart.line.uptrend.xyaxis", title: "証券口座") {
                        dismiss()
                        onSelect(.securities)
                    }

                    typeCard(icon: "bitcoinsign.circle", title: "暗号資産") {
                        dismiss()
                        onSelect(.crypto)
                    }

                    typeCard(icon: "ellipsis.circle", title: "その他") {
                        dismiss()
                        onSelect(.other)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("支払いの追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .presentationDetents([.large])
    }

    private func typeCard(
        icon: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColors.main)
                    .frame(width: 36)

                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.8))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}
