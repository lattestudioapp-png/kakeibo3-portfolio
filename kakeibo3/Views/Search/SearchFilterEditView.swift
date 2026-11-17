import SwiftUI

// MARK: - 検索条件編集シート
//
// 期間プリセット・開始日・終了日・カテゴリー・支払い/受け取り・種別を
// 1つのシートにまとめて編集する。SearchView からチップタップで開く。

struct SearchFilterEditView: View {
    @ObservedObject var vm: SearchViewModel

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var categoryDataObserver = CategoryDataSync.observer()
    private var categoryDataListRaw: [CategoryData] { categoryDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var bankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var paymentSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    private var categoryDataList: [CategoryData] {
        categoryDataListRaw.filter { $0.bookId == currentBookId }
    }
    private var bankAccounts: [BankAccountData] {
        bankAccountsRaw.filter { $0.bookId == currentBookId }
    }
    private var paymentSettings: [PaymentMethodSettingData] {
        paymentSettingsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var isShowingStartDatePicker = false
    @State private var isShowingEndDatePicker = false
    @State private var isShowingCategoryPicker = false
    @State private var isShowingPaymentMethodPicker = false
    @State private var isShowingReceiveMethodPicker = false
    @State private var isShowingTypePicker = false

    // MARK: - 種別ラベル

    private func typeLabel(_ type: SearchTransactionType) -> String {
        switch type {
        case .all:     return "すべて"
        case .expense: return "支出"
        case .income:  return "収入"
        }
    }

    // MARK: - Category / Method リスト

    private var expenseCategories: [CategoryData] {
        categoryDataList
            .filter { $0.type == "支出" }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.createdAt < $1.createdAt
                    : $0.sortOrder < $1.sortOrder
            }
    }

    private var incomeCategories: [CategoryData] {
        categoryDataList
            .filter { $0.type == "収入" }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.createdAt < $1.createdAt
                    : $0.sortOrder < $1.sortOrder
            }
    }

    private var availablePaymentMethods: [String] {
        let bankNames = bankAccounts
            .filter { $0.isActive && $0.showAsPaymentMethod }
            .map { $0.accountName }
        let methodNames = paymentSettings
            .filter { $0.isActive && $0.showInInputPicker }
            .map { $0.methodName }
        return Array(Set(bankNames + methodNames)).sorted()
    }

