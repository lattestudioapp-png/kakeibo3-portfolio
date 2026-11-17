import SwiftUI

struct TransferEditView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()

    private var bankAccounts: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var receiveMethodDataObserver = ReceiveMethodDataSync.observer()
    private var receiveMethods: [ReceiveMethodData] { receiveMethodDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentMethods: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }

    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @State private var existing: TransferData

    @State private var date: Date
    @State private var fromId: UUID?
    @State private var toId: UUID?
    @State private var amountText: String
    @State private var memo: String
    @State private var isDatePickerPresented: Bool = false
    @State private var isAmountKeyboardPresented = false
    @FocusState private var isMemoFocused: Bool

    init(existing: TransferData) {
        _existing      = State(initialValue: existing)
        _date          = State(initialValue: existing.date)
        _fromId        = State(initialValue: existing.fromId)
        _toId          = State(initialValue: existing.toId)
        _amountText    = State(initialValue: "\(existing.amount)")
        _memo          = State(initialValue: existing.memo)
    }

    // 振替は帳簿をまたがないため、この振替が属する帳簿（作成時のbookId）の口座・支払い方法だけを候補にする
    private var participantBookId: UUID? {
        existing.bookId ?? currentBookId
    }

    private var activeParticipants: [TransferParticipant] {
        TransferParticipantBuilder.build(
            bankAccounts: bankAccounts.filter { $0.bookId == participantBookId },
            paymentMethods: paymentMethods.filter { $0.bookId == participantBookId },
            receiveMethods: receiveMethods.filter { $0.bookId == participantBookId }
        )
    }

    // 振替元/振替先の候補は、現在帳簿の有効な残高管理対象だけを表示する。
    // 削除済み（isActive=false）の項目は、この振替で使われていたものであっても候補には出さない。
    private var pickerParticipants: [TransferParticipant] {
        activeParticipants
    }

    private var parsedAmount: Int {
        Int(amountText.filter { $0.isNumber }) ?? 0
    }

    private var canSave: Bool {
        guard let f = fromId, let t = toId, f != t, parsedAmount > 0 else { return false }
        // 元々ロックされていた場合でも「変更していない」ならそのまま保存できる（履歴は改変しない方針）。
        // ロックされている参加者を新たに選び直した場合のみ弾く。
        let fromLocked = f != existing.fromId && (pickerParticipants.first(where: { $0.id == f })?.isLocked ?? false)
        let toLocked = t != existing.toId && (pickerParticipants.first(where: { $0.id == t })?.isLocked ?? false)
        return !fromLocked && !toLocked
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        formCard
                        deleteButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .background(AppColors.sheetBackground)
                .navigationTitle("振替を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("キャンセル") { dismiss() }
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(canSave ? AppColors.main : Color.gray.opacity(0.4))
                            .disabled(!canSave)
                    }
                }
                .onChange(of: isMemoFocused) { _, focused in
                    if focused {
                        isAmountKeyboardPresented = false
                    }
                }
            }

            if isAmountKeyboardPresented {
                SheetAmountKeyboardContainer(amountText: $amountText, isPresented: $isAmountKeyboardPresented)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isAmountKeyboardPresented)
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 0) {
            dateRow
            Divider().padding(.horizontal, 16)
            pickerRow(label: "移動元", id: $fromId)
            Divider().padding(.horizontal, 16)
            pickerRow(label: "移動先", id: $toId)
            Divider().padding(.horizontal, 16)
            amountRow
            Divider().padding(.horizontal, 16)
            memoRow
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.line, lineWidth: 1))
    }

    private var dateRow: some View {
        Button {
            isDatePickerPresented = true
        } label: {
            HStack {
                Text("日付")
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
                Text(formattedDate)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(AppColors.main)
            }
            .padding(.horizontal, 16)
            .frame(height: AppLayout.selectionRowHeight)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
        }
    }

    private var datePickerSheet: some View {
        VStack(spacing: 20) {
            DatePicker("日付を選択", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .padding()
            Button {
                isDatePickerPresented = false
            } label: {
                Text("決定")
                    .font(AppFonts.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColors.main)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16)
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.medium])
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    private func pickerRow(label: String, id: Binding<UUID?>) -> some View {
        HStack {
            Text(label)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))
            Spacer()
            Picker("", selection: id) {
                Text("未選択").tag(UUID?.none)
                ForEach(pickerParticipants) { p in
                    if p.isLocked {
                        Label(p.name, systemImage: "lock.fill")
                            .tag(UUID?.some(p.id))
                            .disabled(true)
                    } else {
                        Text(p.name).tag(UUID?.some(p.id))
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(id.wrappedValue == nil ? Color.black.opacity(0.4) : AppColors.main)
            .simultaneousGesture(TapGesture().onEnded {
                isMemoFocused = false
                isAmountKeyboardPresented = false
            })
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.selectionRowHeight)
    }

    private var amountRow: some View {
        HStack {
            Text("金額")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))
            Spacer()
            HStack(spacing: 4) {
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(AppFonts.summaryAmount)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if isAmountKeyboardPresented {
                    BlinkingCursorView(height: 20)
                }
            }
            .frame(width: 150, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture {
                isMemoFocused = false
                DispatchQueue.main.async { isAmountKeyboardPresented = true }
            }
            Text("円")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.selectionRowHeight)
    }

    private var memoRow: some View {
        HStack {
            Text("メモ")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.75))
            Spacer()
            TextField("任意", text: $memo)
                .multilineTextAlignment(.trailing)
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.black.opacity(0.65))
                .focused($isMemoFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.selectionRowHeight)
    }

    // MARK: - Delete button

    private var deleteButton: some View {
        Button {
            // 即時完全削除ではなく、ゴミ箱へ移動する（30日後に自動で完全削除される）
            let existingDate = existing.date
            let existingBookId = existing.bookId ?? currentBookId ?? UUID()
            var trashed = existing
            trashed.isInTrash = true
            trashed.trashedAt = Date()
            TransferDataSync.update(trashed)
            SnapshotUpdateService.handle(.transferDeleted(date: existingDate, bookId: existingBookId))
            dismiss()
        } label: {
            Text("この振替を削除")
                .font(AppFonts.rowTitle)
                .foregroundStyle(Color.red.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.selectionRowHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save

    private func save() {
        guard canSave, let fId = fromId, let tId = toId else { return }
        let originalDate = existing.date
        let fromP = pickerParticipants.first(where: { $0.id == fId })
        let toP   = pickerParticipants.first(where: { $0.id == tId })
        existing.date      = date
        existing.fromType  = fromP?.type  ?? existing.fromType
        existing.fromId    = fId
        existing.fromName  = fromP?.name  ?? existing.fromName
        existing.toType    = toP?.type    ?? existing.toType
        existing.toId      = tId
        existing.toName    = toP?.name    ?? existing.toName
        existing.amount    = parsedAmount
        existing.memo      = memo.trimmingCharacters(in: .whitespaces)
        existing.updatedAt = Date()
        let bookId = existing.bookId ?? currentBookId ?? UUID()
        TransferDataSync.update(existing)
        SnapshotUpdateService.handle(.transferUpdated(oldDate: originalDate, newDate: date, bookId: bookId))
        dismiss()
    }
}
