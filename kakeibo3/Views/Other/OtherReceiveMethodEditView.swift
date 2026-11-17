import SwiftUI

struct OtherReceiveMethodEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: ReceiveMethodData?

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    formCard

                    if existing != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background)
            .navigationTitle(existing == nil ? "受け取り方法を追加" : "受け取り方法を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Color.gray.opacity(0.4) : AppColors.main)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let e = existing {
                name = e.methodName
            }
        }
    }

    private var formCard: some View {
        HStack {
            Text("名前")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))
            Spacer()
            TextField("例：こぶた商品券", text: $name)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.selectionRowHeight)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1)
        )
    }

    private var deleteButton: some View {
        Button {
            if var e = existing {
                e.isActive = false
                ReceiveMethodDataSync.update(e)
                dismiss()
            }
        } label: {
            Text("この受け取り方法を削除")
                .font(AppFonts.button)
                .foregroundStyle(Color.red.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.selectionRowHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if var e = existing {
            e.methodName = trimmedName
            ReceiveMethodDataSync.update(e)
        } else {
            ReceiveMethodDataSync.insert(ReceiveMethodData(methodName: trimmedName))
        }
        dismiss()
    }
}