    private var availableReceiveMethods: [String] {
        let bankNames = bankAccounts
            .filter { $0.isActive && $0.showAsReceiveMethod }
            .map { $0.accountName }
        let methodNames = paymentSettings
            .filter {
                $0.isActive
                    && $0.useForReceive
                    && $0.type != PaymentMethodType.creditCard.rawValue
            }
            .map { $0.methodName }
        return Array(Set(bankNames + methodNames)).sorted()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sectionCard {
                        filterRow(
                            title: "開始日",
                            valueText: vm.startDate.map { formatFilterDate($0) } ?? "指定なし"
                        ) {
                            isShowingStartDatePicker = true
                        }
                        Divider().padding(.horizontal, 16)
                        filterRow(
                            title: "終了日",
                            valueText: vm.endDate.map { formatFilterDate($0) } ?? "指定なし"
                        ) {
                            isShowingEndDatePicker = true
                        }
                    }

                    sectionCard {
                        filterRow(
                            title: "種別",
                            valueText: typeLabel(vm.selectedType)
                        ) {
                            isShowingTypePicker = true
                        }

                        Divider().padding(.horizontal, 16)
                        filterRow(
                            title: "カテゴリー",
                            valueText: vm.selectedCategory ?? "未選択"
                        ) {
                            isShowingCategoryPicker = true
                        }

                        if vm.selectedType != .income {
                            Divider().padding(.horizontal, 16)
                            filterRow(
                                title: "支払い",
                                valueText: vm.selectedPayment ?? "未選択"
                            ) {
                                isShowingPaymentMethodPicker = true
                            }
                        }

                        if vm.selectedType != .expense {
                            Divider().padding(.horizontal, 16)
                            filterRow(
                                title: "受け取り",
                                valueText: vm.selectedReceive ?? "未選択"
                            ) {
                                isShowingReceiveMethodPicker = true
                            }
                        }
                    }

                    Button {
                        vm.resetAllFilters()
                    } label: {
                        Text("条件をすべてクリア")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(AppColors.sheetBackground)
            .navigationTitle("検索条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.main)
                }
            }
        }
        .sheet(isPresented: $isShowingStartDatePicker) { startDatePickerSheet }
        .sheet(isPresented: $isShowingEndDatePicker)   { endDatePickerSheet }
        .sheet(isPresented: $isShowingCategoryPicker)  { categoryPickerSheet }
        .sheet(isPresented: $isShowingTypePicker)      { typePickerSheet }
        .sheet(isPresented: $isShowingPaymentMethodPicker) {
            pickerSheet(
                title: "支払い",
                options: availablePaymentMethods,
                selectedOption: $vm.selectedPayment,
                isPresented: $isShowingPaymentMethodPicker
            )
        }
        .sheet(isPresented: $isShowingReceiveMethodPicker) {
            pickerSheet(
                title: "受け取り",
                options: availableReceiveMethods,
                selectedOption: $vm.selectedReceive,
                isPresented: $isShowingReceiveMethodPicker
            )
        }
    }

    // MARK: - カード

    private func sectionCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.line, lineWidth: 1)
            )
    }

    // MARK: - Filter Row

    private func filterRow(
        title: String,
        valueText: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                    .font(AppFonts.rowTitle)
                    .foregroundStyle(Color.black.opacity(0.78))
                Spacer()
                Text(valueText)
                    .font(AppFonts.body)
                    .foregroundStyle(Color.black.opacity(0.38))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type Picker Sheet

    private var typePickerSheet: some View {
        NavigationStack {
            List {
                ForEach([SearchTransactionType.all, .expense, .income], id: \.self) { type in
                    Button {
                        vm.setTransactionType(type)
                        isShowingTypePicker = false
                    } label: {
                        HStack {
                            Text(typeLabel(type)).foregroundStyle(.primary)
                            Spacer()
                            if vm.selectedType == type {
                                Image(systemName: "checkmark").foregroundStyle(AppColors.main)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("種別")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Date Picker Sheets

    private var startDatePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: Binding(
                    get: { vm.startDate ?? Date() },
                    set: { newDate in
                        vm.startDate = newDate
                        if let end = vm.endDate, newDate > end { vm.endDate = nil }
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .padding(.horizontal, 16)
            .navigationTitle("開始日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("指定しない") {
                        vm.startDate = nil
                        isShowingStartDatePicker = false
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        if vm.startDate == nil { vm.startDate = Date() }
                        isShowingStartDatePicker = false
                    }
                }
            }
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.medium])
    }

    private var endDatePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: Binding(
                    get: { vm.endDate ?? Date() },
                    set: { newDate in
                        vm.endDate = newDate
                        if let start = vm.startDate, newDate < start { vm.startDate = nil }
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .padding(.horizontal, 16)
            .navigationTitle("終了日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("指定しない") {
                        vm.endDate = nil
                        isShowingEndDatePicker = false
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        if vm.endDate == nil { vm.endDate = Date() }
                        isShowingEndDatePicker = false
                    }
                }
            }
        }
        .background(AppColors.sheetBackground)
        .presentationDetents([.medium])
    }

    // MARK: - Category Picker Sheet

    private var categoryPickerSheet: some View {
        NavigationStack {
            List {
                Button {
                    vm.selectedCategory = nil
                    isShowingCategoryPicker = false
                } label: {
                    HStack {
                        Text("選択しない").foregroundStyle(.red)
                        Spacer()
                        if vm.selectedCategory == nil {
                            Image(systemName: "checkmark").foregroundStyle(AppColors.main)
                        }
                    }
                }
                .buttonStyle(.plain)

                Section("支出カテゴリ") {
                    ForEach(expenseCategories) { category in
                        Button {
                            vm.selectedCategory = category.name
                            isShowingCategoryPicker = false
                        } label: {
                            HStack {
                                Text(category.name).foregroundStyle(.primary)
                                Spacer()
                                if vm.selectedCategory == category.name {
                                    Image(systemName: "checkmark").foregroundStyle(AppColors.main)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("収入カテゴリ") {
                    ForEach(incomeCategories) { category in
                        Button {
                            vm.selectedCategory = category.name
                            isShowingCategoryPicker = false
                        } label: {
                            HStack {
                                Text(category.name).foregroundStyle(.primary)
                                Spacer()
                                if vm.selectedCategory == category.name {
                                    Image(systemName: "checkmark").foregroundStyle(AppColors.main)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("カテゴリー")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Generic Picker Sheet

    private func pickerSheet(
        title: String,
        options: [String],
        selectedOption: Binding<String?>,
        isPresented: Binding<Bool>
    ) -> some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedOption.wrappedValue = nil
                        isPresented.wrappedValue = false
                    } label: {
                        HStack {
                            Text("クリア").foregroundStyle(.red)
                            Spacer()
                            if selectedOption.wrappedValue == nil {
                                Image(systemName: "checkmark").foregroundStyle(AppColors.main)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    if options.isEmpty {
                        Text("データがありません").foregroundStyle(.secondary)
                    } else {
                        ForEach(options, id: \.self) { option in
                            Button {
                                selectedOption.wrappedValue = option
                                isPresented.wrappedValue = false
                            } label: {
                                HStack {
                                    Text(option).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedOption.wrappedValue == option {
                                        Image(systemName: "checkmark").foregroundStyle(AppColors.main)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func formatFilterDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
