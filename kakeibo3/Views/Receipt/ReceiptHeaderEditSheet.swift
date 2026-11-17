import SwiftUI

// MARK: - レシートヘッダー（日付・店舗名・支払い方法）の編集シート
//
// レシート全体に対して1つだけ設定する項目。商品ごとには編集できない。

struct ReceiptHeaderEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var storeName: String
    @State private var paymentMethod: String?

    let availableMethodNames: [String]
    let onSave: (Date, String, String?) -> Void

    init(
        date: Date?,
        storeName: String?,
        paymentMethod: String?,
        availableMethodNames: [String],
        onSave: @escaping (Date, String, String?) -> Void
    ) {
        _date = State(initialValue: date ?? Date())
        _storeName = State(initialValue: storeName ?? "")
        _paymentMethod = State(initialValue: paymentMethod)
        self.availableMethodNames = availableMethodNames
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldSection(title: "日付") {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }

                    fieldSection(title: "店舗名") {
                        TextField("店舗名を入力", text: $storeName)
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    fieldSection(title: "支払い方法") {
                        methodGrid
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("レシート情報を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmedStore = storeName.trimmingCharacters(in: .whitespaces)
                        onSave(date, trimmedStore, paymentMethod)
                        dismiss()
                    }
                }
            }
        }
    }

    private func fieldSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.5))
            content()
        }
    }

    private var methodGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(availableMethodNames, id: \.self) { name in
                Button {
                    paymentMethod = name
                } label: {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(paymentMethod == name ? AppColors.main : Color.black.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(paymentMethod == name ? AppColors.main.opacity(0.12) : Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(paymentMethod == name ? AppColors.main : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
